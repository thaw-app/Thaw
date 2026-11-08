//
//  LayoutBarRowFlow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Where one section's items sit when the bar wraps them onto as many rows as its width needs.
///
/// Every view also keeps its place in the single-row sweep, and a point on the wrapped bar maps
/// back to that sweep, so the drag and drop rules, written for one row, read several the same way.
nonisolated struct LayoutBarRowFlow: Equatable {
    static let rowSpacing: CGFloat = 4

    /// Each view's leading edge on its row. Wrapped rows are pushed to end at the row width.
    let wrappedX: [CGFloat]
    /// Each view's leading edge in the single row.
    let sweepX: [CGFloat]
    /// The row each view is on, top first.
    let row: [Int]
    let widths: [CGFloat]
    /// The room held open ahead of each view, where a group's grip sits.
    let leads: [CGFloat]
    let rowHeight: CGFloat
    let rowCount: Int
    /// The widest row, or the single row's length.
    let contentWidth: CGFloat

    /// - Parameter rowWidth: The room a row has; nil keeps every view on one row.
    init(widths: [CGFloat], leads: [CGFloat], rowHeight: CGFloat, rowWidth: CGFloat?) {
        precondition(widths.count == leads.count)
        var wrappedX = [CGFloat]()
        var sweepX = [CGFloat]()
        var row = [Int]()
        var sweep: CGFloat = 0
        var lineX: CGFloat = 0
        var line = 0
        var widest: CGFloat = 0
        for (viewWidth, lead) in zip(widths, leads) {
            // A view that does not fit starts the next row, unless it would be alone on this one.
            if let rowWidth, lineX > 0, lineX + lead + viewWidth > rowWidth {
                line += 1
                lineX = 0
            }
            sweep += lead
            lineX += lead
            wrappedX.append(lineX)
            sweepX.append(sweep)
            row.append(line)
            sweep += viewWidth
            lineX += viewWidth
            widest = max(widest, lineX)
        }
        // Rows end at the trailing edge, as the menu bar's items do.
        if let rowWidth {
            for line in 0 ..< (row.last.map { $0 + 1 } ?? 0) {
                let indices = row.indices.filter { row[$0] == line }
                guard let last = indices.last else { continue }
                let shift = max(0, rowWidth - (wrappedX[last] + widths[last]))
                for index in indices {
                    wrappedX[index] += shift
                }
            }
        }
        self.wrappedX = wrappedX
        self.sweepX = sweepX
        self.row = row
        self.widths = widths
        self.leads = leads
        self.rowHeight = rowHeight
        self.rowCount = widths.isEmpty ? 1 : line + 1
        self.contentWidth = rowWidth == nil ? sweep : widest
    }

    var height: CGFloat {
        CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * Self.rowSpacing
    }

    /// A row's band in a view of this flow's height whose origin is at the bottom, as AppKit's is.
    func band(ofRow line: Int, width: CGFloat) -> CGRect {
        let top = height - CGFloat(line) * (rowHeight + Self.rowSpacing)
        return CGRect(x: 0, y: top - rowHeight, width: width, height: rowHeight)
    }

    /// The row whose band is nearest y.
    func row(atY y: CGFloat) -> Int {
        let fromTop = height - y
        let line = Int((fromTop / (rowHeight + Self.rowSpacing)).rounded(.down))
        return min(max(line, 0), rowCount - 1)
    }

    /// Where a point on the wrapped bar falls in the single row.
    ///
    /// Kept a hair inside the row's own span, so the edge of a row never reads as the item
    /// that ends the row above or starts the row below.
    func sweepPosition(at point: CGPoint) -> CGFloat {
        let line = row(atY: point.y)
        guard let first = row.firstIndex(of: line), let last = row.lastIndex(of: line) else {
            return 0
        }
        let start = wrappedX[first]
        let end = wrappedX[last] + widths[last]
        let x = min(max(point.x, start + Self.edgeInset), max(start + Self.edgeInset, end - Self.edgeInset))
        return sweepX[first] + (x - start)
    }

    /// Where a position in the single row sits on the wrapped bar: a row and an x on it.
    /// A position between two rows goes to the end of the earlier one.
    func wrappedPosition(atSweep position: CGFloat) -> (row: Int, x: CGFloat)? {
        guard !sweepX.isEmpty else { return nil }
        let index = sweepX.indices.first { position <= sweepX[$0] + widths[$0] } ?? sweepX.count - 1
        let offset = min(max(position - sweepX[index], -leads[index]), widths[index])
        return (row[index], wrappedX[index] + offset)
    }

    /// The runs of indices that sit side by side, split where the bar wraps.
    func splitByRow(_ run: [Int]) -> [[Int]] {
        var runs = [[Int]]()
        for index in run {
            if let tail = runs.last?.last, row.indices.contains(index), row.indices.contains(tail), row[tail] == row[index] {
                runs[runs.count - 1].append(index)
            } else {
                runs.append([index])
            }
        }
        return runs
    }

    private static let edgeInset: CGFloat = 0.5
}
