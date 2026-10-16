//
//  MenuBarItemNameMemoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins which items may carry a remembered name across launches.
///
/// The first cache pass after launch has no source PIDs, so items read
/// "Menu Bar Item" until the AX scan finishes (#956). A remembered name is
/// only safe where its key means the same item next launch; a wrong name
/// gets clicked.
///
/// Serialized: the tests swap the process-wide `menuBarItemResolvedNames`.
@Suite(.serialized)
struct MenuBarItemNameMemoryTests {
    @Test("An ordinary app item is eligible")
    func ordinaryAppItemIsEligible() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Widget"),
            windowID: 42
        )
        #expect(MenuBarItemNameMemory.isEligible(item))
    }

    @Test("A Control-Center-hosted item with a distinctive title is eligible")
    func distinctivelyTitledHostedItemIsEligible() {
        // Hosted by Control Center, but titled after their owner, so the key
        // stays meaningful across launches.
        for title in ["raycastIcon", "com.goodsnooze.MacWhisper", "FocusModes"] {
            let item = MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.apple.controlcenter", title: title),
                windowID: 100
            )
            #expect(MenuBarItemNameMemory.isEligible(item), "\(title) should be eligible")
        }
    }

    @Test("Control Center's generic slots are refused")
    func genericControlCenterSlotsAreRefused() {
        // `Item-N` encodes a position in Control Center's hosting order, not
        // an identity. Which slot is Item-0 depends on which agents launched
        // this boot, so a name restored here can land on another app's icon.
        for title in ["Item-0", "Item-1", "Item-12"] {
            let item = MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.apple.controlcenter", title: title),
                windowID: 200
            )
            #expect(!MenuBarItemNameMemory.isEligible(item), "\(title) must be refused")
        }
    }

    @Test("A generic slot stays refused at every instance index")
    func genericSlotRefusedAtEveryInstanceIndex() {
        // The index distinguishes Item-0:7 from Item-0:9 this session only.
        for index in 1...12 {
            let item = MenuBarItem.fixture(
                tag: .appItem(
                    bundleID: "com.apple.controlcenter",
                    title: "Item-0",
                    instanceIndex: index
                ),
                windowID: 300
            )
            #expect(!MenuBarItemNameMemory.isEligible(item), "Item-0:\(index) must be refused")
        }
    }

    @Test("Items with a UUID namespace are refused")
    func uuidNamespacedItemsAreRefused() {
        // macOS reassigns these every session, so the key could never match
        // again. Mirrors MenuBarItemFailureLedger's own stability rule.
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .uuid(UUID()), title: "Widget"),
            windowID: 400
        )
        #expect(!MenuBarItemNameMemory.isEligible(item))
    }

    @Test("Thaw's own control items are refused")
    func controlItemsAreRefused() {
        // They already name themselves from Constants.displayName and never
        // reach the fallback this memory feeds.
        let item = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 500)
        #expect(!MenuBarItemNameMemory.isEligible(item))
    }

    @Test("An unresolved item reads back nothing when nothing was stored")
    func unresolvedItemWithoutMemoryReadsNothing() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.never-seen-\(UUID().uuidString)", title: "Widget"),
            windowID: 600,
            sourcePID: nil
        )
        #expect(MenuBarItemNameMemory.rememberedName(for: item) == nil)
        // And with no memory to fall back on, the generic label still shows.
        #expect(item.autoDetectedName == "Menu Bar Item")
    }

    @Test("A refused item never reads back a name, even if one is in defaults")
    func refusedItemNeverReadsBack() {
        // Even an older build's stored entry must not name a generic slot.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.apple.controlcenter", title: "Item-0"),
            windowID: 700,
            sourcePID: nil
        )
        let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)

        let original = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        defer { Defaults.set(original, forKey: .menuBarItemResolvedNames) }

        var seeded = original
        seeded[key] = "Docker Desktop"
        Defaults.set(seeded, forKey: .menuBarItemResolvedNames)

        #expect(MenuBarItemNameMemory.rememberedName(for: item) == nil)
        #expect(item.autoDetectedName == "Menu Bar Item")
    }

    @Test("A remembered name labels an item whose source has not resolved")
    func rememberedNameLabelsUnresolvedItem() {
        let bundleID = "com.example.remembered-\(UUID().uuidString)"
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: "Widget"),
            windowID: 800,
            sourcePID: nil
        )
        let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)

        let original = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        defer { Defaults.set(original, forKey: .menuBarItemResolvedNames) }

        var seeded = original
        seeded[key] = "Example Widget"
        Defaults.set(seeded, forKey: .menuBarItemResolvedNames)

        #expect(MenuBarItemNameMemory.rememberedName(for: item) == "Example Widget")
        #expect(item.autoDetectedName == "Example Widget")
    }

    @Test("A custom name still outranks a remembered one")
    func customNameOutranksRememberedName() {
        // displayName's precedence order is user intent first. The memory is
        // a fallback for the auto-detected name, not a competitor to it.
        let bundleID = "com.example.custom-\(UUID().uuidString)"
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: "Widget"),
            windowID: 900,
            sourcePID: nil
        )
        let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)

        let originalNames = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        let originalCustom = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        defer {
            Defaults.set(originalNames, forKey: .menuBarItemResolvedNames)
            Defaults.set(originalCustom, forKey: .menuBarItemCustomNames)
        }

        var seededNames = originalNames
        seededNames[key] = "Remembered"
        Defaults.set(seededNames, forKey: .menuBarItemResolvedNames)

        var seededCustom = originalCustom
        seededCustom[item.uniqueIdentifier] = "Chosen By User"
        Defaults.set(seededCustom, forKey: .menuBarItemCustomNames)

        #expect(item.displayName == "Chosen By User")
    }

    @Test("Unresolved items are never written back into the memory")
    func unresolvedItemsAreNotRemembered() {
        // Storing the generic fallback would make the memory self-defeating:
        // the next launch would restore "Menu Bar Item" as if it were a name.
        let bundleID = "com.example.unresolved-\(UUID().uuidString)"
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: "Widget"),
            windowID: 1000,
            sourcePID: nil
        )
        let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)

        let original = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        defer { Defaults.set(original, forKey: .menuBarItemResolvedNames) }

        MenuBarItemNameMemory.remember([item])

        let stored = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        #expect(stored[key] == nil)
    }

    @Test("Refused items are never written into the memory")
    func refusedItemsAreNotRemembered() {
        // A live sourcePID passes the source-application filter, so only the
        // eligibility rule can keep this out of the dictionary.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.apple.controlcenter", title: "Item-0"),
            windowID: 1100,
            sourcePID: ProcessInfo.processInfo.processIdentifier
        )
        #expect(item.sourceApplication != nil)
        let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)

        let original = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        var baseline = original
        baseline[key] = nil
        Defaults.set(baseline, forKey: .menuBarItemResolvedNames)
        defer { Defaults.set(original, forKey: .menuBarItemResolvedNames) }

        MenuBarItemNameMemory.remember([item])

        let stored = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        #expect(stored[key] == nil)
    }
}
