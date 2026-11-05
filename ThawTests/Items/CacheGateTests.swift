//
//  CacheGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Cache gate")
struct CacheGateTests {
    @Test("Admits one pass at a time and coalesces reruns into one follow-up")
    func admissionAndCoalescedReruns() async {
        let gate = MenuBarItemManager.CacheGate()

        #expect(await gate.begin(), "The first pass must be admitted")
        #expect(await gate.begin() == false, "A concurrent pass must be rejected")
        #expect(await gate.begin() == false, "Further concurrent passes must still be rejected")
        #expect(await gate.end(), "A rerun must be requested after concurrent rejections")

        #expect(await gate.begin(), "The follow-up pass must be admitted")
        #expect(await gate.end() == false, "A quiet pass must not report a rerun")
    }
}

@Suite("Partial AX cache merge")
@MainActor
struct PartialAXCacheMergeTests {
    private func item(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        windowID: CGWindowID,
        ownerPID: pid_t
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, windowID: windowID),
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: false
        )
    }

    @Test("A partial AX snapshot adds fresh items without dropping live cached ones")
    func mergesFreshAndCachedItems() {
        let control = item(namespace: .thaw, title: "Visible", windowID: 1, ownerPID: 10)
        let hidden = item(namespace: .string("com.example.hidden"), title: "Hidden", windowID: 2, ownerPID: 20)
        let fresh = item(namespace: .string("com.example.fresh"), title: "Fresh", windowID: 3, ownerPID: 30)
        let quit = item(namespace: .string("com.example.quit"), title: "Quit", windowID: 4, ownerPID: 40)

        let merged = MenuBarItemManager.mergingLiveCachedItems(
            snapshotItems: [fresh],
            previousCachedItems: [control, hidden, quit],
            processIDs: [10, 20, 30],
            bundleIdentifiers: ["com.example.hidden", "com.example.fresh"]
        )

        #expect(merged.map(\.uniqueIdentifier) == [fresh, control, hidden].map(\.uniqueIdentifier))
    }

    @Test("A cached identity with a churned window ID does not duplicate a fresh item")
    func deduplicatesPersistentIdentities() {
        let cached = item(namespace: .string("com.example.app"), title: "Menu", windowID: 2, ownerPID: 30)
        let fresh = item(namespace: .string("com.example.app"), title: "Menu", windowID: 99, ownerPID: 30)

        let merged = MenuBarItemManager.mergingLiveCachedItems(
            snapshotItems: [fresh],
            previousCachedItems: [cached],
            processIDs: [30],
            bundleIdentifiers: ["com.example.app"]
        )

        #expect(merged == [fresh])
    }
}
