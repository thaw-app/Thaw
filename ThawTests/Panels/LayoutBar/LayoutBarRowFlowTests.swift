//
//  LayoutBarRowFlowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Wrapping a section's items onto rows, and reading a point on the rows back into the single row.
struct LayoutBarRowFlowTests {
    /// Ten 24pt items, the fourth leading a group whose grip takes 15pt.
    private static func flow(rowWidth: CGFloat?) -> LayoutBarRowFlow {
        let leads: [CGFloat] = (0 ..< 10).map { $0 == 3 ? 15 : 0 }
        return LayoutBarRowFlow(widths: Array(repeating: 24, count: 10), leads: leads, rowHeight: 24, rowWidth: rowWidth)
    }

    @Test("Without a row width every item is on one row, end to end", arguments: [CGFloat?.none, 10000])
    func oneRow(rowWidth: CGFloat?) {
        let flow = Self.flow(rowWidth: rowWidth)
        #expect(flow.rowCount == 1)
        #expect(flow.row.allSatisfy { $0 == 0 })
        // A wide enough row holds them all, pushed to its trailing edge.
        let shift = rowWidth.map { $0 - (flow.sweepX[9] + 24) } ?? 0
        #expect(flow.wrappedX == flow.sweepX.map { $0 + shift })
        #expect(flow.sweepX[3] == CGFloat(24 * 3 + 15), "the grip's room comes before the group's first item")
        #expect(flow.height == 24)
    }

    @Test("Rows hold as many items as fit, and the grip's room counts", arguments: [
        (CGFloat(100), [0, 0, 0, 1, 1, 1, 2, 2, 2, 2]),
        (CGFloat(130), [0, 0, 0, 0, 1, 1, 1, 1, 1, 2]),
        (CGFloat(260), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        // Narrower than one item: one item a row, never an empty one.
        (CGFloat(10), Array(0 ..< 10)),
    ])
    func wrapping(rowWidth: CGFloat, rows: [Int]) {
        let flow = Self.flow(rowWidth: rowWidth)
        #expect(flow.row == rows)
        #expect(flow.rowCount == (rows.last ?? 0) + 1)
        for index in flow.row.indices where index == flow.row.count - 1 || flow.row[index] != flow.row[index + 1] {
            #expect(flow.wrappedX[index] + 24 == max(rowWidth, flow.leads[index] + 24), "a row ends at the trailing edge, as the menu bar does")
        }
        #expect(flow.height == CGFloat(flow.rowCount) * 24 + CGFloat(flow.rowCount - 1) * LayoutBarRowFlow.rowSpacing)
    }

    @Test("An empty section keeps one row to drop into")
    func emptySection() {
        let flow = LayoutBarRowFlow(widths: [], leads: [], rowHeight: 24, rowWidth: 100)
        #expect(flow.rowCount == 1)
        #expect(flow.height == 24)
        #expect(flow.wrappedPosition(atSweep: 0) == nil)
    }

    @Test("The first row is the top band, as AppKit's origin is at the bottom")
    func bands() {
        let flow = Self.flow(rowWidth: 100)
        #expect(flow.band(ofRow: 0, width: 100).maxY == flow.height)
        #expect(flow.band(ofRow: 2, width: 100).minY == 0)
        #expect(flow.row(atY: flow.height - 1) == 0)
        #expect(flow.row(atY: 1) == 2)
        #expect(flow.row(atY: -50) == 2, "below the bar reads as its last row")
        #expect(flow.row(atY: flow.height + 50) == 0, "above it, as its first")
    }

    @Test("A point on a row reads back to the same place in the single row")
    func sweepPosition() {
        let flow = Self.flow(rowWidth: 100)
        // Row 1 holds items 3, 4 and 5; item 4 is its second.
        let middle = CGPoint(x: flow.wrappedX[4] + 12, y: flow.band(ofRow: 1, width: 100).midY)
        #expect(flow.sweepPosition(at: middle) == flow.sweepX[4] + 12)
    }

    @Test("Past either end of a row, a point stays on that row's own items")
    func rowEnds() {
        let flow = Self.flow(rowWidth: 100)
        let rowY = flow.band(ofRow: 1, width: 100).midY
        let pastEnd = flow.sweepPosition(at: CGPoint(x: 99, y: rowY))
        #expect(pastEnd > flow.sweepX[5] + 12 && pastEnd < flow.sweepX[6], "after the row's last item, before the next row's first")
        let beforeStart = flow.sweepPosition(at: CGPoint(x: 0, y: rowY))
        #expect(beforeStart > flow.sweepX[3] && beforeStart < flow.sweepX[3] + 12, "before the row's first item's middle")
    }

    @Test("A single-row position maps onto its item's row")
    func wrappedPosition() throws {
        let flow = Self.flow(rowWidth: 100)
        let spot = try #require(flow.wrappedPosition(atSweep: flow.sweepX[7] + 5))
        #expect(spot.row == 2)
        #expect(spot.x == flow.wrappedX[7] + 5)
        let end = try #require(flow.wrappedPosition(atSweep: flow.sweepX[9] + 24))
        #expect(end.row == 2)
        #expect(end.x == flow.wrappedX[9] + 24, "the end of the bar is the end of its last row")
    }

    @Test("A group's background splits where the bar wraps")
    func splitByRow() {
        let flow = Self.flow(rowWidth: 100)
        #expect(flow.splitByRow([1, 2, 3, 4]) == [[1, 2], [3, 4]])
        #expect(flow.splitByRow([4, 5]) == [[4, 5]])
    }
}
