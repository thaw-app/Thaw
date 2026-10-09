//
//  PrewarmRevealRestorationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins MenuBarItemImageCache.PrewarmRevealRestorationAction.resolve(previous:currentAfterShow:):
/// what a prewarm does with the section it revealed once its capture is done.
@MainActor
@Suite("Prewarm reveal restoration")
struct PrewarmRevealRestorationTests {
    private typealias Action = MenuBarItemImageCache.PrewarmRevealRestorationAction

    @Test("Nothing was revealed before the prewarm, so its section is hidden again")
    func nothingRevealedBeforeHides() {
        #expect(Action.resolve(previous: nil, currentAfterShow: .hidden) == .hide)
        #expect(Action.resolve(previous: nil, currentAfterShow: nil) == .hide)
    }

    @Test("The section revealed before the prewarm is still the one showing")
    func sameSectionIsLeftAlone() {
        #expect(Action.resolve(previous: .hidden, currentAfterShow: .hidden) == .noOp)
        #expect(Action.resolve(previous: .alwaysHidden, currentAfterShow: .alwaysHidden) == .noOp)
    }

    @Test("A different section is showing, so the earlier one is shown again")
    func differentSectionIsRestored() {
        #expect(Action.resolve(previous: .hidden, currentAfterShow: .alwaysHidden) == .show(.hidden))
        #expect(Action.resolve(previous: .alwaysHidden, currentAfterShow: nil) == .show(.alwaysHidden))
    }
}
