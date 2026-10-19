//
//  ModulesGridTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Modules grid")
struct ModulesGridTests {
    private let cards: [ModuleCard] = [
        .init(kind: .profiles, name: "Profiles", summary: "Switches between saved layouts.", pane: .profiles),
        .init(kind: .module("triggers"), name: "Thaw Triggers", summary: "Shows chosen menu bar items while an app runs.", pane: .triggers),
        .init(kind: .module("widgets"), name: "Thaw Widgets", summary: "Shows battery, Wi-Fi and other readings.", pane: .widgets),
    ]

    @Test("An empty or blank search shows every card")
    func emptySearch() {
        #expect(ModulesSettingsPane.matching(cards, query: "") == cards)
        #expect(ModulesSettingsPane.matching(cards, query: "   ") == cards)
    }

    @Test("Search matches names and descriptions, ignoring case, and needs every word")
    func search() {
        #expect(ModulesSettingsPane.matching(cards, query: "widgets").map(\.id) == ["widgets"])
        #expect(ModulesSettingsPane.matching(cards, query: "WI-FI").map(\.id) == ["widgets"])
        #expect(ModulesSettingsPane.matching(cards, query: "shows app").map(\.id) == ["triggers"])
        #expect(ModulesSettingsPane.matching(cards, query: "nothing like this").isEmpty)
    }

    @Test("Each module card shows its own page's icon")
    func icons() {
        #expect(ModulesSettingsPane.pane(for: "automation") == .scripts)
        #expect(ModulesSettingsPane.pane(for: "triggers") == .triggers)
        #expect(ModulesSettingsPane.pane(for: "widgets") == .widgets)
    }
}
