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
}
