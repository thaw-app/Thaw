//
//  UnresolvedPlaceholderAliasTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// When the catalog already knows the app that owns an unresolved Control
/// Center-hosted slot, the placeholder is re-tagged under that app's bundle ID
/// so the Layout editor drag and `move(...)` can proceed (#905).
///
/// Only the pure halves are tested here; the `LayoutBarItemView` flow sits
/// behind an `AXIdentityCatalog` snapshot tested separately.
@Suite("Unresolved placeholder alias")
struct UnresolvedPlaceholderAliasTests {
    private static let hostBundleIDs: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
    ]
    private static let thawBundleID = "com.stonerl.Thaw"
    private static let littleSnitchBundleID = "at.obdev.littlesnitch.agent"

    private static let placeholder = MenuBarItem.fixture(
        tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0"),
        windowID: 1234,
        sourcePID: nil
    )

    // MARK: appBundleID

    @Test("appBundleID returns the AXIdentifier when it is a non-host bundle ID")
    func appBundleIDPrefersAXIdentifier() {
        let identity = AXIdentityCatalog.AXItemIdentity(
            identifier: Self.littleSnitchBundleID,
            title: "Item-0",
            help: nil,
            frame: CGRect(x: 0, y: 0, width: 24, height: 22)
        )
        let bundleID = UnresolvedPlaceholderAlias.appBundleID(
            from: identity,
            excluding: Self.hostBundleIDs,
            thawBundleID: Self.thawBundleID
        )
        #expect(bundleID == Self.littleSnitchBundleID)
    }

    @Test(
        "appBundleID rejects host bundle IDs at every attribute position",
        arguments: ["com.apple.controlcenter", "com.apple.systemuiserver"]
    )
    func appBundleIDRejectsHosts(hostBundleID: String) {
        let identity = AXIdentityCatalog.AXItemIdentity(
            identifier: hostBundleID,
            title: hostBundleID,
            help: hostBundleID,
            frame: .zero
        )
        #expect(UnresolvedPlaceholderAlias.appBundleID(
            from: identity,
            excluding: Self.hostBundleIDs,
            thawBundleID: Self.thawBundleID
        ) == nil)
    }

    @Test("appBundleID rejects Thaw's own bundle identifier")
    func appBundleIDRejectsThaw() {
        let identity = AXIdentityCatalog.AXItemIdentity(
            identifier: Self.thawBundleID,
            title: nil,
            help: nil,
            frame: .zero
        )
        #expect(UnresolvedPlaceholderAlias.appBundleID(
            from: identity,
            excluding: Self.hostBundleIDs,
            thawBundleID: Self.thawBundleID
        ) == nil)
    }

    @Test("appBundleID falls back to AXTitle then AXHelp when the identifier is not bundle-shaped")
    func appBundleIDFallsBackToTitleThenHelp() {
        let bundleID = "net.matthewpalmer.Rocket"
        let titleOnly = AXIdentityCatalog.AXItemIdentity(
            identifier: nil,
            title: bundleID,
            help: nil,
            frame: .zero
        )
        let helpOnly = AXIdentityCatalog.AXItemIdentity(
            identifier: "Menu Bar Item",
            title: "",
            help: bundleID,
            frame: .zero
        )
        #expect(UnresolvedPlaceholderAlias.appBundleID(
            from: titleOnly,
            excluding: Self.hostBundleIDs,
            thawBundleID: Self.thawBundleID
        ) == bundleID)
        #expect(UnresolvedPlaceholderAlias.appBundleID(
            from: helpOnly,
            excluding: Self.hostBundleIDs,
            thawBundleID: Self.thawBundleID
        ) == bundleID)
    }

    @Test("appBundleID returns nil when no attribute is bundle-identifier-shaped")
    func appBundleIDNilForUnshapedIdentities() {
        let identity = AXIdentityCatalog.AXItemIdentity(
            identifier: "WiFi",
            title: "Item-0",
            help: "Open Wi-Fi settings",
            frame: .zero
        )
        #expect(UnresolvedPlaceholderAlias.appBundleID(
            from: identity,
            excluding: Self.hostBundleIDs,
            thawBundleID: Self.thawBundleID
        ) == nil)
    }

    @Test("appBundleID returns nil for a missing identity")
    func appBundleIDNilForMissingIdentity() {
        #expect(UnresolvedPlaceholderAlias.appBundleID(
            from: nil,
            excluding: Self.hostBundleIDs,
            thawBundleID: Self.thawBundleID
        ) == nil)
    }

    // MARK: aliasedItem

    @Test("aliasedItem is nil for a resolved item that is not the placeholder gate")
    func aliasedItemRejectsNonPlaceholder() {
        let resolved = MenuBarItem.fixture(
            tag: .appItem(bundleID: Self.littleSnitchBundleID, title: "Item-0"),
            windowID: 1234,
            sourcePID: 9001
        )
        #expect(UnresolvedPlaceholderAlias.aliasedItem(
            for: resolved,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        ) == nil)
    }

    @Test("aliasedItem is nil for a static prohibited system item")
    func aliasedItemRejectsProhibitedSystemItem() {
        let clock = MenuBarItem.fixture(tag: .clock, windowID: 1234, sourcePID: nil)
        #expect(UnresolvedPlaceholderAlias.aliasedItem(
            for: clock,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        ) == nil)
    }

    @Test("aliasedItem re-tags the placeholder under the app-owned namespace")
    func aliasedItemRetagsUnderAppNamespace() throws {
        let alias = try #require(UnresolvedPlaceholderAlias.aliasedItem(
            for: Self.placeholder,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        ))

        // Namespace becomes the app's bundle ID; title and instance index are kept so
        // the UID matches the saved key (at.obdev.littlesnitch.agent:Item-0).
        #expect(alias.tag.namespace == .string(Self.littleSnitchBundleID))
        #expect(alias.tag.title == Self.placeholder.tag.title)
        #expect(alias.tag.instanceIndex == Self.placeholder.tag.instanceIndex)

        // Tagging override only: synthetic drags still address the live slot's window.
        #expect(alias.windowID == Self.placeholder.windowID)
        #expect(alias.ownerPID == Self.placeholder.ownerPID)
        #expect(alias.bounds == Self.placeholder.bounds)
        #expect(alias.title == Self.placeholder.title)
        #expect(alias.isOnScreen == Self.placeholder.isOnScreen)

        // The host PID becomes sourcePID, clearing the provisional-identity save gate.
        #expect(alias.sourcePID == 9001)
    }

    @Test("aliasedItem is movable and persistable")
    func aliasedItemIsMovableAndPersistable() throws {
        let alias = try #require(UnresolvedPlaceholderAlias.aliasedItem(
            for: Self.placeholder,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        ))

        #expect(alias.immovabilityReason == nil)
        #expect(alias.isMovable)
        #expect(!alias.hasProvisionalIdentity)
        #expect(!alias.isTransientControlCenterItem)
    }

    @Test("aliasedItem's uniqueIdentifier matches the saved-layout app-owned key")
    func aliasedItemUniqueIdentifierMatchesSavedLayout() throws {
        let alias = try #require(UnresolvedPlaceholderAlias.aliasedItem(
            for: Self.placeholder,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        ))

        // The saved layout keys the app-owned form, so the alias must match it.
        #expect(alias.uniqueIdentifier == "\(Self.littleSnitchBundleID):Item-0")
    }

    @Test("aliasedItem preserves the instance index in its uniqueIdentifier")
    func aliasedItemPreservesInstanceIndex() throws {
        let thirdWindow = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0", windowID: 1234, instanceIndex: 2),
            windowID: 1234,
            sourcePID: nil
        )
        let alias = try #require(UnresolvedPlaceholderAlias.aliasedItem(
            for: thirdWindow,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        ))
        #expect(alias.uniqueIdentifier == "\(Self.littleSnitchBundleID):Item-0:2")
    }
}
