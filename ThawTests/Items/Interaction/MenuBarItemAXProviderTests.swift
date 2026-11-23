//
//  MenuBarItemAXProviderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw
import ThawAXCore

/// Subprocess walks return raw observations; app-side identity and assembly must match the in-process path.
@Suite("AX subprocess observation mapping")
struct AXSubprocessMappingTests {
    private func observation(
        bundleID: String?,
        title: String? = nil,
        identifier: String? = nil,
        description: String? = nil,
        x: CGFloat,
        isOverflow: Bool = false
    ) -> AXItemObservation {
        AXItemObservation(
            bundleID: bundleID,
            processName: nil,
            ownerPID: 100,
            identifier: identifier,
            accessibilityDescription: description,
            title: title,
            help: nil,
            frame: CGRect(x: x, y: 0, width: 24, height: 24),
            isOverflowControl: isOverflow
        )
    }

    @Test("overflow control is not an item")
    func overflowDropped() {
        let items = MenuBarItemAXProvider.items(fromSubprocess: [
            observation(bundleID: "com.apple.MenuBarAgent", title: "Chevron", x: 0, isOverflow: true),
            observation(bundleID: "com.example.app", title: "Widget", x: 40),
        ])
        #expect(items.count == 1)
        #expect(items[0].tag.title == "Widget")
    }

    @Test("items added besides the helper's are assembled with them, and see what the helper read")
    func addedItemsAreAssembled() {
        var seen = [MenuBarItemAXProvider.RawItem]()
        let drawn = MenuBarItemAXProvider.RawItem(
            namespace: .string("com.example.drawn"), identityTitle: "Item-0", displayTitle: "Item-0",
            bounds: CGRect(x: 80, y: 0, width: 24, height: 24), ownerPID: 200
        )
        let items = MenuBarItemAXProvider.items(
            fromSubprocess: [observation(bundleID: "com.example.app", title: "Widget", x: 40)],
            adding: { raw in
                seen = raw
                return [drawn]
            }
        )
        #expect(seen.map(\.ownerPID) == [100])
        #expect(items.map(\.tag.namespace) == [.string("com.example.app"), .string("com.example.drawn")])
        #expect(items.last?.ownerPID == 200)
    }

    @Test("a titled app item keeps its namespace, title, and frame")
    func titledItem() {
        let items = MenuBarItemAXProvider.items(fromSubprocess: [
            observation(bundleID: "com.example.app", identifier: "Widget", x: 10),
        ])
        #expect(items.count == 1)
        #expect(items[0].tag.namespace == .string("com.example.app"))
        #expect(items[0].tag.title == "Widget")
        #expect(items[0].bounds == CGRect(x: 10, y: 0, width: 24, height: 24))
        #expect(items[0].ownerPID == 100)
    }

    @Test("nameless siblings get positional fallback titles and distinct ids")
    func fallbackTitles() {
        let items = MenuBarItemAXProvider.items(fromSubprocess: [
            observation(bundleID: "com.example.app", x: 10),
            observation(bundleID: "com.example.app", x: 40),
        ])
        #expect(items.count == 2)
        #expect(items[0].tag.title == "Item-0")
        #expect(items[1].tag.title == "Item-1")
        #expect(items[0].windowID != items[1].windowID)
    }
}

/// Pins the height ceiling the AX walk holds extras-bar children to.
@Suite("Menu bar item height ceiling")
struct MenuBarItemHeightCeilingTests {
    @Test("A bar at or under 40 pt keeps the 40 pt ceiling", arguments: [nil, 24.0, 33.0, 39.0] as [CGFloat?])
    func standardBarsKeepTheFloor(menuBarHeight: CGFloat?) {
        #expect(MenuBarItemAXProvider.maxItemHeight(menuBarHeight: menuBarHeight) == 40)
    }

    /// 64 px of notched bar on a 3456 px panel scaled to 2177 pt.
    @Test("A notched bar taller than 40 pt admits its full-height system items")
    func tallNotchedBarAdmitsSystemItems() {
        let barHeight: CGFloat = 64 / (3456 / 2177)
        let ceiling = MenuBarItemAXProvider.maxItemHeight(menuBarHeight: barHeight)
        #expect(barHeight > 40)
        #expect(barHeight <= ceiling)
    }

