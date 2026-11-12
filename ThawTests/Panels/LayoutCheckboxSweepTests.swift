//
//  LayoutCheckboxSweepTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

struct LayoutCheckboxSweepTests {
    /// Five 44 pt rows: a, b and d hidden, c shown, e locked.
    private let rows: [LayoutCheckboxSweep.Row] = [
        Self.row("a", 0, shown: false),
        Self.row("b", 1, shown: false),
        Self.row("c", 2, shown: true),
        Self.row("d", 3, shown: false),
        Self.row("e", 4, shown: false, locked: true),
    ]

    private static func row(_ id: String, _ index: CGFloat, shown: Bool, locked: Bool = false) -> LayoutCheckboxSweep.Row {
        LayoutCheckboxSweep.Row(id: id, span: index * 44 ... index * 44 + 44, isShown: shown, isLocked: locked)
    }

    @Test("The sweep takes the state the first row flips to")
    func targetIsFirstRowFlipped() throws {
        #expect(try #require(LayoutCheckboxSweep(startingAt: "a", rows: rows)).target)
        #expect(try !#require(LayoutCheckboxSweep(startingAt: "c", rows: rows)).target)
    }

    @Test("A sweep can't start on a locked row")
    func lockedStart() {
        #expect(LayoutCheckboxSweep(startingAt: "e", rows: rows) == nil)
    }

