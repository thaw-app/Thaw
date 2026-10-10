//
//  CaptureDemandNarrowingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins which items a capture pass still has to screenshot once the user has
/// asked for app icons instead of live previews.
///
/// Without narrowing, the capture loop keeps reading the bar to fill a cache
/// nothing consults. Narrowing wrongly is worse: an item skipped here that
/// some surface then draws from a capture falls back to a blank tile.
@Suite("Capture demand narrowing")
struct CaptureDemandNarrowingTests {
    private typealias Demand = MenuBarItemImageCache.CaptureDemand

    private static func item(
        _ namespace: MenuBarItemTag.Namespace,
        _ title: String
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static let thirdParty = item(.string("com.example.app"), "Example")
    private static let systemModule = item(.controlCenter, "Wi-Fi")

    private static func demand(
        usesAppIcons: Bool,
        hasUnfilteredConsumer: Bool = false,
        alertRevealIdentifiers: Set<String> = []
    ) -> Demand {
        Demand(
            usesAppIcons: usesAppIcons,
            hasUnfilteredConsumer: hasUnfilteredConsumer,
            alertRevealIdentifiers: alertRevealIdentifiers
        )
    }

    @Test("Live previews capture everything")
    func livePreviewsCaptureEverything() {
        let items = [Self.thirdParty, Self.systemModule]
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            items,
            demand: Self.demand(usesAppIcons: false)
        )
        #expect(narrowed.count == 2)
    }

    @Test("App-icon mode keeps Apple modules and drops the rest")
    func appIconModeKeepsSystemPreviews() {
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            [Self.thirdParty, Self.systemModule],
            demand: Self.demand(usesAppIcons: true)
        )
        #expect(narrowed.map(\.tag) == [Self.systemModule.tag])
    }

    @Test("An item with no resolvable app icon keeps its capture")
    func unresolvedAppIconKeepsCapture() {
        let ownerless = MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .string("com.example.agent"),
                title: "Agent",
                instanceIndex: 0
            ),
            windowID: 3,
            ownerPID: 100,
            sourcePID: nil,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: "Agent",
            isOnScreen: true
        )
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            [Self.thirdParty, ownerless],
            demand: Self.demand(usesAppIcons: true)
        )
        #expect(narrowed.map(\.tag) == [ownerless.tag])
    }

    @Test("An item armed for alert reveal is captured in app-icon mode")
    func alertRevealSurvivesAppIconMode() {
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            [Self.thirdParty],
            demand: Self.demand(
                usesAppIcons: true,
                alertRevealIdentifiers: [Self.thirdParty.tag.tagIdentifier]
            )
        )
        #expect(narrowed.map(\.tag) == [Self.thirdParty.tag])
    }

    @Test("Search and the hotkey list read the cache directly, so nothing is dropped")
    func unfilteredConsumerDefeatsNarrowing() {
        let items = [Self.thirdParty, Self.systemModule]
        let narrowed = MenuBarItemImageCache.itemsNeedingCapture(
            items,
            demand: Self.demand(usesAppIcons: true, hasUnfilteredConsumer: true)
        )
        #expect(narrowed.count == 2)
    }
}
