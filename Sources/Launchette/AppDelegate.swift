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

	// MARK: Lifecycle

	func applicationDidFinishLaunching(_ notification: Notification) {
		AppDelegate.instance = self
		setupMenuBar()
		installEventHandler()
		registerHotKey()
		searchPanel = SearchPanel(appIndex: appIndex)
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
			button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Launchette")
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

	@objc private func quit() {
		NSApp.terminate(nil)
	}

	@objc private func runningAppsChanged(_ notification: Notification) {
		appIndex.refreshRunningApps()
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
