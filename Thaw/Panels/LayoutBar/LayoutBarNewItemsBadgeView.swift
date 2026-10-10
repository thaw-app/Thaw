//
//  LayoutBarNewItemsBadgeView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// A draggable badge that controls where newly detected items will be placed.
final class LayoutBarNewItemsBadgeView: LayoutBarArrangedView {
    private enum Metrics {
        static let height: CGFloat = 24
        static let cornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 10
        static let borderWidth: CGFloat = 1
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let isBright = isBrightForActiveScreen()
        let foregroundColor: NSColor = isBright ? .black : .white
        return [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: foregroundColor,
        ]
    }

    override var kind: Kind {
        .newItemsBadge
    }

    init() {
        let tempAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let title = NSAttributedString(
            string: String(localized: "New Items"),
            attributes: tempAttributes
        )
        let textWidth = ceil(title.size().width)
        let badgeWidth = textWidth + (Metrics.horizontalPadding * 2)
        let size = CGSize(width: badgeWidth, height: Metrics.height)
        super.init(frame: CGRect(origin: .zero, size: size))
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingImage() -> NSImage? {
        bitmapImage()
    }

    /// Plays a bounce-in scale animation, used when the badge first appears
    /// for a newly detected item. No-op when reduce motion is enabled.
    func animateAppearance() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        wantsLayer = true
        let animation = CASpringAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.6
        animation.toValue = 1.0
        animation.damping = 12
        animation.initialVelocity = 4
        animation.duration = animation.settlingDuration
        layer?.add(animation, forKey: "appearanceScale")
    }

    override func draw(_: NSRect) {
        guard !isDraggingPlaceholder else {
            return
        }

        let isBright = isBrightForActiveScreen()
        let pillPath = NSBezierPath(roundedRect: bounds, xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius)

        let fillColor: NSColor = isBright ? .black : .white
        let strokeColor: NSColor = isBright ? .black : .white

        fillColor.withAlphaComponent(0.25).setFill()
        pillPath.fill()

        strokeColor.withAlphaComponent(0.65).setStroke()
        pillPath.lineWidth = Metrics.borderWidth
        pillPath.stroke()

        let title = NSAttributedString(
            string: String(localized: "New Items"),
            attributes: textAttributes
        )
        let titleSize = title.size()
        let titleOrigin = CGPoint(
            x: bounds.midX - (titleSize.width / 2),
            y: bounds.midY - (titleSize.height / 2)
        )
        title.draw(at: titleOrigin)
    }

    /// Use the active screen for notch-aware brightness.
    private func isBrightForActiveScreen() -> Bool {
        guard let colorInfo = averageColorInfo else { return false }
        return colorInfo.isBright(for: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: draggingImage())

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func bitmapImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
