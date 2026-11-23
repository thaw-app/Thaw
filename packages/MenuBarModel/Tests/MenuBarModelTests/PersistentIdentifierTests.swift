//
//  PersistentIdentifierTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

@Suite("Item identity accessors")
struct MenuBarItemIdentityAccessorsTests {
    @Test("An item's canonical identifier is its unique identifier, canonicalized", arguments: [
        MenuBarItemTag.Namespace.string("com.example.app"),
        // Rectangle's AppKit placeholder title is the one the canonical form rewrites.
        .string("com.knollsoft.Rectangle"),
    ])
    func canonicalIdentifier(namespace: MenuBarItemTag.Namespace) {
        let item = MenuBarItem.fixture(namespace: namespace, title: "_NS:8")
        #expect(item.canonicalIdentifier == MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier))
    }

    @Test("Only a string namespace names a bundle identifier")
    func namespaceBundleIdentifier() {
        #expect(MenuBarItemTag.Namespace.string("com.example.app").bundleIdentifier == "com.example.app")
        #expect(MenuBarItemTag.Namespace.null.bundleIdentifier == nil)
        #expect(MenuBarItemTag.Namespace.uuid(UUID()).bundleIdentifier == nil)
    }

    @Test("Apple's bundle identifiers are the ones under com.apple.")
    func appleBundleIdentifier() {
        #expect(SharedConstants.isAppleBundleIdentifier("com.apple.controlcenter"))
        #expect(!SharedConstants.isAppleBundleIdentifier("com.applesauce.app"))
        #expect(!SharedConstants.isAppleBundleIdentifier("com.example.app"))
    }

    @Test("The active menu bar display is the one the optional read names")
    func activeMenuBarDisplay() {
        #expect(Bridging.activeMenuBarDisplayID == Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID())
    }

    @Test("The deprecated ownership constants forward to ThawMenuBarIdentity")
    @available(*, deprecated)
    func legacyOwnershipSymbolsForward() {
        #expect(Constants.thawOwnedBundleIdentifiers == ThawMenuBarIdentity.ownedBundleIdentifiers)
        #expect(Constants.isThawOwnedBundleIdentifier(ThawMenuBarIdentity.bundleIdentifier))
    }
}

@Suite("Persistent identifier parts")
struct PersistentIdentifierPartsTests {
    @Test("The first colon separates the namespace; the title keeps the rest")
    func splitsAtFirstColon() throws {
        let parts = try #require(MenuBarItemTag.persistentIdentifierParts("com.example.app:Status:2"))
        #expect(parts.namespace == "com.example.app")
        #expect(parts.title == "Status:2")
    }

    @Test("An identifier without a colon has no parts")
    func noColon() {
        #expect(MenuBarItemTag.persistentIdentifierParts("com.example.app") == nil)
    }

    @Test("An empty title or namespace is kept as empty")
    func emptyParts() throws {
        let trailing = try #require(MenuBarItemTag.persistentIdentifierParts("com.example.app:"))
        #expect(trailing.namespace == "com.example.app" && trailing.title.isEmpty)
        let leading = try #require(MenuBarItemTag.persistentIdentifierParts(":Title"))
        #expect(leading.namespace.isEmpty && leading.title == "Title")
    }

    @Test("A trailing :<number> after a title is an instance suffix")
    func instanceSuffix() {
        #expect(MenuBarItemTag.hasInstanceSuffix("Status:2"))
        #expect(!MenuBarItemTag.hasInstanceSuffix("Status"))
        #expect(!MenuBarItemTag.hasInstanceSuffix(":2"))
        #expect(!MenuBarItemTag.hasInstanceSuffix("Status:two"))
    }
}

@Suite("Stale identifier aliases")
struct StaleAliasTests {
    private func pruned(_ titles: [String], bundleID: String) -> Set<String> {
        let identifiers = Set(titles.map { "\(bundleID):\($0)" })
        let kept = MenuBarItemTag.identifiersWithoutStaleAliases(identifiers, bundleID: bundleID)
        return Set(kept.map { String($0.dropFirst(bundleID.count + 1)) })
    }

