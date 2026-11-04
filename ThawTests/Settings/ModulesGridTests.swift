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
    @Test("Each module card shows its own page's icon")
    func icons() {
        #expect(ModulesSettingsPane.pane(for: "automation") == .scripts)
        #expect(ModulesSettingsPane.pane(for: "triggers") == .triggers)
        #expect(ModulesSettingsPane.pane(for: "widgets") == .widgets)
    }
}
