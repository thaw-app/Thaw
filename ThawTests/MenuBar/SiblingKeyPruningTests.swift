//
//  SiblingKeyPruningTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

// Parked with the pruner it covers; see MenuBarItemManager+SiblingKeyPruning.
#if false

    @MainActor
    struct SiblingKeyPruningTests {
        /// Measured f.lux bundle and display-name spellings share one weight among unrelated neighbors.
        private var fluxPositions: [String: Int] {
            [
                "status:Flux::Item-0": -5586,
                "status:org.herf.Flux::Item-0": -5586,
                "status:cc.ffitch.shottr::Item-0": -3221,
                "status:com.raycast.macos::Item-0": -2321,
            ]
        }

        private let fluxPrefixes = ["status:org.herf.Flux::", "status:Flux::"]

        @Test("Tied sibling spelling is detected")
        func tiedSiblingIsDetected() {
            let stale = MenuBarItemManager.staleSiblingSpellings(
                resolvedKey: "status:org.herf.Flux::Item-0",
                ownerPrefixes: fluxPrefixes,
                positions: fluxPositions
            )
            #expect(stale == ["status:Flux::Item-0"])
        }

        @Test("The resolved key is never its own stale sibling")
        func resolvedKeyIsExcluded() {
            let stale = MenuBarItemManager.staleSiblingSpellings(
                resolvedKey: "status:org.herf.Flux::Item-0",
                ownerPrefixes: fluxPrefixes,
                positions: ["status:org.herf.Flux::Item-0": -5586]
            )
            #expect(stale.isEmpty)
        }

        /// Different weights mean distinct slots, not mirrors; pruning would delete a meaningful seat.
        @Test("Untied sibling is left alone")
        func untiedSiblingIsLeftAlone() {
            let stale = MenuBarItemManager.staleSiblingSpellings(
                resolvedKey: "status:org.herf.Flux::Item-0",
                ownerPrefixes: fluxPrefixes,
                positions: [
                    "status:Flux::Item-0": -3131,
                    "status:org.herf.Flux::Item-0": -5586,
                ]
            )
            #expect(stale.isEmpty)
        }

        /// Many apps share ::Item-0; prune only within the owner's prefix family.
        @Test("Other apps' equal-weight keys are outside the family")
        func otherAppsAreOutsideTheFamily() {
            let stale = MenuBarItemManager.staleSiblingSpellings(
                resolvedKey: "status:org.herf.Flux::Item-0",
                ownerPrefixes: fluxPrefixes,
                positions: [
                    "status:org.herf.Flux::Item-0": -5586,
                    "status:cc.ffitch.shottr::Item-0": -5586,
                ]
            )
            #expect(stale.isEmpty)
        }

        @Test("Missing resolved weight detects nothing")
        func missingResolvedWeightDetectsNothing() {
            let stale = MenuBarItemManager.staleSiblingSpellings(
                resolvedKey: "status:org.herf.Flux::Item-0",
                ownerPrefixes: fluxPrefixes,
                positions: ["status:Flux::Item-0": -5586]
            )
            #expect(stale.isEmpty)
        }

        /// Frames beyond every display are retracted, just like the -1 sentinel.
        @Test("Off-display frame reads as retracted")
        func offDisplayFrameIsRetracted() {
            let parked = MenuBarItem(
                tag: .init(namespace: .string("org.herf.Flux"), title: "Item-0"),
                windowID: 4,
                ownerPID: 1,
                sourcePID: 1,
                bounds: CGRect(x: 2330, y: 3, width: 33, height: 24),
                title: "Item-0",
                isOnScreen: false
            )
            #expect(!MenuBarItemManager.frameIntersectsAnyDisplay(
                parked.bounds,
                displayBounds: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
            ))
        }

        @Test("On-display frame intersects")
        func onDisplayFrameIntersects() {
            #expect(MenuBarItemManager.frameIntersectsAnyDisplay(
                CGRect(x: 1046, y: 3, width: 34, height: 24),
                displayBounds: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
            ))
        }

        /// Failed display enumeration must answer on-display to avoid misclassifying healthy items.
        @Test("Unknown topology never strands")
        func unknownTopologyNeverStrands() {
            #expect(MenuBarItemManager.frameIntersectsAnyDisplay(
                CGRect(x: 5000, y: 3, width: 33, height: 24),
                displayBounds: []
            ))
        }

        /// The live, real-sized sentinel has no host-assigned seat.
        @Test("Sentinel frame reads as retracted")
        func sentinelFrameIsRetracted() {
            let flux = MenuBarItem(
                tag: .init(namespace: .string("org.herf.Flux"), title: "Item-0"),
                windowID: 1,
                ownerPID: 1,
                sourcePID: 1,
                bounds: CGRect(x: -1, y: 1068, width: 33, height: 24),
                title: "Item-0",
                isOnScreen: false
            )
            #expect(MenuBarItemManager.isRetractedItem(flux))
        }

        @Test("Seated item is not retracted")
        func seatedItemIsNotRetracted() {
            // Use live topology because fixed coordinates only fit one display arrangement.
            let display = MenuBarItemManager.activeDisplayBounds().first
                ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let seated = MenuBarItem(
                tag: .init(namespace: .string("com.raycast.macos"), title: "Item-0"),
                windowID: 2,
                ownerPID: 1,
                sourcePID: 1,
                bounds: CGRect(x: display.minX + 100, y: display.minY + 3, width: 34, height: 24),
                title: "Item-0",
                isOnScreen: true
            )
            #expect(!MenuBarItemManager.isRetractedItem(seated))
        }

        /// Collapsed controls intentionally have negative x; the ladder and republish own them, not this pruner.
        @Test("Control items are never pruned")
        func controlItemsAreExcluded() {
            let divider = MenuBarItem(
                tag: .hiddenControlItem,
                windowID: 3,
                ownerPID: 1,
                sourcePID: 1,
                bounds: CGRect(x: -1, y: 1068, width: 1, height: 24),
                title: "Thaw.ControlItem.Hidden",
                isOnScreen: false
            )
            #expect(!MenuBarItemManager.isRetractedItem(divider))
        }
    }

#endif
