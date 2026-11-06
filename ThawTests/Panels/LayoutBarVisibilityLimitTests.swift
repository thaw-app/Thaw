//
//  LayoutBarVisibilityLimitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A Layout tile explains when macOS keeps its icon out of its section")
struct LayoutBarVisibilityLimitTests {
    private func limit(
        section: MenuBarSectionName,
        registered: Bool? = true,
        bundleID: String = "com.example.app",
        native: Bool = false,
        hidesOthers: Bool = true,
        untracked: Set<String> = [],
        pinned: Bool = false
    ) -> LayoutBarVisibilityLimit? {
        LayoutBarVisibilityLimit.limit(
            section: section,
            ownerHasRegisteredBundle: registered,
            ownerBundleID: bundleID,
            nativeAppHidingActive: native,
            hidesOtherIcons: hidesOthers,
            untrackedBundleIDs: untracked,
            isPinnedControlCenterModule: pinned
        )
    }

    @Test("A pinned Control Center item cannot show in Visible while others are hidden")
    func pinnedModuleCannotShow() {
        #expect(limit(section: .visible, pinned: true) == .pinnedModuleCannotShow)
        #expect(limit(section: .visible, hidesOthers: false, pinned: true) == nil)
        #expect(limit(section: .visible, native: true, pinned: true) == nil)
        #expect(limit(section: .hidden, pinned: true) == nil)
    }

    @Test("An icon without a registered bundle cannot show in Visible while others are hidden")
    func unregisteredOwnerCannotShow() {
        #expect(limit(section: .visible, registered: false) == .cannotShow)
        #expect(limit(section: .visible, registered: false, hidesOthers: false) == nil)
        #expect(limit(section: .visible, registered: false, native: true) == nil)
        #expect(limit(section: .visible, registered: nil) == nil)
        #expect(limit(section: .visible, registered: true) == nil)
    }

    @Test("An untracked app cannot hide under native app hiding", arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func untrackedAppCannotHide(section: MenuBarSectionName) {
        let untracked: Set = ["com.example.app"]
        #expect(limit(section: section, native: true, untracked: untracked) == .cannotHide)
        #expect(limit(section: section, native: false, untracked: untracked) == nil)
        #expect(limit(section: section, native: true, untracked: ["com.example.other"]) == nil)
        #expect(limit(section: .visible, native: true, untracked: untracked) == nil)
    }
}
