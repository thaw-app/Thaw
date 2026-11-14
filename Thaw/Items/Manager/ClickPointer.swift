//
//  ClickPointer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The pointer actions a synthetic click performs, replaceable in tests.
struct ClickPointer {
    var warp: (CGPoint) -> Void
    var hide: () -> Void
    var show: () -> Void
    /// Lets the Window Server take the warp before events are posted.
    var settle: () async -> Void

    static func live(settle: @escaping () async -> Void) -> ClickPointer {
        ClickPointer(
            warp: { MouseHelpers.warpCursor(to: $0) },
            hide: { MouseHelpers.hideCursor() },
            show: { MouseHelpers.showCursor() },
            settle: settle
        )
    }
}

extension MenuBarItemManager {
    /// Parks the hidden pointer on point for body, then puts it back at restore however body ends.
    static func withPointerParked(
        at point: CGPoint,
        restoringTo restore: CGPoint,
        pointer: ClickPointer,
        body: () async throws -> Void
    ) async throws {
        pointer.warp(point)
        await pointer.settle()
        pointer.hide()
        defer {
            pointer.warp(restore)
            pointer.show()
        }
        // Checked only once the restore is in place, so a cancelled click still puts the pointer back.
        try Task.checkCancellation()
        try await body()
    }
}
