//
//  GhostControlItemWindowTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("GhostControlItemWindow")
struct GhostControlItemWindowTests {
    private let hiddenTitle = "Thaw.ControlItem.Hidden"
    private let alwaysHiddenTitle = "Thaw.ControlItem.AlwaysHidden"
    private let visibleTitle = "Thaw.ControlItem.Visible"

    private func item(tag: MenuBarItemTag, windowID: CGWindowID, title: String) -> MenuBarItem {
        MenuBarItem.fixture(tag: tag, windowID: windowID, title: title)
    }

    @Test("ControlItemPair prefers authoritative window IDs")
    func controlItemPairPrefersAuthoritativeWindowIDs() {
        var items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: hiddenTitle, instanceIndex: 1),
                windowID: 21542,
                title: hiddenTitle
            ),
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: alwaysHiddenTitle, instanceIndex: 1),
                windowID: 21543,
                title: alwaysHiddenTitle
            ),
        ]

        let pair = MenuBarItemManager.ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: 21542,
            alwaysHiddenControlItemWindowID: 21543
        )

        #expect(pair?.hidden.windowID == 21542)
        #expect(pair?.alwaysHidden?.windowID == 21543)
        #expect(items.map(\.windowID) == [364, 366])
    }

    @Test("ControlItemPair falls back to tag lookup without window IDs")
    func controlItemPairFallsBackToTagLookupWithoutWindowIDs() {
        var items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
        ]

        let pair = MenuBarItemManager.ControlItemPair(items: &items)

        #expect(pair?.hidden.windowID == 364)
        #expect(pair?.alwaysHidden?.windowID == 366)
        #expect(items.isEmpty)
    }

    @Test("ControlItemPair does not adopt a foreign always-hidden window")
    func controlItemPairDoesNotAdoptForeignAlwaysHiddenWindow() {
        var items = [
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: hiddenTitle, instanceIndex: 1),
                windowID: 21542,
                title: hiddenTitle
            ),
        ]

        let pair = MenuBarItemManager.ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: 21542,
            alwaysHiddenControlItemWindowID: 21543
        )

        #expect(pair?.hidden.windowID == 21542)
        #expect(pair?.alwaysHidden == nil)
    }

    @Test("Ghost detection drops only the foreign control window")
    func ghostDetectionDropsOnlyForeignControlWindow() {
        let items = [
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: hiddenTitle, instanceIndex: 1),
                windowID: 21542,
                title: hiddenTitle
            ),
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .appItem(bundleID: "com.apple.controlcenter", title: "Battery"), windowID: 850, title: "Battery"),
        ]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [hiddenTitle: 21542]
        )

        #expect(ghosts == [364])
    }

    @Test("Ghost detection requires the authoritative window")
    func ghostDetectionRequiresTheAuthoritativeWindow() {
        let items = [item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle)]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [hiddenTitle: 21542]
        )

        #expect(ghosts.isEmpty)
    }

    @Test("Authoritative current-process IDs win even when older numerically")
    func authoritativeDividerGenerationSurvivesReversedIDs() {
        let items = [
            item(tag: .hiddenControlItem, windowID: 42, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 43, title: alwaysHiddenTitle),
            item(tag: .visibleControlItem, windowID: 39, title: visibleTitle),
            item(tag: .hiddenControlItem, windowID: 900, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 901, title: alwaysHiddenTitle),
            item(tag: .visibleControlItem, windowID: 902, title: visibleTitle),
        ]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [
                hiddenTitle: 42,
                alwaysHiddenTitle: 43,
                visibleTitle: 39,
            ]
        )
        #expect(ghosts == [900, 901, 902])
    }

    @Test("A synthetic AppKit window number leaves duplicate dividers ambiguous")
    func syntheticWindowNumberDoesNotSelectADuplicateDivider() {
        let syntheticWindowNumber = Int(CGWindowID.max) + 1
        #expect(MenuBarItemManager.authoritativeControlItemWindowID(
            windowNumber: syntheticWindowNumber
        ) == nil)
        #expect(MenuBarItemManager.authoritativeControlItemWindowID(windowNumber: 42) == 42)

        let items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(
                tag: .appItem(
                    bundleID: "com.stonerl.Thaw",
                    title: hiddenTitle,
                    instanceIndex: 1
                ),
                windowID: 21542,
                title: hiddenTitle
            ),
        ]
        #expect(MenuBarItemManager.ControlItemPair.ambiguousControlItemTitles(
            in: items
        ) == [hiddenTitle])
    }

    // MARK: - Orphans under our own namespace (#1032)

    /// The window Control Center kept serving after the Thaw process behind
    /// it exited: our namespace, our bundle identifier as its title, and a
    /// window number that is none of ours.
    private var orphan: MenuBarItem {
        item(
            tag: .appItem(bundleID: "com.stonerl.Thaw", title: "com.stonerl.Thaw"),
            windowID: 639,
            title: "com.stonerl.Thaw"
        )
    }

    @Test("An orphaned window under our namespace is dropped")
    func orphanDetectionDropsControlCenterHeldWindow() {
        let items = [
            item(tag: .hiddenControlItem, windowID: 16233, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 16236, title: alwaysHiddenTitle),
            orphan,
            item(tag: .appItem(bundleID: "com.apple.controlcenter", title: "Battery"), windowID: 16, title: "Battery"),
        ]

        let orphans = MenuBarItemManager.orphanedOwnNamespaceWindowIDs(
            in: items,
            ownWindowIDs: [16233, 16236]
        )

        #expect(orphans == [639])
    }

    /// Without one of our own windows in the reading there is no baseline,
    /// so the filter declines to call anything an orphan.
    @Test("Orphan detection requires one of our own windows")
    func orphanDetectionRequiresOneOfOurWindows() {
        let orphans = MenuBarItemManager.orphanedOwnNamespaceWindowIDs(
            in: [orphan],
            ownWindowIDs: [16233]
        )

        #expect(orphans.isEmpty)
    }

    /// The orphan's title is indistinguishable from one of our control items
    /// caught in a bar-wide `kCGWindowName` degradation, which is why
    /// ownership is decided by window number. A degraded control item of
    /// ours is kept, so it still reaches the degradation check.
    @Test("A control item of ours with a degraded title is kept")
    func orphanDetectionKeepsADegradedControlItem() {
        let degraded = item(
            tag: .appItem(bundleID: "com.stonerl.Thaw", title: "com.stonerl.Thaw"),
            windowID: 16233,
            title: "com.stonerl.Thaw"
        )
        let items = [
            degraded,
            item(tag: .alwaysHiddenControlItem, windowID: 16236, title: alwaysHiddenTitle),
        ]

        let orphans = MenuBarItemManager.orphanedOwnNamespaceWindowIDs(
            in: items,
            ownWindowIDs: [16233, 16236]
        )

        #expect(orphans.isEmpty)
    }

    /// A spacer identified by title is ours even when its window number has
    /// not been enumerated as one of ours; the manager answers for the
    /// window-number case the tag cannot cover yet.
    @Test("A user spacer is not an orphan")
    func orphanDetectionKeepsUserSpacers() {
        let spacerTitle = MenuBarSpacerManager.autosavePrefix + UUID().uuidString
        let items = [
            item(tag: .hiddenControlItem, windowID: 16233, title: hiddenTitle),
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: spacerTitle),
                windowID: 17001,
                title: spacerTitle
            ),
        ]

        let orphans = MenuBarItemManager.orphanedOwnNamespaceWindowIDs(
            in: items,
            ownWindowIDs: [16233]
        )

        #expect(orphans.isEmpty)
    }

    /// The reason the orphan had to go. Left in the reading it is a
    /// self-titled item under our own namespace, which
    /// `liveIdentitiesAreDegraded` reads as the whole bar having lost its
    /// names — so every reading is discarded and the cache freezes for as
    /// long as the orphan lasts.
    @Test("Dropping the orphan clears the false degradation signal")
    func droppingTheOrphanClearsTheDegradationSignal() {
        let items = [
            item(tag: .hiddenControlItem, windowID: 16233, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 16236, title: alwaysHiddenTitle),
            orphan,
            item(tag: .appItem(bundleID: "com.apple.controlcenter", title: "Battery"), windowID: 16, title: "Battery"),
        ]
        let identities = { (items: [MenuBarItem]) in
            items.map { ($0.tag.namespace.description, $0.tag.title) }
        }

        #expect(LayoutSolver.liveIdentitiesAreDegraded(identities(items)))

        let orphans = MenuBarItemManager.orphanedOwnNamespaceWindowIDs(
            in: items,
            ownWindowIDs: [16233, 16236]
        )
        let kept = items.filter { !orphans.contains($0.windowID) }

        #expect(!LayoutSolver.liveIdentitiesAreDegraded(identities(kept)))

    }
}
