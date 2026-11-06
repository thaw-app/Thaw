//
//  OccupancyForecastTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing

@Suite("Occupancy forecast")
struct OccupancyForecastTests {
    private typealias Item = OccupancyPlanner.ProjectedItem

    /// Builds a left-to-right run of items, each width wide, starting at 0.
    private func run(widths: [CGFloat?]) -> [Item] {
        var edge = CGFloat.zero
        return widths.enumerated().map { index, width in
            let item = Item(identifier: "item\(index)", width: width, leadingEdge: edge)
            edge += width ?? 20
            return item
        }
    }

    // MARK: - Degenerate inputs

    @Test("An empty bar fits rather than reading as indeterminate")
    func emptyBarFits() {
        let forecast = OccupancyPlanner.forecast(items: [], capacity: 500)
        #expect(forecast.outcome == .fits)
        #expect(forecast.projectedOccupancy == 0)
    }

    @Test("Zero or negative capacity is indeterminate, never a fit")
    func invalidCapacityIsIndeterminate() {
        for capacity in [CGFloat.zero, -1, -1000] {
            let forecast = OccupancyPlanner.forecast(items: run(widths: [10]), capacity: capacity)
            #expect(forecast.outcome == .indeterminate(.invalidCapacity))
        }
    }

    @Test("One unknown width poisons the whole projection")
    func unknownWidthPoisonsProjection() {
        let items = run(widths: [20, nil, 20])
        let forecast = OccupancyPlanner.forecast(items: items, capacity: 500)
        #expect(forecast.outcome == .indeterminate(.unknownWidths))
        #expect(forecast.projectedOccupancy == 0)
    }

    @Test("An unknown width is indeterminate even when the known items alone overflow")
    func unknownWidthOutranksOverflow() {
        let items = run(widths: [400, nil, 400])
        let forecast = OccupancyPlanner.forecast(items: items, capacity: 100)
        #expect(forecast.outcome == .indeterminate(.unknownWidths))
    }

    @Test("NaN and infinite geometry are rejected at the input boundary")
    func invalidGeometryIsRejected() {
        let nanWidth = [Item(identifier: "a", width: .nan, leadingEdge: 0)]
        #expect(
            OccupancyPlanner.forecast(items: nanWidth, capacity: 100).outcome
                == .indeterminate(.invalidGeometry)
        )

        let nanEdge = [Item(identifier: "a", width: 10, leadingEdge: .nan)]
        #expect(
            OccupancyPlanner.forecast(items: nanEdge, capacity: 100).outcome
                == .indeterminate(.invalidGeometry)
        )

        let infiniteWidth = [Item(identifier: "a", width: .infinity, leadingEdge: 0)]
        #expect(
            OccupancyPlanner.forecast(items: infiniteWidth, capacity: 100).outcome
                == .indeterminate(.invalidGeometry)
        )

        #expect(
            OccupancyPlanner.forecast(items: run(widths: [10]), capacity: .nan).outcome
                == .indeterminate(.invalidGeometry)
        )
    }

    @Test("A negative width is geometry corruption, not a narrow item")
    func negativeWidthIsRejected() {
        let items = [Item(identifier: "a", width: -5, leadingEdge: 0)]
        #expect(
            OccupancyPlanner.forecast(items: items, capacity: 100).outcome
                == .indeterminate(.invalidGeometry)
        )
    }

    // MARK: - Fitting

    @Test("Items that fit report the total occupancy")
    func fittingItemsReportOccupancy() {
        let forecast = OccupancyPlanner.forecast(items: run(widths: [30, 30, 40]), capacity: 200)
        #expect(forecast.outcome == .fits)
        #expect(forecast.projectedOccupancy == 100)
        #expect(forecast.capacity == 200)
    }

    @Test("Exactly filling capacity fits — the boundary is inclusive")
    func exactFitFits() {
        let forecast = OccupancyPlanner.forecast(items: run(widths: [50, 50]), capacity: 100)
        #expect(forecast.outcome == .fits)
    }

    @Test("One point past capacity ejects")
    func onePointPastCapacityEjects() {
        let forecast = OccupancyPlanner.forecast(items: run(widths: [50, 51]), capacity: 100)
        guard case let .ejects(ejections) = forecast.outcome else {
            Issue.record("expected an ejection, got \(forecast.outcome)")
            return
        }
        #expect(ejections.count == 1)
    }

    // MARK: - Ejection

    @Test("The leftmost item is ejected first and carries the largest overflow")
    func leftmostEjectsFirst() {
        // Four 50pt items, 100pt of room: the two rightmost survive.
        let forecast = OccupancyPlanner.forecast(items: run(widths: [50, 50, 50, 50]), capacity: 100)
        guard case let .ejects(ejections) = forecast.outcome else {
            Issue.record("expected ejections, got \(forecast.outcome)")
            return
        }
        #expect(ejections.map(\.identifier) == ["item0", "item1"])
        #expect(ejections[0].overflow == 100)
        #expect(ejections[1].overflow == 50)
        #expect(forecast.projectedOccupancy == 200)
    }

    @Test("Overflow is measured past capacity, not past the previous item")
    func overflowIsMeasuredPastCapacity() {
        let forecast = OccupancyPlanner.forecast(items: run(widths: [10, 100]), capacity: 60)
        guard case let .ejects(ejections) = forecast.outcome else {
            Issue.record("expected ejections, got \(forecast.outcome)")
            return
        }
        // Rightmost (100) alone already exceeds 60 by 40; adding the 10pt item
        // on its left puts the running total 50 past capacity.
        #expect(ejections.map(\.identifier) == ["item0", "item1"])
        #expect(ejections[0].overflow == 50)
        #expect(ejections[1].overflow == 40)
    }

    @Test("Ejection order is deterministic when several items share a leading edge")
    func tiedLeadingEdgesAreDeterministic() {
        let tied = [
            Item(identifier: "b", width: 50, leadingEdge: 0),
            Item(identifier: "a", width: 50, leadingEdge: 0),
            Item(identifier: "c", width: 50, leadingEdge: 100),
        ]
        let first = OccupancyPlanner.forecast(items: tied, capacity: 60)
        let second = OccupancyPlanner.forecast(items: tied.reversed(), capacity: 60)
        #expect(first.outcome == second.outcome)
    }

    @Test("Input order does not change the result")
    func inputOrderIsIrrelevant() {
        let items = run(widths: [50, 50, 50, 50])
        let forward = OccupancyPlanner.forecast(items: items, capacity: 100)
        let shuffled = OccupancyPlanner.forecast(items: items.reversed(), capacity: 100)
        #expect(forward.outcome == shuffled.outcome)
        #expect(forward.projectedOccupancy == shuffled.projectedOccupancy)
    }

    @Test("Every item ejects when even the rightmost cannot fit")
    func everythingEjectsWhenNothingFits() {
        let forecast = OccupancyPlanner.forecast(items: run(widths: [40, 40]), capacity: 10)
        guard case let .ejects(ejections) = forecast.outcome else {
            Issue.record("expected ejections, got \(forecast.outcome)")
            return
        }
        #expect(ejections.count == 2)
    }
}