    @Test("An AppKit placeholder name is dropped for any app")
    func appKitPlaceholderIsDropped() {
        #expect(pruned(["Item-0", "_NS:49"], bundleID: "com.stairways.keyboardmaestro.engine") == ["Item-0"])
        #expect(pruned(["Item-0", "_NS:12:1"], bundleID: "com.example.app") == ["Item-0"])
    }

    @Test("A real second item is kept")
    func realSiblingsAreKept() {
        #expect(pruned(["Item-0", "Item-1"], bundleID: "com.example.app") == ["Item-0", "Item-1"])
        #expect(pruned(["Item-0", "Named"], bundleID: "com.stairways.keyboardmaestro.engine") == ["Item-0", "Named"])
    }

    @Test("OneDrive's bare title is dropped once an account title is known")
    func oneDriveBareTitleIsAnAlias() {
        let bundleID = "com.microsoft.OneDrive"
        #expect(pruned(["OneDrive", "OneDrive \u{2014} Personal"], bundleID: bundleID) == ["OneDrive \u{2014} Personal"])
        // Two accounts stay two items.
        #expect(
            pruned(["OneDrive \u{2014} Personal", "OneDrive \u{2014} Work"], bundleID: bundleID)
                == ["OneDrive \u{2014} Personal", "OneDrive \u{2014} Work"]
        )
    }

    @Test("A bare OneDrive title on its own is kept, and other apps keep the title")
    func bareTitleAloneIsKept() {
        #expect(pruned(["OneDrive"], bundleID: "com.microsoft.OneDrive") == ["OneDrive"])
        #expect(pruned(["OneDrive", "OneDrive \u{2014} X"], bundleID: "com.example.app").count == 2)
    }
}

@Suite("Legacy AppKit status-item titles")
struct LegacyAppKitTitleTests {
    @Test(arguments: [
        "com.stairways.keyboardmaestro.engine",
        "com.knollsoft.RectanglePro",
        "com.knollsoft.Rectangle.helper",
        "com.example.app",
    ])
    func ambiguousOwnersKeepTheirPlaceholderIdentities(_ bundleID: String) {
        let title = "_NS:49"
        let tag = MenuBarItemTag(namespace: .string(bundleID), title: title)
        #expect(tag.tagIdentifier == "\(bundleID):\(title)")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier(tag.tagIdentifier) == tag.tagIdentifier)
    }

    @Test(arguments: ["Item-0", "Item-1", "Named item", "Named item:12", "_NS:", "_NS:-1", "_NS:239extra", "_NS:239\n"])
    func rectangleMigrationLeavesOtherTitlesUnchanged(_ title: String) {
        let bundleID = "com.knollsoft.Rectangle"
        let tag = MenuBarItemTag(namespace: .string(bundleID), title: title)
        #expect(tag.tagIdentifier == "\(bundleID):\(title)")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier(tag.tagIdentifier) == tag.tagIdentifier)
    }

    @Test
    func rectangleMigrationDeduplicatesAliasesWithoutChangingLiveTitleSelection() {
        let bundleID = "com.knollsoft.Rectangle"
        #expect(MenuBarItemTag.canonicalPersistentIdentifiers([
            "\(bundleID):_NS:239", "\(bundleID):Item-0", "\(bundleID):_NS:456", "\(bundleID):Item-1",
        ]) == ["\(bundleID):Item-0", "\(bundleID):Item-1"])
        #expect(!MenuBarItemTag.hasCanonicalizableTitles(bundleID))
    }

    @Test(arguments: [1, 12, 123])
    func rectangleMigrationPreservesInstanceIndices(_ instance: Int) {
        let bundleID = "com.knollsoft.Rectangle"
        let tag = MenuBarItemTag(namespace: .string(bundleID), title: "_NS:239", instanceIndex: instance)
        let current = MenuBarItemTag(namespace: .string(bundleID), title: "Item-0", instanceIndex: instance)
        #expect(tag.matchesIdentity(of: current))
        #expect(tag.tagIdentifier == "\(bundleID):Item-0:\(instance)")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundleID):_NS:239:\(instance)") == tag.tagIdentifier)
        #expect(MenuBarItemTag.canonicalPersistentIdentifier(tag.tagIdentifier) == tag.tagIdentifier)
    }

    @Test(arguments: ["_NS:239", "_NS:1", "_NS:123456"])
    func rectanglePlaceholderMatchesCurrentFallback(_ title: String) {
        let bundleID = "com.knollsoft.Rectangle"
        let tag = MenuBarItemTag(namespace: .string(bundleID), title: title)
        let current = MenuBarItemTag(namespace: .string(bundleID), title: "Item-0")
        #expect(tag.matchesIdentity(of: current))
        #expect(tag.tagIdentifier == "\(bundleID):Item-0")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundleID):\(title)") == tag.tagIdentifier)
    }
}

