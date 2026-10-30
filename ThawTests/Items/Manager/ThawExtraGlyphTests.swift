//
//  ThawExtraGlyphTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import PlatformRuntimeKit
import Testing
@testable import Thaw

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
