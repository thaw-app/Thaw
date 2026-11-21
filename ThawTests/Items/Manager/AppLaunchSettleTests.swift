//
//  AppLaunchSettleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Which app launches hold the move pass until their item re-pairs. Each launch is weighed as it
/// arrives, so a tracked relaunch followed within the second by another app still settles the bar.
@Suite("App launch settle")
struct AppLaunchSettleTests {
    private static let known: Set<String> = ["com.example.tracked:Item-0", "com.example.other-tracked:Clock"]

    @Test("A relaunch of an app Thaw tracks an item for settles on its bundle ID")
    func trackedAppSettles() {
        #expect(MenuBarItemManager.launchSettle(bundleID: "com.example.tracked", knownIdentifiers: Self.known)
            == .appLaunched(bundleID: "com.example.tracked"))
    }

    @Test("An app with no tracked item, or with no bundle ID, starts no settle")
    func untrackedAppDoesNotSettle() {
        #expect(MenuBarItemManager.launchSettle(bundleID: "com.example.unrelated", knownIdentifiers: Self.known) == nil)
        #expect(MenuBarItemManager.launchSettle(bundleID: nil, knownIdentifiers: Self.known) == nil)
    }

    @Test("A bundle ID that only starts like a tracked one isn't taken for it")
    func prefixIsNotAMatch() {
        #expect(MenuBarItemManager.launchSettle(bundleID: "com.example.track", knownIdentifiers: Self.known) == nil)
    }
}
