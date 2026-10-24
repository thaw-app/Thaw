//
//  MenuBarBoundsInclusionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Tests for the rule that decides which items occupy menu bar space during
/// click, hover, and scroll hit-testing.
///
/// A revealed hidden item is drawn on the bar, so it must count as occupied
/// space; a concealed one must not swallow clicks aimed at the empty bar
/// behind it.
@Suite("Menu bar bounds inclusion")
struct MenuBarBoundsInclusionTests {
    private static let screens = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 2560, y: 290, width: 1710, height: 1107),
    ]

    @Test("A lower display's bar counts as occupied, but concealed and off-bar frames do not")
    func lowerDisplayInclusion() {
        let seated = item(bundle: "com.example.app", title: "Alpha", x: 3600, y: 295)
        let parked = item(bundle: "com.example.app", title: "Alpha", x: 3600, y: 1068)
        #expect(HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(seated, section: .visible, screens: Self.screens))
        #expect(HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(seated, section: nil, screens: Self.screens))
        #expect(HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(seated, section: .hidden, screens: Self.screens))
        let concealedIncluded = HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
            seated, section: .hidden, effectivelyConcealed: [canonicalIdentifier(seated)], screens: Self.screens
        )
        #expect(!concealedIncluded)
        #expect(!HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(parked, section: .visible, screens: Self.screens))
    }

    private func item(
        bundle: String,
        title: String,
        x: CGFloat = 600,
        y: CGFloat = 0,
        width: CGFloat = 24
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private func canonicalIdentifier(_ item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }

    @Test("A visible-authored item is included")
    func visibleItemIncluded() {
        let item = item(bundle: "com.example.app", title: "Alpha")
        #expect(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(item, section: .visible, screens: Self.screens)
        )
    }

    @Test("A concealed hidden item is excluded")
    func concealedHiddenItemExcluded() {
        let item = item(bundle: "com.example.app", title: "Alpha")
        let included = HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
            item,
            section: .hidden,
            effectivelyConcealed: [canonicalIdentifier(item)],
            screens: Self.screens
        )
        #expect(!included)
    }

    @Test("A revealed hidden item is included")
    func revealedHiddenItemIncluded() {
        let item = item(bundle: "com.example.app", title: "Alpha")
        #expect(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
                item,
                section: .hidden,
                effectivelyConcealed: [],
                screens: Self.screens
            )
        )
    }

    @Test("A revealed always-hidden item is included")
    func revealedAlwaysHiddenItemIncluded() {
        let item = item(bundle: "com.example.app", title: "Alpha")
        #expect(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
                item,
                section: .alwaysHidden,
                effectivelyConcealed: [],
                screens: Self.screens
            )
        )
    }

    @Test("A concealed non-concealable system item is still included")
    func systemItemIncluded() {
        let item = item(bundle: "com.apple.systemuiserver", title: "Siri")
        #expect(
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
                item,
                section: .hidden,
                effectivelyConcealed: [canonicalIdentifier(item)],
                screens: Self.screens
            )
        )
    }

    @Test("A phantom off-band frame is excluded even when revealed")
    func phantomFrameExcluded() {
        let parked = item(bundle: "com.example.app", title: "Alpha", y: 1400)
        let included = HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
            parked,
            section: .hidden,
            effectivelyConcealed: [],
            screens: Self.screens
        )
        #expect(!included)
    }
}
