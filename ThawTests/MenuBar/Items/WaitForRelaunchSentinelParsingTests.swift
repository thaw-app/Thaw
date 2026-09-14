//
//  WaitForRelaunchSentinelParsingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the waitForRelaunch sentinel's string format, including the
/// unix-time suffix added in #1079 so a sentinel whose app never
/// relaunches can be aged out. The format must round-trip and must stay
/// backward-compatible with the pre-#1079 two-field form.
@MainActor
@Suite("Wait-for-relaunch sentinel parsing")
final class WaitForRelaunchSentinelParsingTests {
    @Test("The new format round-trips with the timestamp")
    func newFormatRoundTrips() throws {
        let manager = MenuBarItemManager()
        let setAt = Date(timeIntervalSince1970: 1_750_000_000)
        let value = manager.waitForRelaunchValue(windowID: 12345, section: .hidden, setAt: setAt)

        #expect(value == "waitForRelaunch:12345:hidden:1750000000")

        let parsed = try #require(manager.parseWaitForRelaunch(value))
        #expect(parsed.windowID == 12345)
        #expect(parsed.section == .hidden)
        #expect(parsed.setAt == setAt)
    }

    @Test("The old two-field format parses with a nil setAt")
    func oldFormatParsesWithNilSetAt() throws {
        let manager = MenuBarItemManager()
        let parsed = try #require(manager.parseWaitForRelaunch("waitForRelaunch:12345:hidden"))

        #expect(parsed.windowID == 12345)
        #expect(parsed.section == .hidden)
        #expect(parsed.setAt == nil, "pre-#1079 sentinels carry no timestamp")
    }

    @Test("A plain section key is not a sentinel")
    func plainSectionKeyIsNotASentinel() {
        let manager = MenuBarItemManager()
        #expect(manager.parseWaitForRelaunch("hidden") == nil)
        #expect(manager.parseWaitForRelaunch("alwaysHidden") == nil)
    }

    @Test("A sentinel for the always-hidden section round-trips")
    func alwaysHiddenRoundTrips() throws {
        let manager = MenuBarItemManager()
        let value = manager.waitForRelaunchValue(windowID: 7, section: .alwaysHidden)

        let parsed = try #require(manager.parseWaitForRelaunch(value))
        #expect(parsed.windowID == 7)
        #expect(parsed.section == .alwaysHidden)
        #expect(parsed.setAt != nil)
    }
}