/// Notion Calendar has one menu bar item whose title is the next event and its countdown, or nothing.
@Suite("Notion Calendar titles")
struct NotionCalendarTitleTests {
    @Test(
        "Every Notion Calendar title names the same item",
        arguments: ["🤸🏻Sara gymnastics · 13 m left", "🤸🏻Sara gymnastics · 1 m left", "Standup · 5 m left", "Item-0"]
    )
    func everyTitleCollapses(title: String) {
        let bundle = "com.cron.electron"
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):\(title)") == "\(bundle):Item")
        #expect(MenuBarItemTag(namespace: .string(bundle), title: title).tagIdentifier == "\(bundle):Item")
    }

    @Test("A saved event title ending in a colon and a number isn't read as a second item")
    func trailingNumberIsPartOfTheTitle() {
        let bundle = "com.cron.electron"
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Sync:2") == "\(bundle):Item")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("com.if.Amphetamine:𝗧:1") == "com.if.Amphetamine:Item:1")
    }
}

/// iStat's date and time puts the day first in some regions, so the month sits before "at".
@Suite("Day-first date titles")
struct DayFirstDateTitleTests {
    @Test("A day-first date and time keeps one identity across AM and PM and a new month")
    func dayFirstChurnCollapses() {
        let bundle = MenuBarItemTag.iStatMenusStatusBundleID
        let identifiers = Set(
            ["3 Nov at 9:41 AM", "3 Nov at 9:41 PM", "1 Dec at 12:00 AM", "30 September at 11:59 PM"]
                .map { MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):\($0)") }
        )
        #expect(identifiers == ["\(bundle):# # at #:#"])
    }
}

/// Thaw's widget was named by its label, which carries the live readings. It now has a fixed identifier.
@Suite("Widget identity migration")
struct WidgetIdentityMigrationTests {
    @Test(
        "A widget saved under its old label moves to the fixed identifier",
        arguments: ["com.stonerl.Thaw", "com.stonerl.Thaw.debug"]
    )
    func savedLabelsMigrate(bundle: String) {
        let saved = [
            "Thaw widget · Live readings. Connection: Wi-Fi. Battery level: 63%. Wi-Fi strength: 67%",
            "Thaw widget · Sample readings. Symbol: CPU. Battery level: 0%. Wi-Fi strength: 100%",
            "Thaw widget preview",
        ]
        for label in saved {
            #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):\(label)") == "\(bundle):Thaw.Widget.Preview")
        }
    }

    @Test("A live widget that still reports its label gets the fixed identity")
    func liveLabelMigrates() {
        let tag = MenuBarItemTag(namespace: .string("com.stonerl.Thaw"), title: "Thaw widget · Live readings. Connection: Ethernet.")
        #expect(tag.tagIdentifier == "com.stonerl.Thaw:Thaw.Widget.Preview")
    }

    @Test("Thaw's other items and other apps' titles are left alone")
    func othersUntouched() {
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("com.stonerl.Thaw:Thaw.ControlItem.Hidden") == "com.stonerl.Thaw:Thaw.ControlItem.Hidden")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("com.example.app:Thaw widget · Live readings") == "com.example.app:Thaw widget · Live readings")
    }
}
