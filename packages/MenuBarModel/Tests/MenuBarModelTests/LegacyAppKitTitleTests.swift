//
//  LegacyAppKitTitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing

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
