//
//  LayoutBannerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Layout shows one warning at a time, the most serious first")
struct LayoutBannerTests {
    private func banner(denied: Bool = false, outOfReach: Bool = false, recording: Bool = true) -> LayoutBanner? {
        LayoutBanner.mostSerious(isDeniedBySystem: denied, hasItemsOutOfReach: outOfReach, hasScreenRecording: recording)
    }

    @Test("Thaw switched off in System Settings outranks everything")
    func deniedComesFirst() {
        #expect(banner(denied: true, outOfReach: true, recording: false) == .deniedBySystem)
    }

    @Test("Items out of reach outrank a missing Screen Recording grant")
    func outOfReachComesSecond() {
        #expect(banner(outOfReach: true, recording: false) == .outOfReach)
    }

    @Test("A missing Screen Recording grant shows when nothing worse is true")
    func screenRecordingComesLast() {
        #expect(banner(recording: false) == .noScreenRecording)
        #expect(banner() == nil)
    }

    @Test("Tips show beside no warning or the Screen Recording one, and not beside a broken state")
    func tipsStayAwayFromBrokenStates() {
        #expect(LayoutBanner.allowsTips(beside: nil))
        #expect(LayoutBanner.allowsTips(beside: .noScreenRecording))
        #expect(!LayoutBanner.allowsTips(beside: .outOfReach))
        #expect(!LayoutBanner.allowsTips(beside: .deniedBySystem))
    }
}
