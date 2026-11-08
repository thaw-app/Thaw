//
//  LayoutBarContainer+Rows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit

/// Drag and drop on a bar that wraps: positions are read along the single-row sweep,
/// and the marker is drawn back on the row it belongs to.
extension LayoutBarContainer {
    var wrapsRows: Bool {
        rowWidth != nil
    }

    /// The frame the view at index would have on one row. On one row, its frame.
    func sweepFrame(at index: Int) -> CGRect {
        let frame = arrangedViews[index].frame
        guard wrapsRows, flow.sweepX.indices.contains(index) else { return frame }
        return CGRect(x: flow.sweepX[index], y: frame.minY, width: frame.width, height: frame.height)
    }

    /// Where a point in the window falls along the single-row sweep.
    func sweepX(at windowLocation: NSPoint) -> CGFloat {
        let point = convert(windowLocation, from: nil)
        return wrapsRows ? flow.sweepPosition(at: point) : point.x
    }

    /// Where the drop marker goes, and the band it spans: the whole bar, or one row of it.
    func dropMarker() -> (x: CGFloat, band: CGRect)? {
        if let markerX = groupDropMarkerX {
            guard wrapsRows else { return (markerX, bounds) }
            guard let spot = flow.wrappedPosition(atSweep: markerX) else { return nil }
            return (spot.x, flow.band(ofRow: spot.row, width: bounds.width))
        }
        let gap = arrangedViews.indices.filter { arrangedViews[$0].isDraggingPlaceholder }
        guard let first = gap.first else { return nil }
        guard wrapsRows, flow.row.indices.contains(first) else {
            return LayoutBarDropMarker.x(inGap: gap.map { arrangedViews[$0].frame }).map { ($0, bounds) }
        }
        // A gap that wraps is marked on the row it opens on.
        let line = flow.row[first]
        let onRow = gap.filter { flow.row.indices.contains($0) && flow.row[$0] == line }
        return LayoutBarDropMarker.x(inGap: onRow.map { arrangedViews[$0].frame })
            .map { ($0, flow.band(ofRow: line, width: bounds.width)) }
    }

    /// The bar's height at a row width, before it lays out at that width.
    func wrappedHeight(rowWidth: CGFloat) -> CGFloat {
        LayoutBarRowFlow(widths: flow.widths, leads: flow.leads, rowHeight: flow.rowHeight, rowWidth: rowWidth).height
    }

    /// Points the group marker at the slot a handle drop at windowLocation would take.
    func showGroupDropMarker(at windowLocation: NSPoint) {
        let frames = arrangedViews.indices.filter { !arrangedViews[$0].isNewItemsBadge }.map(sweepFrame(at:))
        let boundary = groupDropDestination(atX: sweepX(at: windowLocation)).boundary
        groupDropMarkerX = LayoutBarDropMarker.x(insertingAt: boundary, among: frames)
    }

    /// The arranged view sitting closest to xPosition, comparing horizontal
    /// centers along the single-row sweep, which wrapped rows map back onto.
    ///
    /// Center, not edge, so a wide view does not swallow its neighbours' slots.
    /// Ties go to the leftmost view.
    ///
    /// - Parameters:
    ///   - xPosition: The sweep position to measure from, usually a dragging
    ///     location passed through sweepX(at:).
    ///   - excludingBadge: Pass true to keep the new-items badge out of the
    ///     running, so an ordinary drag never shoves it aside.
    func closestView(toX xPosition: CGFloat, excludingBadge: Bool = false) -> LayoutBarArrangedView? {
        arrangedViews.indices
            .filter { !excludingBadge || !arrangedViews[$0].isNewItemsBadge }
            .map { (view: arrangedViews[$0], offset: abs(sweepFrame(at: $0).midX - xPosition)) }
            .min { $0.offset < $1.offset }?
            .view
    }

    /// Splits an ascending index list into its maximal contiguous runs.
    static func contiguousRuns(of indices: [Int]) -> [[Int]] {
        var runs = [[Int]]()
        for index in indices {
            if var last = runs.last, let tail = last.last, index == tail + 1 {
                last.append(index)
                runs[runs.count - 1] = last
            } else {
                runs.append([index])
            }
        }
        return runs
    }
}