    @Test("Dragging down covers every row passed and changes only those not in the target state")
    func sweepDown() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "a", rows: rows))
        sweep.extend(to: 150, rows: rows)
        #expect(sweep.covered == ["a", "b", "c", "d"])
        #expect(sweep.changes(in: rows) == ["a", "b", "d"])
    }

    @Test("Dragging up covers the rows above, and locked rows neither preview nor change")
    func sweepUpOverLocked() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "d", rows: rows))
        sweep.extend(to: 200, rows: rows)
        #expect(sweep.preview(for: rows[4]) == nil)
        sweep.extend(to: 60, rows: rows)
        #expect(sweep.covered == ["b", "c", "d"])
        #expect(sweep.changes(in: rows) == ["b", "d"])
    }

    @Test("A drag that stays on its first row is left to the checkbox's own click")
    func staysOnFirstRow() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "b", rows: rows))
        sweep.extend(to: 80, rows: rows)
        #expect(sweep.changes(in: rows).isEmpty)
    }

    @Test("Rows the sweep scrolled out of view stay covered and still change on release")
    func scrolledAwayRowsStayCovered() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "a", rows: rows))
        // The list scrolled: a and b are no longer laid out, and the pointer is on d.
        let scrolled = rows.map { row in
            ["a", "b"].contains(row.id)
                ? LayoutCheckboxSweep.Row(id: row.id, span: nil, isShown: row.isShown, isLocked: row.isLocked)
                : row
        }
        sweep.extend(to: 150, rows: scrolled)
        #expect(sweep.covered == ["a", "b", "c", "d"])
        #expect(sweep.changes(in: scrolled) == ["a", "b", "d"])
    }

    @Test("A pointer past the last row reaches the nearest one, and no laid-out rows leaves the sweep as it was")
    func pointerOutsideRows() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "b", rows: rows))
        sweep.extend(to: 900, rows: rows)
        #expect(sweep.covered == ["b", "c", "d", "e"])

        let unlaid = rows.map { LayoutCheckboxSweep.Row(id: $0.id, span: nil, isShown: $0.isShown, isLocked: $0.isLocked) }
        sweep.extend(to: 0, rows: unlaid)
        #expect(sweep.covered == ["b", "c", "d", "e"])
    }

    // MARK: Step

    @Test("The first move starts the sweep, which counts as a change even on its first row")
    func stepStarts() throws {
        let step = LayoutCheckboxSweep.step(current: nil, startingAt: "a", to: 10, rows: rows)
        #expect(step.didStart)
        #expect(step.didChange)
        #expect(!step.didGrow)
        #expect(try #require(step.sweep).covered == ["a"])
    }

    @Test("A move on a locked first row starts nothing")
    func stepRefusesLockedStart() {
        let step = LayoutCheckboxSweep.step(current: nil, startingAt: "e", to: 200, rows: rows)
        #expect(step.sweep == nil)
        #expect(!step.didStart)
        #expect(!step.didChange)
        #expect(!step.didGrow)
    }

    @Test("A first move already past the first row starts the sweep and grows it")
    func stepStartsAndGrows() throws {
        let step = LayoutCheckboxSweep.step(current: nil, startingAt: "a", to: 100, rows: rows)
        #expect(step.didStart)
        #expect(step.didChange)
        #expect(step.didGrow)
        #expect(try #require(step.sweep).covered == ["a", "b", "c"])
    }

    @Test("Extending down grows the sweep, and a move that covers the same rows changes nothing")
    func stepExtendsDown() throws {
        let start = try #require(LayoutCheckboxSweep(startingAt: "a", rows: rows))
        let grown = LayoutCheckboxSweep.step(current: start, startingAt: "a", to: 100, rows: rows)
        #expect(!grown.didStart)
        #expect(grown.didChange)
        #expect(grown.didGrow)
        #expect(try #require(grown.sweep).covered == ["a", "b", "c"])

        let same = LayoutCheckboxSweep.step(current: grown.sweep, startingAt: "a", to: 95, rows: rows)
        #expect(same.sweep == grown.sweep)
        #expect(!same.didChange)
        #expect(!same.didGrow)
    }

    @Test("Extending up grows the sweep the same way")
    func stepExtendsUp() throws {
        let start = try #require(LayoutCheckboxSweep(startingAt: "d", rows: rows))
        let step = LayoutCheckboxSweep.step(current: start, startingAt: "d", to: 50, rows: rows)
        #expect(step.didChange)
        #expect(step.didGrow)
        #expect(try #require(step.sweep).covered == ["b", "c", "d"])
    }

    @Test("Reversing shrinks the sweep: it changes and redraws but doesn't grow")
    func stepReverses() throws {
        let down = LayoutCheckboxSweep.step(current: nil, startingAt: "b", to: 150, rows: rows)
        let back = LayoutCheckboxSweep.step(current: down.sweep, startingAt: "b", to: 60, rows: rows)
        #expect(back.didChange)
        #expect(!back.didGrow)
        #expect(try #require(back.sweep).covered == ["b"])

        // Crossing over the first row swaps the side the sweep covers; two rows are fewer than three.
        let up = LayoutCheckboxSweep.step(current: down.sweep, startingAt: "b", to: 10, rows: rows)
        #expect(!up.didGrow)
        #expect(try #require(up.sweep).covered == ["a", "b"])
    }

    // MARK: Release

    @Test("Releasing a sweep over several rows moves the ones that change, to the target state")
    func releaseMoves() throws {
        let step = LayoutCheckboxSweep.step(current: nil, startingAt: "a", to: 150, rows: rows)
        let release = try #require(step.sweep?.release(in: rows))
        #expect(release == LayoutCheckboxSweep.Release(ids: ["a", "b", "d"], target: true))
    }

    @Test("A sweep that targets hidden releases the shown rows it covers")
    func releaseHides() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "c", rows: rows))
        sweep.extend(to: 150, rows: rows)
        #expect(sweep.release(in: rows) == LayoutCheckboxSweep.Release(ids: ["c"], target: false))
    }

    @Test("Releasing a drag that stayed on its first row, or covered rows already in the target state, moves nothing")
    func releaseNothing() throws {
        let first = try #require(LayoutCheckboxSweep(startingAt: "a", rows: rows))
        #expect(first.release(in: rows) == nil)

        var covered = try #require(LayoutCheckboxSweep(startingAt: "c", rows: rows))
        covered.extend(to: 150, rows: rows)
        let allHidden = rows.map { LayoutCheckboxSweep.Row(id: $0.id, span: $0.span, isShown: false, isLocked: $0.isLocked) }
        #expect(covered.release(in: allHidden) == nil)
    }
}
