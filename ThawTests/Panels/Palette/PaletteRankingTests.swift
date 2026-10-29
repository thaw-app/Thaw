//
//  PaletteRankingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Ifrit
import MenuBarModel
import Testing
@testable import Thaw

/// How the palette lists and orders items: inventory from the item cache, then prefix matches first.
@Suite("Palette inventory and ranking", .serialized)
@MainActor
struct PaletteRankingTests {
    private static func candidate(_ name: String, owner: String = "", key: String = "") -> PaletteCandidate {
        PaletteCandidate(
            item: LayoutEditorWorld.item(name),
            displayName: name,
            ownerName: owner,
            identityKey: key
        )
    }

    @Test("Properties carry the owner only when it differs and the key only when it is not a placeholder")
    func properties() {
        #expect(Self.candidate("Battery").properties.count == 1)
        #expect(Self.candidate("Battery", owner: "Battery").properties.count == 1)
        #expect(Self.candidate("Battery", owner: "Coconut", key: "com.example:Battery").properties.count == 3)
        #expect(Self.candidate("Battery", owner: "Coconut", key: "com.example:Item-2").properties.count == 2)
    }

    @Test("The subtitle is the owner, when it says something the title does not")
    func subtitle() {
        #expect(Self.candidate("Battery").subtitle == nil)
        #expect(Self.candidate("Battery", owner: "Battery").subtitle == nil)
        #expect(Self.candidate("Battery", owner: "Coconut").subtitle == "Coconut")
    }

    @Test("A name that starts with the query ranks above a better fuzzy match inside a word")
    func prefixMatchesFirst() throws {
        let candidates = [
            Self.candidate("Sublime Clipboard"),
            Self.candidate("Clipy"),
            Self.candidate("Weather", owner: "Clima"),
            Self.candidate("Unrelated"),
        ]
        let ranked = PaletteCandidate.ranked(matching: "cli", in: candidates, using: Fuse(threshold: 0.5))
        let names = ranked.map(\.displayName)
        #expect(!names.contains("Unrelated"))
        let clipy = try #require(names.firstIndex(of: "Clipy"))
        let weather = try #require(names.firstIndex(of: "Weather"))
        let sublime = try #require(names.firstIndex(of: "Sublime Clipboard"))
        #expect(clipy < sublime)
        #expect(weather < sublime, "an owner prefix counts as a prefix match")
    }

    @Test("Inventory lists actionable cached items left to right")
    func inventory() {
        let world = LayoutEditorWorld()
        let right = LayoutEditorWorld.item("Right")
        let left = LayoutEditorWorld.item("Left")
        world.seat([right, left])
        let candidates = PaletteCandidate.inventory(from: world.appState.itemManager)
        let names = candidates.map(\.item.tag.title)
        #expect(names == ["Right", "Left"].sorted { lhs, rhs in
            (lhs == "Right" ? right : left).bounds.minX < (rhs == "Right" ? right : left).bounds.minX
        })
        #expect(candidates.allSatisfy { $0.identityKey == $0.item.uniqueIdentifier })
    }

    @Test("Inventory from a cache lists that cache's actionable items")
    func inventoryFromACache() {
        let kept = LayoutEditorWorld.item("Kept")
        var cache = MenuBarItemCache(displayID: nil)
        cache[.hidden] = [kept]
        #expect(PaletteCandidate.inventory(from: cache).map(\.item) == [kept])
    }
}
