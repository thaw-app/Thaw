//
//  ItemStandInSlotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// The fixed stand-in bundles, which must match what ThawExtraHelper ships.
@Suite("Item stand-in slots")
struct ItemStandInSlotTests {
    private static let thaw = ThawMenuBarIdentity.bundleIdentifier

    @Test("There are six slots, numbered in order")
    func sixSlots() {
        #expect(ItemStandInSlot.all.map(\.number) == Array(1 ... 6))
        #expect(ItemStandInSlot.all.sorted() == ItemStandInSlot.all)
        #expect(ItemStandInSlot.all[0] < ItemStandInSlot.all[5])
    }

    @Test("A slot's names follow its number")
    func names() throws {
        let slot = try #require(ItemStandInSlot.all.first { $0.number == 3 })
        #expect(slot.bundleIdentifier == "\(Self.thaw).extra.slot3")
        #expect(slot.autosaveName == "Thaw.Extra.Slot3")
        #expect(slot.itemIdentifier == MenuBarItemTag.canonicalPersistentIdentifier("\(Self.thaw).extra.slot3:Thaw.Extra.Slot3"))
        #expect(slot.bundleURL.lastPathComponent == "Thaw Stand-In 3.app")
        #expect(slot.bundleURL.path.hasPrefix(Bundle.main.bundleURL.path))
        #expect(slot.updateNotification.rawValue == "\(Self.thaw).extra.slot3.update")
        #expect(ItemStandInSlot.clickNotification.rawValue == "\(Self.thaw).extra.slot.clicked")
    }

    @Test("A slot is found again from its bundle identifier and tag")
    func roundTrip() {
        for slot in ItemStandInSlot.all {
            #expect(ItemStandInSlot(bundleIdentifier: slot.bundleIdentifier) == slot)
            let tag = MenuBarItemTag(namespace: .string(slot.bundleIdentifier), title: slot.autosaveName, instanceIndex: 0)
            #expect(ItemStandInSlot(tag: tag) == slot)
        }
    }

    @Test("Bundles that aren't slots are not taken for one")
    func notSlots() {
        #expect(ItemStandInSlot(bundleIdentifier: "\(Self.thaw).extra.slot7") == nil)
        #expect(ItemStandInSlot(bundleIdentifier: "\(Self.thaw).extra.slot0") == nil)
        #expect(ItemStandInSlot(bundleIdentifier: "\(Self.thaw).extra.slotX") == nil)
        #expect(ItemStandInSlot(bundleIdentifier: "com.example.app") == nil)
        let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "Item-0", instanceIndex: 0)
        #expect(ItemStandInSlot.label(for: tag) == nil)
    }

    @Test("A slot's label is read without failing, whether or not one is stored")
    func slotLabel() throws {
        let slot = try #require(ItemStandInSlot.all.first)
        let tag = MenuBarItemTag(namespace: .string(slot.bundleIdentifier), title: slot.autosaveName, instanceIndex: 0)
        let stored = UserDefaults.standard.dictionary(forKey: "MenuBarItemManager.itemStandInLabels") as? [String: String]
        #expect(ItemStandInSlot.label(for: tag) == stored?[slot.bundleIdentifier])
    }
}
