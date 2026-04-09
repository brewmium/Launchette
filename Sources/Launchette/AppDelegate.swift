import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Carbon hotkey callback (free function for C interop)

private func hotKeyCallback(
	nextHandler: EventHandlerCallRef?,
	event: EventRef?,
	userData: UnsafeMutableRawPointer?
) -> OSStatus {
	AppDelegate.instance?.togglePanel()
	return noErr
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
	static weak var instance: AppDelegate?

	private var statusItem: NSStatusItem!
	private var searchPanel: SearchPanel!
	private let appIndex = AppIndex()
	private var hotKeyRef: EventHotKeyRef?
	private var eventHandlerRef: EventHandlerRef?
	private var hotKeyMenuItem: NSMenuItem!
	private var loginItem: NSMenuItem!
	private var sizeMenuItems: [NSMenuItem] = []
	private var screenMenuItems: [NSMenuItem] = []

	// MARK: Lifecycle

	func applicationDidFinishLaunching(_ notification: Notification) {
		AppDelegate.instance = self
		setupMenuBar()
		installEventHandler()
		registerHotKey()
		searchPanel = SearchPanel(appIndex: appIndex)
		updateSizeCheckmarks()
		updateScreenCheckmarks()
		appIndex.scan()

		let nc = NSWorkspace.shared.notificationCenter
		nc.addObserver(self, selector: #selector(runningAppsChanged),
			name: NSWorkspace.didLaunchApplicationNotification, object: nil)
		nc.addObserver(self, selector: #selector(runningAppsChanged),
			name: NSWorkspace.didTerminateApplicationNotification, object: nil)
	}

	// MARK: Menu bar

	private func setupMenuBar() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		if let button = statusItem.button {
			let icon = SearchPanel.makeLaunchetteIcon(size: 18, tint: NSColor.white.withAlphaComponent(0.7))
			icon.isTemplate = false
			button.image = icon
		}

		let menu = NSMenu()

		let pref = loadHotKeyPreference()
		let keyStr = hotkeyDisplayString(keyCode: pref.keyCode, modifiers: pref.modifiers)
		hotKeyMenuItem = NSMenuItem(title: "Change Hotkey (\(keyStr))...", action: #selector(changeHotKey), keyEquivalent: "")
		hotKeyMenuItem.target = self
		menu.addItem(hotKeyMenuItem)

		let addItem = NSMenuItem(title: "Add Custom App...", action: #selector(addCustomApp), keyEquivalent: "")
		addItem.target = self
		menu.addItem(addItem)

		let rescanItem = NSMenuItem(title: "Rescan Applications", action: #selector(rescan), keyEquivalent: "")
		rescanItem.target = self
		menu.addItem(rescanItem)

		menu.addItem(NSMenuItem.separator())

		let sizeMenu = NSMenu()
		for size in PanelSize.allCases {
			let item = NSMenuItem(title: size.label, action: #selector(changeSize(_:)), keyEquivalent: "")
			item.target = self
			item.tag = size.rawValue
			sizeMenu.addItem(item)
			sizeMenuItems.append(item)
		}
		let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
		sizeItem.submenu = sizeMenu
		menu.addItem(sizeItem)

		let screenMenu = NSMenu()
		for mode in ScreenMode.allCases {
			let item = NSMenuItem(title: mode.label, action: #selector(changeScreenMode(_:)), keyEquivalent: "")
			item.target = self
			item.tag = mode.rawValue
			screenMenu.addItem(item)
			screenMenuItems.append(item)
		}
		let screenItem = NSMenuItem(title: "Open On", action: nil, keyEquivalent: "")
		screenItem.submenu = screenMenu
		menu.addItem(screenItem)

		let manageItem = NSMenuItem(title: "Manage Apps...", action: #selector(showManageApps), keyEquivalent: "")
		manageItem.target = self
		menu.addItem(manageItem)

		menu.addItem(NSMenuItem.separator())

		loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
		loginItem.target = self
		loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
		menu.addItem(loginItem)

		menu.addItem(NSMenuItem.separator())

		let quitItem = NSMenuItem(title: "Quit Launchette", action: #selector(quit), keyEquivalent: "q")
		quitItem.target = self
		menu.addItem(quitItem)

		statusItem.menu = menu
	}

	// MARK: Global hotkey

	private func installEventHandler() {
		var eventType = EventTypeSpec(
			eventClass: OSType(kEventClassKeyboard),
			eventKind: UInt32(kEventHotKeyPressed)
		)
		InstallEventHandler(
			GetEventDispatcherTarget(),
			hotKeyCallback,
			1,
			&eventType,
			nil,
			&eventHandlerRef
		)
	}

	private func registerHotKey() {
		let pref = loadHotKeyPreference()
		let hotKeyID = EventHotKeyID(signature: OSType(0x4C434854), id: 1)
		RegisterEventHotKey(
			pref.keyCode,
			pref.modifiers,
			hotKeyID,
			GetEventDispatcherTarget(),
			0,
			&hotKeyRef
		)
	}

	func togglePanel() {
		if searchPanel.isVisible {
			searchPanel.dismiss()
		} else {
			searchPanel.showPanel()
		}
	}

	// MARK: Hotkey preferences

	private func loadHotKeyPreference() -> (keyCode: UInt32, modifiers: UInt32) {
		let defaults = UserDefaults.standard
		let keyCode: UInt32
		let modifiers: UInt32
		if defaults.object(forKey: "hotKeyKeyCode") != nil {
			keyCode = UInt32(defaults.integer(forKey: "hotKeyKeyCode"))
			modifiers = UInt32(defaults.integer(forKey: "hotKeyModifiers"))
		} else {
			keyCode = UInt32(kVK_Space)
			modifiers = UInt32(cmdKey)
		}
		return (keyCode, modifiers)
	}

	private func saveHotKeyPreference(keyCode: UInt32, modifiers: UInt32) {
		UserDefaults.standard.set(Int(keyCode), forKey: "hotKeyKeyCode")
		UserDefaults.standard.set(Int(modifiers), forKey: "hotKeyModifiers")
	}

	private func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
		if let ref = hotKeyRef {
			UnregisterEventHotKey(ref)
			hotKeyRef = nil
		}
		let hotKeyID = EventHotKeyID(signature: OSType(0x4C434854), id: 1)
		RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
		saveHotKeyPreference(keyCode: keyCode, modifiers: modifiers)

		let keyStr = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
		hotKeyMenuItem.title = "Change Hotkey (\(keyStr))..."
	}

	// MARK: Hotkey display

	private func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
		var s = ""
		if modifiers & UInt32(controlKey) != 0 { s += "\u{2303}" }
		if modifiers & UInt32(optionKey) != 0 { s += "\u{2325}" }
		if modifiers & UInt32(shiftKey) != 0 { s += "\u{21E7}" }
		if modifiers & UInt32(cmdKey) != 0 { s += "\u{2318}" }
		s += Self.keyName(keyCode)
		return s
	}

	private static let keyNames: [UInt32: String] = {
		var m: [UInt32: String] = [
			0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
			0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
			0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
			0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
			0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
			0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
			0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
			0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
			0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
			0x2F: ".", 0x32: "`",
		]
		m[UInt32(kVK_Space)] = "Space"
		m[UInt32(kVK_Return)] = "\u{21A9}"
		m[UInt32(kVK_Tab)] = "\u{21E5}"
		m[UInt32(kVK_Delete)] = "\u{232B}"
		m[UInt32(kVK_ForwardDelete)] = "\u{2326}"
		m[UInt32(kVK_Escape)] = "\u{238B}"
		m[UInt32(kVK_UpArrow)] = "\u{2191}"
		m[UInt32(kVK_DownArrow)] = "\u{2193}"
		m[UInt32(kVK_LeftArrow)] = "\u{2190}"
		m[UInt32(kVK_RightArrow)] = "\u{2192}"
		m[UInt32(kVK_F1)] = "F1"; m[UInt32(kVK_F2)] = "F2"
		m[UInt32(kVK_F3)] = "F3"; m[UInt32(kVK_F4)] = "F4"
		m[UInt32(kVK_F5)] = "F5"; m[UInt32(kVK_F6)] = "F6"
		m[UInt32(kVK_F7)] = "F7"; m[UInt32(kVK_F8)] = "F8"
		m[UInt32(kVK_F9)] = "F9"; m[UInt32(kVK_F10)] = "F10"
		m[UInt32(kVK_F11)] = "F11"; m[UInt32(kVK_F12)] = "F12"
		return m
	}()

	private static func keyName(_ keyCode: UInt32) -> String {
		keyNames[keyCode] ?? "Key\(keyCode)"
	}

	// MARK: Hotkey recorder

	@objc private func changeHotKey() {
		let recorder = HotKeyRecorderPanel()
		recorder.onRecord = { [weak self] keyCode, modifiers in
			self?.updateHotKey(keyCode: keyCode, modifiers: modifiers)
		}
		recorder.beginRecording()
	}

	// MARK: Actions

	@objc private func addCustomApp() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowedContentTypes = [.application]
		panel.allowsMultipleSelection = true
		panel.directoryURL = URL(fileURLWithPath: "/Applications")
		NSApp.activate(ignoringOtherApps: true)
		if panel.runModal() == .OK {
			for url in panel.urls {
				appIndex.addCustomApp(path: url.path)
			}
		}
	}

	@objc private func rescan() {
		appIndex.scan()
	}

	@objc private func changeSize(_ sender: NSMenuItem) {
		guard let size = PanelSize(rawValue: sender.tag) else { return }
		searchPanel.setSize(size)
		updateSizeCheckmarks()
	}

	private func updateSizeCheckmarks() {
		let current = searchPanel.currentSize
		for item in sizeMenuItems {
			item.state = item.tag == current.rawValue ? .on : .off
		}
	}

	@objc private func changeScreenMode(_ sender: NSMenuItem) {
		guard let mode = ScreenMode(rawValue: sender.tag) else { return }
		searchPanel.setScreenMode(mode)
		updateScreenCheckmarks()
	}

	private func updateScreenCheckmarks() {
		let current = searchPanel.screenMode
		for item in screenMenuItems {
			item.state = item.tag == current.rawValue ? .on : .off
		}
	}

	@objc private func toggleLaunchAtLogin() {
		do {
			if SMAppService.mainApp.status == .enabled {
				try SMAppService.mainApp.unregister()
				loginItem.state = .off
			} else {
				try SMAppService.mainApp.register()
				loginItem.state = .on
			}
		} catch {
			NSLog("Launchette: Failed to toggle login item: \(error)")
		}
	}

	@objc private func showManageApps() {
		let panel = ManageAppsPanel(appIndex: appIndex)
		NSApp.activate(ignoringOtherApps: true)
		panel.makeKeyAndOrderFront(nil)
	}

	@objc private func quit() {
		NSApp.terminate(nil)
	}

	@objc private func runningAppsChanged(_ notification: Notification) {
		appIndex.refreshRunningApps()
	}
}

// MARK: - Manage Apps Panel

class ManageAppsPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
	private let appIndex: AppIndex
	private let tabView: NSTabView
	private var recentsTable: NSTableView!
	private var hiddenTable: NSTableView!
	private var recents: [(name: String, path: String, count: Int)] = []
	private var hidden: [(name: String, path: String)] = []

	init(appIndex: AppIndex) {
		self.appIndex = appIndex
		tabView = NSTabView()

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)

		title = "Manage Apps"
		setupUI()
		reload()
		center()
	}

	private func setupUI() {
		tabView.frame = NSRect(x: 10, y: 10, width: 500, height: 360)
		tabView.autoresizingMask = [.width, .height]
		contentView?.addSubview(tabView)

		// Recents tab
		let recentsTab = NSTabViewItem(identifier: "recents")
		recentsTab.label = "Recent Apps"
		let recentsView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

		recentsTable = makeTable()
		recentsTable.dataSource = self
		recentsTable.delegate = self
		let recentsScroll = makeScrollView(for: recentsTable,
			frame: NSRect(x: 0, y: 40, width: 480, height: 280))
		recentsView.addSubview(recentsScroll)

		let clearBtn = NSButton(title: "Remove Selected", target: self, action: #selector(clearSelectedRecent))
		clearBtn.frame = NSRect(x: 0, y: 4, width: 140, height: 28)
		recentsView.addSubview(clearBtn)

		recentsTab.view = recentsView
		tabView.addTabViewItem(recentsTab)

		// Hidden tab
		let hiddenTab = NSTabViewItem(identifier: "hidden")
		hiddenTab.label = "Hidden Apps"
		let hiddenView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

		hiddenTable = makeTable()
		hiddenTable.dataSource = self
		hiddenTable.delegate = self
		let hiddenScroll = makeScrollView(for: hiddenTable,
			frame: NSRect(x: 0, y: 40, width: 480, height: 280))
		hiddenView.addSubview(hiddenScroll)

		let restoreBtn = NSButton(title: "Restore Selected", target: self, action: #selector(restoreSelectedHidden))
		restoreBtn.frame = NSRect(x: 0, y: 4, width: 140, height: 28)
		hiddenView.addSubview(restoreBtn)

		hiddenTab.view = hiddenView
		tabView.addTabViewItem(hiddenTab)
	}

	private func makeTable() -> NSTableView {
		let table = NSTableView()
		let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		nameCol.title = "Name"
		nameCol.width = 200
		table.addTableColumn(nameCol)
		let detailCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
		detailCol.title = "Detail"
		detailCol.width = 250
		table.addTableColumn(detailCol)
		table.rowHeight = 22
		table.allowsMultipleSelection = true
		return table
	}

	private func makeScrollView(for table: NSTableView, frame: NSRect) -> NSScrollView {
		let scroll = NSScrollView(frame: frame)
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autoresizingMask = [.width, .height]
		return scroll
	}

	private func reload() {
		recents = appIndex.getRecentApps()
		hidden = appIndex.getHiddenApps()
		recentsTable.reloadData()
		hiddenTable.reloadData()
	}

	@objc private func clearSelectedRecent() {
		let rows = recentsTable.selectedRowIndexes
		for row in rows.reversed() {
			guard row < recents.count else { continue }
			appIndex.clearUsage(forPath: recents[row].path)
		}
		reload()
	}

	@objc private func restoreSelectedHidden() {
		let rows = hiddenTable.selectedRowIndexes
		for row in rows.reversed() {
			guard row < hidden.count else { continue }
			appIndex.unhideApp(path: hidden[row].path)
		}
		reload()
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		if tableView === recentsTable { return recents.count }
		return hidden.count
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let colID = tableColumn?.identifier.rawValue ?? ""
		let label: NSTextField

		if tableView === recentsTable {
			let r = recents[row]
			if colID == "name" {
				label = NSTextField(labelWithString: r.name)
			} else {
				label = NSTextField(labelWithString: "\(r.count) launches")
			}
		} else {
			let h = hidden[row]
			if colID == "name" {
				label = NSTextField(labelWithString: h.name)
			} else {
				label = NSTextField(labelWithString: h.path)
			}
		}

		label.font = .systemFont(ofSize: 13)
		label.lineBreakMode = .byTruncatingTail
		return label
	}
}

// MARK: - Hotkey Recorder Panel

class HotKeyRecorderPanel: NSPanel {
	private let label: NSTextField
	private var keyMonitor: Any?
	var onRecord: ((UInt32, UInt32) -> Void)?

	init() {
		label = NSTextField(labelWithString: "Press a key combination...")

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)

		title = "Set Hotkey"
		level = .floating

		label.alignment = .center
		label.font = .systemFont(ofSize: 16)
		label.frame = NSRect(x: 20, y: 30, width: 280, height: 40)
		contentView?.addSubview(label)

		center()
	}

	func beginRecording() {
		makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)

		keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self = self else { return event }

			if event.keyCode == UInt16(kVK_Escape) {
				self.close()
				return nil
			}

			let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			let hasModifier = mods.contains(.command) || mods.contains(.option)
				|| mods.contains(.control)

			guard hasModifier else {
				self.label.stringValue = "Need a modifier (\u{2318}, \u{2325}, \u{2303})"
				return nil
			}

			var carbonMods: UInt32 = 0
			if mods.contains(.command) { carbonMods |= UInt32(cmdKey) }
			if mods.contains(.option) { carbonMods |= UInt32(optionKey) }
			if mods.contains(.control) { carbonMods |= UInt32(controlKey) }
			if mods.contains(.shift) { carbonMods |= UInt32(shiftKey) }

			self.onRecord?(UInt32(event.keyCode), carbonMods)
			self.close()
			return nil
		}
	}

	override func close() {
		if let monitor = keyMonitor {
			NSEvent.removeMonitor(monitor)
			keyMonitor = nil
		}
		super.close()
	}
}
