//
//  StandInTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import PlatformRuntimeKit
import Testing
@testable import Thaw

private let standIn = "com.example.thaw.extra.timer:Thaw.Extra.Timer"
private let original = "com.apple.menuextra.timer"

@Suite("A stand-in takes its original's slot only when it has no place yet")
struct StandInPlacementTests {
    @Test("A new stand-in follows its original")
    func newStandInFollowsOriginal() {
        let order = SystemExtraStandIn.orderPlacing(standIn, after: original, in: ["a", original, "b"])

        #expect(order == ["a", original, standIn, "b"])
    }

    @Test(
        "A stand-in the user moved, one already next to its original, or an original in another section changes nothing",
        arguments: [
            [standIn, "a", original, "b"],
            ["a", original, standIn, "b"],
            ["a", "b"],
        ]
    )
    func placedStandInChangesNothing(order: [String]) {
        #expect(SystemExtraStandIn.orderPlacing(standIn, after: original, in: order) == nil)
    }
}

@MainActor
@Suite("Stand-ins and the spacing relaunch wave")
struct StandInSpacingRestartTests {
    @Test("Every stand-in bundle is recognised as this app's own", arguments: SystemExtraStandIn.allCases)
    func standInIsOwned(standIn: SystemExtraStandIn) {
        #expect(SystemExtraStandIn.owns(bundleIdentifier: standIn.bundleIdentifier))
    }

    @Test("Other apps, the app itself and a missing identifier are not stand-ins")
    func othersAreNotOwned() {
        let parent = "com.example.Thaw"
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: nil, parent: parent))
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: parent, parent: parent))
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: "org.herf.Flux", parent: parent))
        #expect(!SystemExtraStandIn.owns(bundleIdentifier: "\(parent).extra.unknown", parent: parent))
        #expect(SystemExtraStandIn.owns(bundleIdentifier: "\(parent).extra.timemachine", parent: parent))
    }
}

/// The layout identifier each stand-in's status item gets, and which stand-in
/// replaces each takeover item.
@MainActor
@Suite("System extra stand-in identity")
struct SystemExtraStandInIdentityTests {
    /// The autosave names ExtraRole in ThawExtraHelper gives each helper's item.
    @Test("Each stand-in's layout identifier is its bundle followed by the helper's autosave name", arguments: [
        (SystemExtraStandIn.focus, "Thaw.Extra.Focus"),
        (.timeMachine, "Thaw.Extra.TimeMachine"),
        (.timer, "Thaw.Extra.Timer"),
        (.airDrop, "Thaw.Extra.AirDrop"),
        (.nowPlaying, "Thaw.Extra.NowPlaying"),
        (.userSwitcher, "Thaw.Extra.UserSwitcher"),
        (.textInput, "Thaw.Extra.TextInput"),
        (.space, "Thaw.Extra.Space"),
    ])
    func itemIdentifier(standIn: SystemExtraStandIn, autosaveName: String) {
        #expect(standIn.itemIdentifier == "\(standIn.bundleIdentifier):\(autosaveName)")
    }

    @Test("Each takeover item is replaced by the stand-in of the same name", arguments: [
        (SystemExtraItem.timeMachine, SystemExtraStandIn.timeMachine),
        (.timer, .timer),
        (.textInput, .textInput),
    ])
    func standInForItem(item: SystemExtraItem, standIn: SystemExtraStandIn) {
        #expect(SystemExtraStandIn(item) == standIn)
    }
}

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

@MainActor
@Suite("Thaw's own stand-ins get a picture of their own")
struct ThawExtraGlyphTests {
    private func item(namespace: MenuBarItemTag.Namespace, title: String = "Item") -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, instanceIndex: 0),
            windowID: 90,
            ownerPID: 999_971,
            sourcePID: 999_971,
            bounds: CGRect(x: 0, y: 0, width: 22, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("Every Apple-extra stand-in draws a template symbol", arguments: SystemExtraStandIn.allCases)
    func standInDrawsTemplateSymbol(standIn: SystemExtraStandIn) throws {
        let standInItem = item(namespace: .string(standIn.bundleIdentifier))

        let image = try #require(ThawExtraGlyph.image(for: standInItem))

        #expect(image.isTemplate)
        #expect(ThawExtraGlyph.isStandIn(standInItem.tag))
    }

    @Test("Items that are not Thaw's stand-ins have no glyph")
    func otherItemsHaveNone() {
        let parent = ThawMenuBarIdentity.bundleIdentifier
        #expect(ThawExtraGlyph.image(for: item(namespace: .string("com.example.other"))) == nil)
        #expect(ThawExtraGlyph.image(for: item(namespace: .string("\(parent).extra.unknown"))) == nil)
        #expect(ThawExtraGlyph.image(for: item(namespace: .uuid(UUID()))) == nil)
        #expect(!ThawExtraGlyph.isStandIn(item(namespace: .uuid(UUID())).tag))
        #expect(!ThawExtraGlyph.isStandIn(item(namespace: .string("com.example.other")).tag))
    }

    @Test("A slot stand-in counts as a stand-in")
    func slotIsStandIn() throws {
        let slot = try #require(ItemStandInSlot.all.first)
        #expect(ThawExtraGlyph.isStandIn(item(namespace: .string(slot.bundleIdentifier)).tag))
    }

    private func writeSlotImage(_ slot: ItemStandInSlot, size: NSSize, template: Bool, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        try #require(rep.representation(using: .png, properties: [:])).write(to: folder.appending(path: "slot\(slot.number).png"))
        if template {
            try Data().write(to: folder.appending(path: "slot\(slot.number).template"))
        }
    }

    @Test("A slot shows the icon Thaw handed it, capped at the menu bar's height")
    func slotShowsItsIcon() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ThawExtraGlyphTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let tall = try #require(ItemStandInSlot.all.first)
        let short = ItemStandInSlot.all[1]
        try writeSlotImage(tall, size: NSSize(width: 72, height: 36), template: true, in: folder)
        try writeSlotImage(short, size: NSSize(width: 10, height: 12), template: false, in: folder)

        let tallImage = try #require(ThawExtraGlyph.image(for: item(namespace: .string(tall.bundleIdentifier)), slotFolder: folder))
        let shortImage = try #require(ThawExtraGlyph.image(for: item(namespace: .string(short.bundleIdentifier)), slotFolder: folder))

        #expect(tallImage.size == NSSize(width: 36, height: 18))
        #expect(tallImage.isTemplate)
        #expect(shortImage.size == NSSize(width: 10, height: 12))
        #expect(!shortImage.isTemplate)
    }

    @Test("A slot with no icon written has no picture")
    func slotWithoutIcon() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ThawExtraGlyphTests-\(UUID().uuidString)")
        let slot = try #require(ItemStandInSlot.all.last)
        #expect(ThawExtraGlyph.image(for: item(namespace: .string(slot.bundleIdentifier)), slotFolder: folder) == nil)
    }
}
