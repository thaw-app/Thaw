//
//  LayoutCheckboxSweep.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics

/// A drag down the list's checkboxes: every row it passes takes the state the first row
/// flips to, and the release moves them all in one batch, so one undo puts them back.
nonisolated struct LayoutCheckboxSweep: Equatable {
    /// A row as the sweep sees it, with its vertical span in the list's coordinates.
    /// A row scrolled out of view isn't laid out and has no span.
    struct Row: Equatable {
        let id: String
        let span: ClosedRange<CGFloat>?
        let isShown: Bool
        let isLocked: Bool
    }

    /// The coordinate space rows report their spans in and the drag reads its location in.
    static let coordinateSpace = "LayoutItemListContent"

    let startID: String
    /// Checked or unchecked: the opposite of where the first row started.
    let target: Bool
    private(set) var covered: [String]

    /// A sweep starting on startID, or nil when that row can't change.
    init?(startingAt startID: String, rows: [Row]) {
        guard let start = rows.first(where: { $0.id == startID }), !start.isLocked else { return nil }
        self.startID = startID
        target = !start.isShown
        covered = [startID]
    }

    /// Covers every row from the first one to the one under the pointer, both ends included.
    /// Counted in list order: a sweep that scrolls the list leaves its first rows without a span.
    mutating func extend(to currentY: CGFloat, rows: [Row]) {
        guard let start = rows.firstIndex(where: { $0.id == startID }), let end = Self.index(nearest: currentY, in: rows) else { return }
        covered = rows[min(start, end) ... max(start, end)].map(\.id)
    }

    /// The laid-out row under y, or the closest one when y is past the rows.
    private static func index(nearest y: CGFloat, in rows: [Row]) -> Int? {
        func distance(_ span: ClosedRange<CGFloat>) -> CGFloat {
            max(span.lowerBound - y, y - span.upperBound, 0)
        }
        return rows.indices
            .compactMap { index in rows[index].span.map { (index, distance($0)) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// The state a covered row shows while the drag is under way, or nil when the sweep doesn't reach it.
    func preview(for row: Row) -> Bool? {
        guard !row.isLocked, covered.contains(row.id) else { return nil }
        return target
    }

    /// The rows the release moves: covered, free to change and not already in the target state.
    /// Empty when the drag stayed on its first row, which the checkbox's own click handles.
    func changes(in rows: [Row]) -> [String] {
        guard covered.contains(where: { $0 != startID }) else { return [] }
        let covered = Set(covered)
        return rows.filter { covered.contains($0.id) && !$0.isLocked && $0.isShown != target }.map(\.id)
    }

    /// What one pointer move does to the sweep under way, or to none yet.
    struct Step: Equatable {
        /// The sweep after the move: nil when no sweep is under way and none could start.
        let sweep: LayoutCheckboxSweep?
        /// The move began the sweep, so the caller starts scrolling with it.
        let didStart: Bool
        /// The sweep differs from before, so the rows redraw. A mouse move that changes nothing doesn't.
        let didChange: Bool
        /// The move covered more rows than before, which the caller marks with a tap of haptics.
        let didGrow: Bool
    }

    /// Applies the pointer at y to current, starting a sweep on startID first when none is under way.
    static func step(current: LayoutCheckboxSweep?, startingAt startID: String, to y: CGFloat, rows: [Row]) -> Step {
        let started = current == nil ? LayoutCheckboxSweep(startingAt: startID, rows: rows) : nil
        guard let before = current ?? started else {
            return Step(sweep: nil, didStart: false, didChange: false, didGrow: false)
        }
        var sweep = before
        sweep.extend(to: y, rows: rows)
        let moved = sweep != before
        // A sweep that has just started counts as changed even when the pointer hasn't left its first row.
        return Step(
            sweep: sweep,
            didStart: started != nil,
            didChange: moved || started != nil,
            didGrow: moved && sweep.covered.count > before.covered.count
        )
    }

    /// The batch a release moves.
    struct Release: Equatable {
        let ids: [String]
        /// Whether the rows end up checked.
        let target: Bool
    }

    /// What the release moves, or nil when nothing changes.
    func release(in rows: [Row]) -> Release? {
        let ids = changes(in: rows)
        return ids.isEmpty ? nil : Release(ids: ids, target: target)
    }
}
