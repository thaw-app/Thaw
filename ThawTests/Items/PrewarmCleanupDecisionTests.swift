//
//  PrewarmCleanupDecisionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Prewarm cleanup may reconceal only its own reveal, and only if no user reveal followed the capture's last hide.
struct PrewarmCleanupDecisionTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test("No user reveal ever: the prewarm hides its own reveal")
    func noUserReveal() {
        #expect(MenuBarItemImageCache.PrewarmRevealRestorationAction.cleanupMayHide(userRevealDate: nil, lastCaptureHideDate: nil))
        #expect(MenuBarItemImageCache.PrewarmRevealRestorationAction.cleanupMayHide(userRevealDate: nil, lastCaptureHideDate: t0))
    }

    @Test("A user reveal newer than the capture's last hide owns the live reveal")
    func userOwns() {
        #expect(!MenuBarItemImageCache.PrewarmRevealRestorationAction.cleanupMayHide(userRevealDate: t0 + 5, lastCaptureHideDate: nil))
        #expect(!MenuBarItemImageCache.PrewarmRevealRestorationAction.cleanupMayHide(userRevealDate: t0 + 5, lastCaptureHideDate: t0))
    }

    @Test("A user reveal older than the capture's last hide was already settled")
    func userSettled() {
        #expect(MenuBarItemImageCache.PrewarmRevealRestorationAction.cleanupMayHide(userRevealDate: t0, lastCaptureHideDate: t0 + 5))
    }
}
