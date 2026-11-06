//
//  ItemMoveOptionsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Move options")
struct ItemMoveOptionsTests {
    /// Callers that pass no options rely on these to stay cautious.
    @Test("The default options describe an automatic move that waits and refuses unusual sources and targets")
    func defaultsAreAutomatic() {
        let options = ItemMoveOptions()
        #expect(!options.skipInputPause)
        #expect(!options.allowSectionBoundaryTarget)
        #expect(!options.allowParkedOffMenuBarSource)
        #expect(options.anchorFallbacks.isEmpty)
        #expect(!options.isUserInitiated)
        #expect(!options.recoveringUnplacedItem)
    }
}
