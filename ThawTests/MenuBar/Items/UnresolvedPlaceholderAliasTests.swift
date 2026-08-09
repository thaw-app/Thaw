//
//  UnresolvedPlaceholderAliasTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins the #905 identity-preference fallback: when the catalog already holds
/// an app-owned identity for a Control Center-hosted slot that the source-PID
/// cache has not resolved this cycle, the live placeholder is re-tagged under
/// the owning app's bundle ID namespace so the Layout editor drag and the
/// `move(...)` inner guard can both proceed.
///
/// Only the pure halves (`appBundleID(from:excluding:thawBundleID:)` and
/// `aliasedItem(for:appBundleID:hostPID:)`) are tested here; the AppKit-bound
/// snapshot-and-correlate flow in `LayoutBarItemView` lives behind an
/// `AXIdentityCatalog` snapshot that is unit-tested separately.
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

    @Test("appBundleID rejects host bundle IDs at every attribute position")
    func appBundleIDRejectsHosts(arguments: ["com.apple.controlcenter", "com.apple.systemuiserver"]) {
        let identity = AXIdentityCatalog.AXItemIdentity(
            identifier: arguments,
            title: arguments,
            help: arguments,
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
    func aliasedItemRetagsUnderAppNamespace() {
        let alias = UnresolvedPlaceholderAlias.aliasedItem(
            for: Self.placeholder,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        )
        #expect(alias != nil)
        let alias = try #require(alias)

        // The namespace becomes the app-owned bundle ID; the generic slot title
        // (Item-N) and the instance index are preserved so the alias's UID
        // matches the saved-layout key (#905: at.obdev.littlesnitch.agent:Item-0).
        #expect(alias.tag.namespace == .string(Self.littleSnitchBundleID))
        #expect(alias.tag.title == Self.placeholder.tag.title)
        #expect(alias.tag.instanceIndex == Self.placeholder.tag.instanceIndex)

        // The window identity is preserved (the alias is purely a tagging
        // override — synthetic drag events still address the live slot).
        #expect(alias.windowID == Self.placeholder.windowID)
        #expect(alias.ownerPID == Self.placeholder.ownerPID)
        #expect(alias.bounds == Self.placeholder.bounds)
        #expect(alias.title == Self.placeholder.title)
        #expect(alias.isOnScreen == Self.placeholder.isOnScreen)

        // The resolved host PID becomes the item's sourcePID, which clears the
        // provisional-identity gate the save path uses to drop placeholders.
        #expect(alias.sourcePID == 9001)
    }

    @Test("aliasedItem is movable and persistable")
    func aliasedItemIsMovableAndPersistable() {
        let alias = UnresolvedPlaceholderAlias.aliasedItem(
            for: Self.placeholder,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        )
        let alias = try #require(alias)

        #expect(alias.immovabilityReason == nil)
        #expect(alias.isMovable)
        #expect(!alias.hasProvisionalIdentity)
        #expect(!alias.isTransientControlCenterItem)
    }

    @Test("aliasedItem's uniqueIdentifier matches the saved-layout app-owned key")
    func aliasedItemUniqueIdentifierMatchesSavedLayout() {
        let alias = UnresolvedPlaceholderAlias.aliasedItem(
            for: Self.placeholder,
            appBundleID: Self.littleSnitchBundleID,
            hostPID: 9001
        )
        let alias = try #require(alias)

        // #905: savedSectionOrder/hidden[27] keyed the app-owned form
        // `at.obdev.littlesnitch.agent:Item-0`; the alias must produce the
        // same identifier so the saved-layout lookup succeeds.
        #expect(alias.uniqueIdentifier == "\(Self.littleSnitchBundleID):Item-0")
    }

    @Test("aliasedItem preserves the instance index in its uniqueIdentifier")
    func aliasedItemPreservesInstanceIndex() {
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
