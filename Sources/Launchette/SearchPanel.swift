import Cocoa

// MARK: - Search result model

struct SearchResult {
	let icon: NSImage
	let title: String
	let subtitle: String
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

class SearchPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
	private let searchField: NSTextField
	private let resultsTable: PassthroughTableView
	private let scrollView: NSScrollView
	private let visualEffect: NSVisualEffectView
	private let appIndex: AppIndex
	private let mathEvaluator = MathEvaluator()
	private var results: [SearchResult] = []
	private var previousApp: NSRunningApplication?

	private let panelWidth: CGFloat = 680
	private let searchFieldHeight: CGFloat = 48
	private let rowHeight: CGFloat = 44
	private let maxVisibleRows = 8
	private let pad: CGFloat = 8
	private let gutter: CGFloat = 20

	init(appIndex: AppIndex) {
		self.appIndex = appIndex
		searchField = NSTextField()
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
		contentView?.addSubview(visualEffect)

		// Search icon
		let iconSize: CGFloat = 22
		let iconY = bounds.height - pad - searchFieldHeight + (searchFieldHeight - iconSize) / 2
		let searchIcon = NSImageView(frame: NSRect(x: gutter, y: iconY, width: iconSize, height: iconSize))
		searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
		searchIcon.contentTintColor = .secondaryLabelColor
		searchIcon.autoresizingMask = [.minYMargin]
		visualEffect.addSubview(searchIcon)

		// Search field (vertically centered in the search area)
		let fieldX = gutter + iconSize + pad
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

		guard let screen = NSScreen.main else { return }
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

	func dismiss() {
		NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: self)
		orderOut(nil)
		previousApp?.activate(options: [])
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
					title: "= \(resultStr)",
					subtitle: "Copy to clipboard",
					action: {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(resultStr, forType: .string)
					}
				))
			}

			// Apps
			for app in appIndex.search(query: query) {
				let entry = app
				results.append(SearchResult(
					icon: entry.icon,
					title: entry.name,
					subtitle: entry.isRunning ? "Running" : "",
					action: { entry.launch() }
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
		dismiss()
		action()
	}

	@objc private func tableClicked() {
		let row = resultsTable.clickedRow
		guard row >= 0, row < results.count else { return }
		let action = results[row].action
		dismiss()
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
		let cell = NSView()

		let iconView = NSImageView(frame: NSRect(x: gutter, y: 6, width: 32, height: 32))
		iconView.image = result.icon
		iconView.imageScaling = .scaleProportionallyUpOrDown
		cell.addSubview(iconView)

		let titleLabel = NSTextField(labelWithString: result.title)
		titleLabel.frame = NSRect(x: gutter + 40, y: 12, width: 400, height: 22)
		titleLabel.font = .systemFont(ofSize: 16)
		titleLabel.textColor = .labelColor
		titleLabel.lineBreakMode = .byTruncatingTail
		cell.addSubview(titleLabel)

		if !result.subtitle.isEmpty {
			let subLabel = NSTextField(labelWithString: result.subtitle)
			subLabel.font = .systemFont(ofSize: 12)
			subLabel.textColor = .secondaryLabelColor
			subLabel.sizeToFit()
			subLabel.frame.origin = NSPoint(
				x: panelWidth - pad * 2 - gutter * 2 - subLabel.frame.width,
				y: 15
			)
			cell.addSubview(subLabel)
		}

		return cell
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		rowHeight
	}
}
