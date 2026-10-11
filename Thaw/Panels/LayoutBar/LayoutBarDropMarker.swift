//
//  LayoutBarDropMarker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The line Layout draws where a dragged item or group will land.
nonisolated enum LayoutBarDropMarker {
    static let width: CGFloat = 2
    static let verticalInset: CGFloat = 2

    /// A dragged item holds its slot open as an empty gap; the marker sits in the middle of it.
    static func x(inGap frames: [CGRect]) -> CGFloat? {
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }.midX
    }

    /// An arranged view as a group drop sees it.
    struct Slot {
        let frame: CGRect
        /// Its place in the section's item list; nil for an opaque slot or a collapsed group.
        let itemIndex: Int?
        /// Whether the item list holds anything from it, which a collapsed group does.
        let holdsItems: Bool
    }

    /// Where a group drop lands: its index in the item list, and the boundary among the slots that index sits on.
    struct GroupDestination: Equatable {
        let itemIndex: Int
        let boundary: Int
    }

    /// The one rule the marker and the drop share: before the nearest slot, or after it when x is past its middle.
    static func groupDestination(forX x: CGFloat, among slots: [Slot], itemCount: Int) -> GroupDestination {
        let nearest = slots.indices.min { abs(slots[$0].frame.midX - x) < abs(slots[$1].frame.midX - x) }
        guard let nearest, let itemIndex = slots[nearest].itemIndex else {
            // Nearest to something that is not an item, the group goes to the end of the item list.
            let end = slots.lastIndex(where: \.holdsItems).map { $0 + 1 } ?? 0
            return GroupDestination(itemIndex: itemCount, boundary: end)
        }
        let offset = x > slots[nearest].frame.midX ? 1 : 0
        return GroupDestination(itemIndex: itemIndex + offset, boundary: nearest + offset)
    }

    /// A group dragged by its handle opens no gap, so the marker sits on the boundary it will be inserted at.
    static func x(insertingAt index: Int, among frames: [CGRect]) -> CGFloat? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if index <= 0 { return first.minX }
        if index >= frames.count { return last.maxX }
        return (frames[index - 1].maxX + frames[index].minX) / 2
    }

    /// The marker's rect, kept inside bounds so a slot at either end still shows a whole line.
    static func rect(atX x: CGFloat, in bounds: CGRect) -> CGRect {
        let centre = min(max(x, bounds.minX + width / 2), bounds.maxX - width / 2)
        return CGRect(
            x: centre - width / 2,
            y: bounds.minY + verticalInset,
            width: width,
            height: bounds.height - verticalInset * 2
        )
    }

    @MainActor
    static func draw(atX x: CGFloat, in bounds: CGRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect(atX: x, in: bounds), xRadius: width / 2, yRadius: width / 2).fill()
    }
}

extension LayoutBarContainer {
    /// Where a handle drop at x, in this view's coordinates, lands; the marker and the drop both read it.
    func groupDropDestination(atX x: CGFloat) -> LayoutBarDropMarker.GroupDestination {
        let identifiers = LayoutBarPaddingView.layoutItemsForPersistence(from: arrangedViews).map(\.uniqueIdentifier)
        let slots = arrangedViews.filter { !$0.isNewItemsBadge }.map { view in
            var itemIndex: Int?
            if case let .item(item) = view.kind {
                itemIndex = identifiers.firstIndex(of: item.uniqueIdentifier)
            }
            let holdsItems = !LayoutBarPaddingView.persistableItems(from: [view.kind]).isEmpty
            return LayoutBarDropMarker.Slot(frame: view.frame, itemIndex: itemIndex, holdsItems: holdsItems)
        }
        return LayoutBarDropMarker.groupDestination(forX: x, among: slots, itemCount: identifiers.count)
    }
}
