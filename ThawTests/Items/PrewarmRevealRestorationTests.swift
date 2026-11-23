//
//  PrewarmRevealRestorationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// What a prewarm does with the section it revealed once its capture is done.
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

/// Prewarm cleanup may reconceal only its own reveal, and only if no user reveal followed the capture's last hide.
@Suite("Prewarm cleanup decision")
struct PrewarmCleanupDecisionTests {
    private typealias Action = MenuBarItemImageCache.PrewarmRevealRestorationAction

    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test("No user reveal ever: the prewarm hides its own reveal")
    func noUserReveal() {
        #expect(Action.cleanupMayHide(userRevealDate: nil, lastCaptureHideDate: nil))
        #expect(Action.cleanupMayHide(userRevealDate: nil, lastCaptureHideDate: t0))
    }

    @Test("A user reveal newer than the capture's last hide owns the live reveal")
    func userOwns() {
        #expect(!Action.cleanupMayHide(userRevealDate: t0 + 5, lastCaptureHideDate: nil))
        #expect(!Action.cleanupMayHide(userRevealDate: t0 + 5, lastCaptureHideDate: t0))
    }

    @Test("A user reveal older than the capture's last hide was already settled")
    func userSettled() {
        #expect(Action.cleanupMayHide(userRevealDate: t0, lastCaptureHideDate: t0 + 5))
    }
}