    @Test("Popovers and panels stay above the ceiling")
    func popoversStayRejected() {
        let ceiling = MenuBarItemAXProvider.maxItemHeight(menuBarHeight: 42)
        #expect(ceiling < 60)
    }
}

/// A read that misses an item's identifier keeps the identity the item had, per app.
@Suite("Retitled item identities")
struct RetitledItemIdentitiesTests {
    private typealias RawItem = MenuBarItemAXProvider.RawItem

    private func raw(_ identity: String, shows display: String, owner: pid_t, x: CGFloat) -> RawItem {
        RawItem(
            namespace: .string("com.raycast.macos"),
            identityTitle: identity,
            displayTitle: display,
            bounds: CGRect(x: x, y: 0, width: 80, height: 24),
            ownerPID: owner
        )
    }

    @Test("Raycast's calendar item keeps calendar-events when a read sees only its countdown")
    func keepsTheIdentifierAcrossAFallbackRead() {
        var memory = RetitleIdentityMemory()
        let stable = [
            raw("calendar-events", shows: "Standup • in 52m", owner: 42, x: 100),
            raw("clipboard-history", shows: "Clipboard", owner: 42, x: 200),
            raw("Other", shows: "Other", owner: 43, x: 300),
        ]
        #expect(RetitledItemIdentities.resolve(stable, with: &memory).map(\.identityTitle)
            == ["calendar-events", "clipboard-history", "Other"])

        let fallback = [
            raw("Standup • in 51m", shows: "Standup • in 51m", owner: 42, x: 100),
            raw("clipboard-history", shows: "Clipboard", owner: 42, x: 200),
            raw("Renamed", shows: "Renamed", owner: 43, x: 300),
        ]
        let resolved = RetitledItemIdentities.resolve(fallback, with: &memory)
        #expect(resolved.map(\.identityTitle) == ["calendar-events", "clipboard-history", "Renamed"])
        #expect(resolved[0].displayTitle == "Standup • in 51m")
        #expect(resolved[0].bounds == fallback[0].bounds)
        #expect(RetitledItemIdentities.resolve([]).isEmpty)
    }
}

/// The provider's identity hook hands placeholder items their saved identity before any consumer sees them.
struct SavedIdentityAdoptionTests {
    private static let oneDrive = "com.microsoft.OneDrive"

    private static func item(title: String, x: CGFloat) -> MenuBarItem {
        ItemsFixture.item(title, bundle: oneDrive, x: x, y: 3, width: 26, windowID: CGWindowID(x), ownerPID: 1130, sourcePID: 1130)
    }

    @Test("A bare OneDrive item leaves the walk under its saved account identity")
    func placeholderLeavesUnderSavedIdentity() {
        let bare = Self.item(title: "OneDrive", x: 2188)
        let items = MenuBarItemAXProvider.adoptingSavedIdentities([bare]) {
            ["hidden": ["\(Self.oneDrive):Daniel Scherber"]]
        }
        #expect(items.map(\.uniqueIdentifier) == ["\(Self.oneDrive):Daniel Scherber"])
        #expect(items[0].windowID == bare.windowID)
    }

    @Test("The saved order is not read when no item answered under a placeholder name")
    func savedOrderIsReadOnlyForPlaceholders() {
        let named = Self.item(title: "OneDrive — Personal", x: 2188)
        var reads = 0
        let items = MenuBarItemAXProvider.adoptingSavedIdentities([named]) {
            reads += 1
            return [:]
        }
        #expect(items == [named])
        #expect(reads == 0)
    }

    @Test("A placeholder with nothing saved for it keeps its name")
    func placeholderWithoutSavedTitleIsUnchanged() {
        let bare = Self.item(title: "OneDrive", x: 2188)
        let items = MenuBarItemAXProvider.adoptingSavedIdentities([bare]) { [:] }
        #expect(items == [bare])
    }
}
