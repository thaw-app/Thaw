//
//  NotchOcclusionDeficitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Notch occlusion deficit")
struct NotchOcclusionDeficitTests {
    private let nominal = MenuBarItemManager.nominalStatusItemWidth

    @Test("A covered control withholds its width plus one item, and grows while still covered")
    func growsWhileCovered() throws {
        let first = try #require(MenuBarItemManager.notchOcclusionDeficit(
            previous: nil,
            occludedControlWidth: 20,
            visibleUIDs: ["a", "b", "c"],
            overflowUIDs: []
        ))
        #expect(first.width == 20 + nominal)

        // The pass concealed "c"; membership counts it, so the deficit carries.
        let second = try #require(MenuBarItemManager.notchOcclusionDeficit(
            previous: first,
            occludedControlWidth: 20,
            visibleUIDs: ["a", "b"],
            overflowUIDs: ["c"]
        ))
        #expect(second.width == first.width + 20 + nominal)
    }

    @Test("Once the icon clears the notch the deficit holds, so the concealed item is not re-admitted")
    func holdsAfterClearing() throws {
        let previous = (width: CGFloat(44), visibleUIDs: Set(["a", "b", "c"]))
        let held = try #require(MenuBarItemManager.notchOcclusionDeficit(
            previous: previous,
            occludedControlWidth: 0,
            visibleUIDs: ["a", "b"],
            overflowUIDs: ["c"]
        ))
        #expect(held.width == 44)
    }

    @Test("An item arriving or leaving drops the deficit")
    func dropsOnMembershipChange() {
        let previous = (width: CGFloat(44), visibleUIDs: Set(["a", "b", "c"]))
        #expect(MenuBarItemManager.notchOcclusionDeficit(
            previous: previous,
            occludedControlWidth: 0,
            visibleUIDs: ["a", "b"],
            overflowUIDs: []
        ) == nil)
    }

    @Test("The deficit is capped so a cover that never clears cannot empty the bar")
    func isCapped() throws {
        let previous = (width: MenuBarItemManager.maximumNotchOcclusionDeficit, visibleUIDs: Set(["a"]))
        let capped = try #require(MenuBarItemManager.notchOcclusionDeficit(
            previous: previous,
            occludedControlWidth: 20,
            visibleUIDs: ["a"],
            overflowUIDs: []
        ))
        #expect(capped.width == MenuBarItemManager.maximumNotchOcclusionDeficit)
    }
}
