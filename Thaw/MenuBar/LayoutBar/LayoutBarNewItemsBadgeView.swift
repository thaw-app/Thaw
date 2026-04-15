//
//  LayoutBarNewItemsBadgeView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// A draggable badge that controls where newly detected items will be placed.
final class LayoutBarNewItemsBadgeView: LayoutBarArrangedView {
    private enum Metrics {
        static let size = CGSize(width: 84, height: 24)
        static let cornerRadius: CGFloat = 12
        static let horizontalInset: CGFloat = 10
        static let borderWidth: CGFloat = 1
    }

    override var kind: Kind {
        .newItemsBadge
    }

    init() {
        super.init(frame: CGRect(origin: .zero, size: Metrics.size))
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingImage() -> NSImage? {
        bitmapImage()
    }

    override func draw(_: NSRect) {
        guard !isDraggingPlaceholder else {
            return
        }

        let pillPath = NSBezierPath(roundedRect: bounds, xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius)
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        pillPath.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.45).setStroke()
        pillPath.lineWidth = Metrics.borderWidth
        pillPath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let title = NSAttributedString(string: String(localized: "New Items"), attributes: attributes)
        let titleRect = CGRect(
            x: bounds.minX + Metrics.horizontalInset,
            y: bounds.midY - 7,
            width: bounds.width - (Metrics.horizontalInset * 2),
            height: 14
        )
        title.draw(in: titleRect)
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
