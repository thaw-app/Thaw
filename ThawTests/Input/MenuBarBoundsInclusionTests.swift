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
    private func item(
        bundle: String,
        title: String,
        y: CGFloat = 0,
        width: CGFloat = 24
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: 600, y: y, width: width, height: 24),
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
            HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(item, section: .visible)
        )
    }

    @Test("A concealed hidden item is excluded")
    func concealedHiddenItemExcluded() {
        let item = item(bundle: "com.example.app", title: "Alpha")
        let included = HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
            item,
            section: .hidden,
            effectivelyConcealed: [canonicalIdentifier(item)]
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
                effectivelyConcealed: []
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
                effectivelyConcealed: []
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
                effectivelyConcealed: [canonicalIdentifier(item)]
            )
        )
    }

    @Test("A phantom off-band frame is excluded even when revealed")
    func phantomFrameExcluded() {
        let parked = item(bundle: "com.example.app", title: "Alpha", y: 1400)
        let included = HIDEventManager.shouldIncludeItemInMenuBarBoundsLookup(
            parked,
            section: .hidden,
            effectivelyConcealed: []
        )
        #expect(!included)
    }
}
