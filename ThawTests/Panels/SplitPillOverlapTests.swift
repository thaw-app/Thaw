//
//  SplitPillOverlapTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Split shape when the application menu reaches the items", .bug("https://github.com/thaw-app/Thaw/issues/1324"))
struct SplitPillOverlapTests {
    private let leading = CGRect(x: 8, y: 0, width: 500, height: 24)
    private let trailing = CGRect(x: 900, y: 0, width: 600, height: 24)

    @Test("Overlapping halves are both kept, so the builder draws one merged shape")
    func overlapKeepsBothHalves() {
        let longMenu = CGRect(x: 8, y: 0, width: 950, height: 24)
        let resolved = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: longMenu,
            trailing: trailing,
            geometryFrozen: false,
            lastStableLeading: leading,
            lastStableTrailing: trailing
        )
        #expect(resolved.leading == longMenu)
        #expect(resolved.trailing == trailing)
        #expect(resolved.leading.intersects(resolved.trailing))
    }

    @Test("Halves with a gap between them stay two shapes")
    func separateHalvesStaySeparate() {
        let resolved = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: leading,
            trailing: trailing,
            geometryFrozen: false,
            lastStableLeading: .zero,
            lastStableTrailing: .zero
        )
        #expect(resolved.leading == leading)
        #expect(resolved.trailing == trailing)
        #expect(!resolved.leading.intersects(resolved.trailing))
    }
}
