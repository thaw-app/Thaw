//
//  NotchIndicatorOverlay.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Shows the notch dead zone at the leading edge of the visible Layout Bar,
/// sized in screen points so it scrolls at 1:1 scale with the items.
///
/// Drawn in AppKit: a nested SwiftUI hosting view kept requesting constraint
/// passes on notched Macs until AppKit aborted the window.
final class NotchIndicatorView: NSView {
    /// Radii for a marker a menu bar high: the frame follows the notch's own
    /// rounded corners, the label pill is a small caption chip.
    private enum Metrics {
        static let frameRadius: CGFloat = 9
        static let labelRadius: CGFloat = 4
        static let inset: CGFloat = 3
        static let stripeWidth: CGFloat = 3
        static let stripeGap: CGFloat = 5
    }

    /// Colour palette used to keep the indicator legible against the
    /// current menu bar background.
    var averageColorInfo: MenuBarAverageColorInfo? {
        didSet {
            guard averageColorInfo != oldValue else { return }
            needsDisplay = true
        }
    }

    init(averageColorInfo: MenuBarAverageColorInfo?) {
        self.averageColorInfo = averageColorInfo
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        unregisterDraggedTypes()
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        let frame = bounds.insetBy(dx: Metrics.inset, dy: Metrics.inset)
        guard frame.width > 0, frame.height > 0 else { return }
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let ink = isBright ? NSColor.black : NSColor.white
        let shape = NSBezierPath(roundedRect: frame, xRadius: Metrics.frameRadius, yRadius: Metrics.frameRadius)

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        ink.withAlphaComponent(increasedContrast ? 1 : 0.5).setFill()
        let step = Metrics.stripeWidth + Metrics.stripeGap
        let height = frame.height
        var offset = frame.minX - height
        while offset < frame.maxX {
            let stripe = NSBezierPath()
            stripe.move(to: NSPoint(x: offset, y: frame.minY))
            stripe.line(to: NSPoint(x: offset + height, y: frame.maxY))
            stripe.line(to: NSPoint(x: offset + height + Metrics.stripeWidth, y: frame.maxY))
            stripe.line(to: NSPoint(x: offset + Metrics.stripeWidth, y: frame.minY))
            stripe.close()
            stripe.fill()
            offset += step
        }
        NSGraphicsContext.restoreGraphicsState()

        ink.withAlphaComponent(increasedContrast ? 1 : 0.65).setStroke()
        let border = NSBezierPath(
            roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Metrics.frameRadius,
            yRadius: Metrics.frameRadius
        )
        border.lineWidth = 1
        border.stroke()

        let label = String(localized: "Notch") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: ink,
        ]
        let textSize = label.size(withAttributes: attributes)
        let pill = CGRect(
            x: bounds.midX - (textSize.width + 12) / 2,
            y: bounds.midY - (textSize.height + 4) / 2,
            width: textSize.width + 12,
            height: textSize.height + 4
        )
        pillColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: Metrics.labelRadius, yRadius: Metrics.labelRadius).fill()
        label.draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 2), withAttributes: attributes)
    }

    private var pillColor: NSColor {
        guard let colorInfo = averageColorInfo else { return .defaultLayoutBar }
        return NSColor(cgColor: colorInfo.color) ?? .defaultLayoutBar
    }

    private var isBright: Bool {
        guard let colorInfo = averageColorInfo else { return false }
        return colorInfo.isBright(for: NSScreen.screenWithActiveMenuBar ?? NSScreen.main)
    }
}
