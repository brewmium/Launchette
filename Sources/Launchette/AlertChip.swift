import Cocoa

// MARK: - Alert chip

// Small always-on-top orange card near the menu bar: timer name, "Time's up"
// with the fire time, and a Stop/Dismiss button. Shown when a timer fires and
// kept on screen after the chime ends, so every finished timer stays visible
// until acknowledged. Chips stack downward under the menu bar. Clicking a chip
// dismisses it; a modifier-click (any of Cmd/Opt/Shift/Ctrl) dismisses all.
class AlertChip: NSPanel {
	static let accent = NSColor(red: 0xFF/255.0, green: 0x8A/255.0, blue: 0x00/255.0, alpha: 1.0)

	let timerID: UUID
	// (timerID, dismissAll) -- dismissAll is true when a modifier was held
	var onDismiss: ((UUID, Bool) -> Void)?

	private var dismissButton: NSButton!

	private static let chipWidth: CGFloat = 300
	private static let chipHeight: CGFloat = 64

	init(timer: CountdownTimer, index: Int) {
		self.timerID = timer.id

		super.init(
			contentRect: NSRect(x: 0, y: 0, width: Self.chipWidth, height: Self.chipHeight),
			styleMask: [.nonactivatingPanel],
			backing: .buffered,
			defer: false
		)

		isFloatingPanel = true
		level = .statusBar
		isOpaque = false
		backgroundColor = .clear
		hasShadow = true
		hidesOnDeactivate = false

		let card = NSView(frame: contentView!.bounds)
		card.autoresizingMask = [.width, .height]
		card.wantsLayer = true
		card.layer?.backgroundColor = Self.accent.cgColor
		card.layer?.cornerRadius = 12
		contentView?.addSubview(card)

		let titleLabel = NSTextField(labelWithString: "Time's up (\(TimeFormat.clockString(timer.fireDate)))")
		titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
		titleLabel.textColor = .white
		titleLabel.frame = NSRect(x: 16, y: 34, width: 190, height: 20)
		titleLabel.lineBreakMode = .byTruncatingTail
		card.addSubview(titleLabel)

		let nameLabel = NSTextField(labelWithString: timer.displayName)
		nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
		nameLabel.textColor = NSColor.white.withAlphaComponent(0.9)
		nameLabel.frame = NSRect(x: 16, y: 12, width: 190, height: 17)
		nameLabel.lineBreakMode = .byTruncatingTail
		card.addSubview(nameLabel)

		dismissButton = NSButton(frame: NSRect(x: Self.chipWidth - 88, y: (Self.chipHeight - 28) / 2, width: 72, height: 28))
		dismissButton.isBordered = false
		dismissButton.wantsLayer = true
		dismissButton.layer?.backgroundColor = NSColor.white.cgColor
		dismissButton.layer?.cornerRadius = 14
		dismissButton.attributedTitle = Self.buttonTitle("Stop")
		dismissButton.target = self
		dismissButton.action = #selector(dismissClicked)
		card.addSubview(dismissButton)

		reposition(index: index)
	}

	// Stack under the menu bar at the top right of the menu-bar screen,
	// growing downward; called again when chips above are dismissed
	func reposition(index: Int) {
		let screen = NSScreen.screens.first ?? NSScreen.main!
		let sf = screen.visibleFrame
		let x = sf.maxX - Self.chipWidth - 16
		let y = sf.maxY - Self.chipHeight - 16 - CGFloat(index) * (Self.chipHeight + 10)
		setFrameOrigin(NSPoint(x: x, y: y))
	}

	func show() {
		orderFrontRegardless()
	}

	// The chime is over; the chip is now just a "this one finished" record
	func soundEnded() {
		dismissButton.attributedTitle = Self.buttonTitle("Dismiss")
	}

	// Anywhere on the card dismisses, same as the button
	override func mouseDown(with event: NSEvent) {
		fireDismiss(modifiers: event.modifierFlags)
	}

	@objc private func dismissClicked() {
		fireDismiss(modifiers: NSApp.currentEvent?.modifierFlags ?? [])
	}

	private func fireDismiss(modifiers: NSEvent.ModifierFlags) {
		let held = modifiers.intersection([.command, .option, .shift, .control])
		onDismiss?(timerID, !held.isEmpty)
	}

	private static func buttonTitle(_ title: String) -> NSAttributedString {
		NSAttributedString(
			string: title,
			attributes: [
				.foregroundColor: accent,
				.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
			]
		)
	}
}
