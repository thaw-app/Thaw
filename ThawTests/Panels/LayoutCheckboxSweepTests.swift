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
        sweep.extend(from: 20, to: 150, rows: rows)
        #expect(sweep.covered == ["a", "b", "c", "d"])
        #expect(sweep.changes(in: rows) == ["a", "b", "d"])
    }

    @Test("Dragging up covers the rows above, and locked rows neither preview nor change")
    func sweepUpOverLocked() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "d", rows: rows))
        sweep.extend(from: 150, to: 200, rows: rows)
        #expect(sweep.preview(for: rows[4]) == nil)
        sweep.extend(from: 150, to: 60, rows: rows)
        #expect(sweep.covered == ["b", "c", "d"])
        #expect(sweep.changes(in: rows) == ["b", "d"])
    }

    @Test("A drag that stays on its first row is left to the checkbox's own click")
    func staysOnFirstRow() throws {
        var sweep = try #require(LayoutCheckboxSweep(startingAt: "b", rows: rows))
        sweep.extend(from: 50, to: 80, rows: rows)
        #expect(sweep.changes(in: rows).isEmpty)
    }
}
