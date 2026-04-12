import Cocoa

// MARK: - Search result model

// MARK: - Panel size

enum ScreenMode: Int, CaseIterable {
	case mouseScreen = 0, frontWindow = 1

	var label: String { ["Mouse Screen", "Front Window Screen"][rawValue] }
}

enum PanelSize: Int, CaseIterable {
	case small = 0, medium = 1, large = 2

	var label: String { ["Small", "Medium", "Large"][rawValue] }
	var iconDim: CGFloat { [24, 36, 48][rawValue] }
	var rowHeight: CGFloat { [44, 56, 72][rawValue] }
	var titleFont: CGFloat { [13, 15, 18][rawValue] }
	var subFont: CGFloat { [10, 11, 12][rawValue] }
	var maxVisible: Int { [10, 8, 6][rawValue] }
	var searchIconSize: CGFloat { [18, 22, 28][rawValue] }
}

// MARK: - Search result model

struct SearchResult {
	let icon: NSImage
	let title: String
	let version: String
	let displayPath: String
	let status: String
	let hidePath: String?
	let action: () -> Void
}

// MARK: - Table view that never steals focus

class PassthroughTableView: NSTableView {
	override var acceptsFirstResponder: Bool { false }
}

// MARK: - Custom row selection highlight

class ResultRowView: NSTableRowView {
	override func drawSelection(in dirtyRect: NSRect) {
		if selectionHighlightStyle != .none {
			NSColor.white.withAlphaComponent(0.15).setFill()
			NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
		}
	}
}

// MARK: - Vertically centered text field cell

class VerticalCenterTextFieldCell: NSTextFieldCell {
	override func titleRect(forBounds rect: NSRect) -> NSRect {
		var r = super.titleRect(forBounds: rect)
		let textH = cellSize(forBounds: rect).height
		let delta = r.height - textH
		if delta > 0 {
			r.origin.y += delta / 2
			r.size.height -= delta
		}
		return r
	}

	override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
		super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
	}

	override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
		delegate: Any?, start selStart: Int, length selLength: Int)
	{
		super.select(withFrame: titleRect(forBounds: rect), in: controlView,
			editor: textObj, delegate: delegate, start: selStart, length: selLength)
	}

	override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
		delegate: Any?, event: NSEvent?)
	{
		super.edit(withFrame: titleRect(forBounds: rect), in: controlView,
			editor: textObj, delegate: delegate, event: event)
	}
}

// MARK: - Search panel

class SearchPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
	private let searchField: NSTextField
	private let searchIcon: NSImageView
	private let resultsTable: PassthroughTableView
	private let scrollView: NSScrollView
	private let visualEffect: NSVisualEffectView
	private let appIndex: AppIndex
	private let mathEvaluator = MathEvaluator()
	private var results: [SearchResult] = []
	private var previousApp: NSRunningApplication?

	private let panelWidth: CGFloat = 561
	private let strokeColor = NSColor(red: 0xFA/255.0, green: 0xF4/255.0, blue: 0x9A/255.0, alpha: 1.0)
	private let searchFieldHeight: CGFloat = 48
	private let pad: CGFloat = 8
	private let gutter: CGFloat = 20
	private(set) var currentSize: PanelSize
	private(set) var screenMode: ScreenMode

	static func makeLaunchetteIcon(size: CGFloat, tint: NSColor? = nil) -> NSImage {
		let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)

		let glass = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!
		let renderedGlass = glass.withSymbolConfiguration(config) ?? glass
		let glassSize = renderedGlass.size

		let bolt = "\u{26A1}\u{FE0F}"
		let boltFont = NSFont.systemFont(ofSize: size * 0.75)
		let boltAttrs: [NSAttributedString.Key: Any] = [.font: boltFont]
		let boltStr = NSAttributedString(string: bolt, attributes: boltAttrs)
		let boltSize = boltStr.size()

		let canvasW = max(glassSize.width, boltSize.width)
		let canvasH = max(glassSize.height, boltSize.height)
		let img = NSImage(size: NSSize(width: canvasW, height: canvasH))
		img.lockFocus()

		// Draw magnifying glass centered
		let glassX = (canvasW - glassSize.width) / 2
		let glassY = (canvasH - glassSize.height) / 2
		if let color = tint {
			let tinted = renderedGlass.copy() as! NSImage
			tinted.lockFocus()
			color.set()
			NSRect(origin: .zero, size: glassSize).fill(using: .sourceAtop)
			tinted.unlockFocus()
			tinted.draw(at: NSPoint(x: glassX, y: glassY), from: .zero, operation: .sourceOver, fraction: 1.0)
		} else {
			renderedGlass.draw(at: NSPoint(x: glassX, y: glassY), from: .zero, operation: .sourceOver, fraction: 1.0)
		}

		// Draw bolt pinned top-left
		let boltX: CGFloat = 0
		let boltY = canvasH - boltSize.height - 1
		boltStr.draw(at: NSPoint(x: boltX, y: boltY))

		img.unlockFocus()
		return img
	}

	private var rowHeight: CGFloat { currentSize.rowHeight }
	private var maxVisibleRows: Int { currentSize.maxVisible }

	init(appIndex: AppIndex) {
		self.appIndex = appIndex
		self.currentSize = PanelSize(rawValue: UserDefaults.standard.integer(forKey: "panelSize")) ?? .medium
		self.screenMode = ScreenMode(rawValue: UserDefaults.standard.integer(forKey: "screenMode")) ?? .mouseScreen
		searchField = NSTextField()
		searchIcon = NSImageView()
		resultsTable = PassthroughTableView()
		scrollView = NSScrollView()
		visualEffect = NSVisualEffectView()

		let initialHeight = searchFieldHeight + pad * 2
		super.init(
			contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: initialHeight),
			styleMask: [.nonactivatingPanel],
			backing: .buffered,
			defer: false
		)

		level = .floating
		hasShadow = true
		backgroundColor = .clear
		isOpaque = false
		hidesOnDeactivate = false
		becomesKeyOnlyIfNeeded = false

		setupViews()
	}

	override var canBecomeKey: Bool { true }

	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
			let row = resultsTable.selectedRow
			if row >= 0, row < results.count, results[row].hidePath == nil {
				// Math result -- copy it
				results[row].action()
				return true
			}
		}
		return super.performKeyEquivalent(with: event)
	}

	// MARK: View setup

	private func setupViews() {
		let bounds = contentView!.bounds

		// Vibrancy background
		visualEffect.frame = bounds
		visualEffect.autoresizingMask = [.width, .height]
		visualEffect.material = .hudWindow
		visualEffect.state = .active
		visualEffect.appearance = NSAppearance(named: .darkAqua)
		visualEffect.wantsLayer = true
		visualEffect.layer?.cornerRadius = 12
		visualEffect.layer?.masksToBounds = true
		visualEffect.layer?.borderWidth = 1.5
		visualEffect.layer?.borderColor = strokeColor.cgColor
		contentView?.addSubview(visualEffect)

		// Search icon (scales with size setting)
		let iconSz = currentSize.searchIconSize
		let iconY = bounds.height - pad - searchFieldHeight + (searchFieldHeight - iconSz) / 2
		searchIcon.frame = NSRect(x: gutter, y: iconY, width: iconSz, height: iconSz)
		searchIcon.image = Self.makeLaunchetteIcon(size: iconSz, tint: .secondaryLabelColor)
		searchIcon.imageScaling = .scaleProportionallyUpOrDown
		searchIcon.autoresizingMask = [.minYMargin]
		visualEffect.addSubview(searchIcon)

		// Search field (vertically centered in the search area)
		let fieldX = gutter + iconSz + pad
		let fieldY = bounds.height - pad - searchFieldHeight
		searchField.frame = NSRect(x: fieldX, y: fieldY, width: bounds.width - fieldX - gutter, height: searchFieldHeight)
		searchField.autoresizingMask = [.width, .minYMargin]
		let centeredCell = VerticalCenterTextFieldCell()
		centeredCell.isEditable = true
		centeredCell.isSelectable = true
		centeredCell.isBordered = false
		centeredCell.isBezeled = false
		centeredCell.drawsBackground = false
		centeredCell.focusRingType = .none
		searchField.cell = centeredCell
		searchField.font = .systemFont(ofSize: 24, weight: .light)
		searchField.placeholderAttributedString = NSAttributedString(
			string: "Search or calculate...",
			attributes: [
				.foregroundColor: NSColor.secondaryLabelColor,
				.font: NSFont.systemFont(ofSize: 24, weight: .light),
			]
		)
		searchField.isBordered = false
		searchField.isBezeled = false
		searchField.drawsBackground = false
		searchField.focusRingType = .none
		searchField.textColor = .white
		searchField.delegate = self
		visualEffect.addSubview(searchField)

		// Table in scroll view
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("results"))
		column.width = panelWidth - pad * 2
		resultsTable.addTableColumn(column)
		resultsTable.headerView = nil
		resultsTable.dataSource = self
		resultsTable.delegate = self
		resultsTable.backgroundColor = .clear
		resultsTable.rowHeight = rowHeight
		resultsTable.intercellSpacing = NSSize(width: 0, height: 2)
		resultsTable.selectionHighlightStyle = .regular
		resultsTable.gridStyleMask = []
		resultsTable.target = self
		resultsTable.action = #selector(tableClicked)

		let contextMenu = NSMenu()
		contextMenu.delegate = self
		resultsTable.menu = contextMenu

		scrollView.documentView = resultsTable
		scrollView.hasVerticalScroller = false
		scrollView.hasHorizontalScroller = false
		scrollView.drawsBackground = false
		scrollView.borderType = .noBorder
		scrollView.frame = NSRect(x: pad, y: pad, width: bounds.width - pad * 2, height: 0)
		scrollView.autoresizingMask = [.width, .height]
		scrollView.isHidden = true
		visualEffect.addSubview(scrollView)
	}

	// MARK: Show / Dismiss

	func showPanel() {
		previousApp = NSWorkspace.shared.frontmostApplication
		searchField.stringValue = ""
		results = []
		resultsTable.reloadData()

		let screen: NSScreen
		if screenMode == .mouseScreen {
			let mouseLocation = NSEvent.mouseLocation
			screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
		} else {
			screen = NSScreen.main ?? NSScreen.screens[0]
		}
		let sf = screen.visibleFrame
		let h = searchFieldHeight + pad * 2
		let x = sf.midX - panelWidth / 2
		let y = sf.origin.y + sf.height * 3 / 4 - h / 2

		setFrame(NSRect(x: x, y: y, width: panelWidth, height: h), display: true)
		scrollView.isHidden = true

		NSApp.activate(ignoringOtherApps: true)
		makeKeyAndOrderFront(nil)
		makeFirstResponder(searchField)

		NotificationCenter.default.addObserver(
			self, selector: #selector(windowDidResignKey),
			name: NSWindow.didResignKeyNotification, object: self
		)
	}

	func dismiss(restoreFocus: Bool = true) {
		NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: self)
		orderOut(nil)
		if restoreFocus {
			previousApp?.activate(options: [])
		}
		previousApp = nil
	}

	@objc private func windowDidResignKey(_ notification: Notification) {
		dismiss()
	}

	// MARK: Search logic

	private func updateResults() {
		let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
		results = []

		if !query.isEmpty {
			// Math
			if let mathResult = mathEvaluator.evaluate(query) {
				let resultStr = mathResult
				results.append(SearchResult(
					icon: NSImage(systemSymbolName: "equal.circle.fill", accessibilityDescription: "Math")
						?? NSImage(),
					title: resultStr,
					version: "",
					displayPath: "",
					status: "Copy to clipboard",
					hidePath: nil,
					action: {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(resultStr, forType: .string)
					}
				))
			}

			// Apps
			for app in appIndex.search(query: query) {
				let entry = app
				let idx = appIndex
				results.append(SearchResult(
					icon: entry.icon,
					title: entry.name,
					version: entry.version,
					displayPath: entry.displayPath,
					status: entry.isRunning ? "Running" : "",
					hidePath: entry.path,
					action: { idx.launchApp(entry) }
				))
			}
		}

		resultsTable.reloadData()
		if !results.isEmpty {
			resultsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		}
		updatePanelSize()
	}

	private func updatePanelSize() {
		let rows = min(results.count, maxVisibleRows)
		let tableH = CGFloat(rows) * (rowHeight + 2)
		let newH: CGFloat

		if rows > 0 {
			scrollView.isHidden = false
			newH = searchFieldHeight + pad * 3 + tableH
		} else {
			scrollView.isHidden = true
			newH = searchFieldHeight + pad * 2
		}

		var f = frame
		let top = f.maxY
		f.size.height = newH
		f.origin.y = top - newH
		setFrame(f, display: true, animate: true)
	}

	// MARK: Activation

	private func activateSelected() {
		let row = resultsTable.selectedRow
		guard row >= 0, row < results.count else { return }
		let action = results[row].action
		dismiss(restoreFocus: false)
		NSApp.hide(nil)
		action()
	}

	@objc private func tableClicked() {
		let row = resultsTable.clickedRow
		guard row >= 0, row < results.count else { return }
		let action = results[row].action
		dismiss(restoreFocus: false)
		NSApp.hide(nil)
		action()
	}

	// MARK: NSTextFieldDelegate

	func controlTextDidChange(_ notification: Notification) {
		updateResults()
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
		if sel == #selector(moveUp(_:)) {
			let row = max(0, resultsTable.selectedRow - 1)
			resultsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			resultsTable.scrollRowToVisible(row)
			return true
		}
		if sel == #selector(moveDown(_:)) {
			let row = min(results.count - 1, resultsTable.selectedRow + 1)
			if row >= 0 {
				resultsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
				resultsTable.scrollRowToVisible(row)
			}
			return true
		}
		if sel == #selector(insertNewline(_:)) {
			activateSelected()
			return true
		}
		if sel == #selector(cancelOperation(_:)) {
			dismiss()
			return true
		}
		return false
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		results.count
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		ResultRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let result = results[row]
		let sz = currentSize
		let rh = sz.rowHeight
		let iconDim = sz.iconDim
		let titleFS = sz.titleFont
		let subFS = sz.subFont
		let cellW = panelWidth - pad * 2
		let rightEdge = cellW - gutter * 2

		let cell = NSView()

		// Icon -- vertically centered
		let iconY = (rh - iconDim) / 2
		let iconView = NSImageView(frame: NSRect(x: gutter, y: iconY, width: iconDim, height: iconDim))
		iconView.image = result.icon
		iconView.imageScaling = .scaleProportionallyUpOrDown
		cell.addSubview(iconView)

		let textX = gutter + iconDim + 10
		let titleH = ceil(titleFS * 1.4)
		let subH = ceil(subFS * 1.4)
		let gap: CGFloat = 1
		let hasTwoLines = !result.displayPath.isEmpty || !result.version.isEmpty

		if hasTwoLines {
			let groupH = titleH + gap + subH
			let groupBot = (rh - groupH) / 2
			let topY = groupBot + subH + gap
			let botY = groupBot

			// Top line left: title
			let titleLabel = NSTextField(labelWithString: result.title)
			titleLabel.frame = NSRect(x: textX, y: topY, width: rightEdge - textX, height: titleH)
			titleLabel.font = .systemFont(ofSize: titleFS, weight: .medium)
			titleLabel.textColor = .labelColor
			titleLabel.lineBreakMode = .byTruncatingTail
			cell.addSubview(titleLabel)

			// Top line right: version
			if !result.version.isEmpty {
				let verLabel = NSTextField(labelWithString: result.version)
				verLabel.font = .monospacedDigitSystemFont(ofSize: subFS, weight: .regular)
				verLabel.textColor = .secondaryLabelColor
				verLabel.sizeToFit()
				verLabel.frame.origin = NSPoint(x: rightEdge - verLabel.frame.width, y: topY + 2)
				cell.addSubview(verLabel)
			}

			// Bottom line left: path
			if !result.displayPath.isEmpty {
				let pathLabel = NSTextField(labelWithString: result.displayPath)
				pathLabel.font = .systemFont(ofSize: subFS)
				pathLabel.textColor = .secondaryLabelColor
				pathLabel.lineBreakMode = .byTruncatingMiddle
				pathLabel.frame = NSRect(x: textX, y: botY, width: rightEdge - textX - 80, height: subH)
				cell.addSubview(pathLabel)
			}

			// Bottom line right: status
			if !result.status.isEmpty {
				let statusLabel = NSTextField(labelWithString: result.status)
				statusLabel.font = .systemFont(ofSize: subFS)
				statusLabel.textColor = .secondaryLabelColor
				statusLabel.sizeToFit()
				statusLabel.frame.origin = NSPoint(x: rightEdge - statusLabel.frame.width, y: botY)
				cell.addSubview(statusLabel)
			}
		} else {
			// Single line -- title centered, status on same line right-aligned
			let titleY = (rh - titleH) / 2

			let titleLabel = NSTextField(labelWithString: result.title)
			titleLabel.frame = NSRect(x: textX, y: titleY, width: rightEdge - textX, height: titleH)
			titleLabel.font = .systemFont(ofSize: titleFS, weight: .medium)
			titleLabel.textColor = .labelColor
			titleLabel.lineBreakMode = .byTruncatingTail
			cell.addSubview(titleLabel)

			if !result.status.isEmpty {
				let statusLabel = NSTextField(labelWithString: result.status)
				statusLabel.font = .systemFont(ofSize: subFS)
				statusLabel.textColor = .secondaryLabelColor
				statusLabel.sizeToFit()
				statusLabel.frame.origin = NSPoint(x: rightEdge - statusLabel.frame.width, y: titleY + 2)
				cell.addSubview(statusLabel)
			}
		}

		return cell
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		rowHeight
	}

	// MARK: NSMenuDelegate (right-click context menu)

	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		let row = resultsTable.clickedRow
		guard row >= 0, row < results.count, let path = results[row].hidePath else { return }
		let item = NSMenuItem(
			title: "Hide \"\(results[row].title)\"",
			action: #selector(hideAppClicked(_:)), keyEquivalent: ""
		)
		item.target = self
		item.representedObject = path
		menu.addItem(item)
	}

	@objc private func hideAppClicked(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		appIndex.hideApp(path: path)
		updateResults()
	}

	// MARK: Size

	func setSize(_ size: PanelSize) {
		currentSize = size
		UserDefaults.standard.set(size.rawValue, forKey: "panelSize")

		// Resize search icon
		let iconSz = size.searchIconSize
		let iconY = searchIcon.superview!.bounds.height - pad - searchFieldHeight + (searchFieldHeight - iconSz) / 2
		searchIcon.frame = NSRect(x: gutter, y: iconY, width: iconSz, height: iconSz)
		searchIcon.image = Self.makeLaunchetteIcon(size: iconSz, tint: .secondaryLabelColor)

		// Reposition search field
		let fieldX = gutter + iconSz + pad
		var sf = searchField.frame
		sf.origin.x = fieldX
		sf.size.width = visualEffect.bounds.width - fieldX - gutter
		searchField.frame = sf

		resultsTable.reloadData()
		if isVisible {
			updatePanelSize()
		}
	}

	func setScreenMode(_ mode: ScreenMode) {
		screenMode = mode
		UserDefaults.standard.set(mode.rawValue, forKey: "screenMode")
	}
}
