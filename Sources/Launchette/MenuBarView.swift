import Cocoa

// MARK: - Menu bar rendering

// Composes the status item: the Launchette icon, the soonest timer's remaining
// time in monospaced digits, and an orange count badge when 2+ timers run.
enum MenuBarView {
	static func render(statusItem: NSStatusItem, store: TimerStore) {
		guard let button = statusItem.button else { return }

		let count = store.count
		button.image = icon(badge: count >= 2 ? count : nil)

		if let soonest = store.soonest {
			button.attributedTitle = NSAttributedString(
				string: " " + TimeFormat.compact(soonest.remaining),
				attributes: [
					.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
					.foregroundColor: NSColor.labelColor,
				]
			)
			button.imagePosition = .imageLeft
		} else {
			button.attributedTitle = NSAttributedString(string: "")
			button.imagePosition = .imageOnly
		}
	}

	static func icon(badge: Int?) -> NSImage {
		let glyph = SearchPanel.makeLaunchetteIcon(size: 18, tint: NSColor.white.withAlphaComponent(0.7))
		glyph.isTemplate = false

		guard let badge else { return glyph }

		let glyphSize = glyph.size
		let badgeD: CGFloat = 12
		let canvas = NSSize(width: glyphSize.width + badgeD / 2 + 2, height: glyphSize.height + 3)
		let text = badge > 9 ? "9+" : "\(badge)"

		let img = NSImage(size: canvas, flipped: false) { _ in
			glyph.draw(at: NSPoint(x: 0, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)

			let badgeRect = NSRect(
				x: canvas.width - badgeD,
				y: canvas.height - badgeD,
				width: badgeD, height: badgeD
			)
			AlertChip.accent.setFill()
			NSBezierPath(ovalIn: badgeRect).fill()

			let str = NSAttributedString(string: text, attributes: [
				.font: NSFont.systemFont(ofSize: 8, weight: .bold),
				.foregroundColor: NSColor.white,
			])
			let strSize = str.size()
			str.draw(at: NSPoint(
				x: badgeRect.midX - strSize.width / 2,
				y: badgeRect.midY - strSize.height / 2
			))
			return true
		}
		img.isTemplate = false
		return img
	}
}
