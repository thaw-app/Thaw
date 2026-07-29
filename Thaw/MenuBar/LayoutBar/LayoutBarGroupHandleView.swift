//
//  LayoutBarGroupHandleView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

// MARK: - LayoutBarGroupHandleView

/// A small grip drawn at the leading edge of a same-bundle cluster in the
/// layout editor. Dragging the handle moves the whole group as one block,
/// leaving the individual item views draggable on their own.
///
/// The handle is deliberately *not* a `LayoutBarArrangedView`: it lives as a
/// container-managed overlay in a reserved gap beside the cluster, so it never
/// participates in the arranged-view swap/persistence machinery that reorders
/// single items. It is its own `NSDraggingSource` with a dedicated pasteboard
/// type, which `LayoutBarPaddingView` routes to a whole-group drop.
final class LayoutBarGroupHandleView: NSView {
    private enum Metrics {
        static let width: CGFloat = 11
        static let dotDiameter: CGFloat = 2
        static let dotSpacing: CGFloat = 3
        static let columnSpacing: CGFloat = 3
    }

    /// The container the group currently lives in, frozen for the drag.
    weak var sourceContainer: LayoutBarContainer?

    /// The section the group is being dragged out of.
    let sourceSection: MenuBarSection.Name

    /// The persistent identifiers of the group's members, in visual order.
    let memberIdentifiers: [String]

    init(
        sourceContainer: LayoutBarContainer,
        sourceSection: MenuBarSection.Name,
        memberIdentifiers: [String]
    ) {
        self.sourceContainer = sourceContainer
        self.sourceSection = sourceSection
        self.memberIdentifiers = memberIdentifiers
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: Metrics.width, height: 18)))
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The handle's preferred size for a cluster of the given height.
    static func preferredSize(height: CGFloat) -> CGSize {
        CGSize(width: Metrics.width, height: max(height, 18))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_: NSRect) {
        // Two columns of dots — a compact "grip" affordance.
        let color = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
        color.setFill()

        let columnCount = 2
        let rowCount = 3
        let totalColumnsWidth = CGFloat(columnCount) * Metrics.dotDiameter
            + CGFloat(columnCount - 1) * Metrics.columnSpacing
        let totalRowsHeight = CGFloat(rowCount) * Metrics.dotDiameter
            + CGFloat(rowCount - 1) * Metrics.dotSpacing
        let startX = bounds.midX - (totalColumnsWidth / 2)
        let startY = bounds.midY - (totalRowsHeight / 2)

        for column in 0 ..< columnCount {
            for row in 0 ..< rowCount {
                let dot = CGRect(
                    x: startX + CGFloat(column) * (Metrics.dotDiameter + Metrics.columnSpacing),
                    y: startY + CGFloat(row) * (Metrics.dotDiameter + Metrics.dotSpacing),
                    width: Metrics.dotDiameter,
                    height: Metrics.dotDiameter
                )
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    override func mouseDown(with _: NSEvent) {
        // Swallow the mouse-down so the drag begins from this view.
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard !memberIdentifiers.isEmpty else {
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            memberIdentifiers.joined(separator: "\n"),
            forType: .layoutBarGroupHandle
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        if let container = sourceContainer,
           let snapshot = container.snapshotCluster(memberIdentifiers: memberIdentifiers) {
            let frameInSelf = convert(snapshot.rect, from: container)
            draggingItem.setDraggingFrame(frameInSelf, contents: snapshot.image)
        } else {
            draggingItem.setDraggingFrame(bounds, contents: nil)
        }

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: LayoutBarGroupHandleView: NSDraggingSource

extension LayoutBarGroupHandleView: NSDraggingSource {
    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt _: NSPoint) {
        // Freeze the source container so a cache refresh can't dissolve the
        // group mid-drag before the drop commits.
        sourceContainer?.canSetArrangedViews = false
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        // A successful drop re-enables the source container in the drop handler;
        // a cancelled or rejected drag restores it here.
        if operation == [] {
            sourceContainer?.canSetArrangedViews = true
        }
    }
}

// MARK: - Pasteboard type

extension NSPasteboard.PasteboardType {
    static let layoutBarGroupHandle = Self("\(Constants.bundleIdentifier).layout-bar-group-handle")
}
