//
//  ThawCapsuleSegmentsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawUI

@Suite("Capsule segments")
struct ThawCapsuleSegmentsTests {
    private typealias Sizing = ThawCapsuleSegments<Int>.Sizing

    @Test("A tab strip fills its row and gives every tab the same height")
    func fillingSizing() {
        let sizing = Sizing.filling
        #expect(sizing.showsTitles)
        #expect(sizing.maxWidth == .infinity)
        #expect(sizing.minWidth == nil)
        #expect(sizing.minHeight == 30)
        #expect(sizing.maxHeight == 30)
        #expect(sizing.inset == ThawSpacing.tight)
        #expect(sizing.horizontalPadding == ThawSpacing.inset)
    }

    @Test("A pill picker sizes to its labels, inset like an action group")
    func fittedSizing() {
        let titled = Sizing.fitted(showsTitles: true)
        #expect(titled.showsTitles)
        #expect(titled.maxWidth == nil)
        #expect(titled.inset == ThawSpacing.capsuleInset)
        #expect(titled.spacing == ThawSpacing.hairline)
        #expect(titled.horizontalPadding == ThawSpacing.row)
    }

    @Test("A symbol-only pill keeps a minimum width for its symbol")
    func symbolOnlySizing() {
        let symbols = Sizing.fitted(showsTitles: false)
        #expect(!symbols.showsTitles)
        #expect(symbols.minWidth == 28)
        #expect(symbols.horizontalPadding < Sizing.fitted(showsTitles: true).horizontalPadding)
    }
}
