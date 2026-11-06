//
//  MenuBarItemAlertRevealsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("The alert reveal opt-ins are stored by tag identifier", .scratchDefaults)
struct MenuBarItemAlertRevealsTests {
    @Test("Nothing is opted in by default")
    func emptyByDefault() {
        #expect(MenuBarItemAlertReveals.identifiers().isEmpty)
        #expect(!MenuBarItemAlertReveals.contains("com.example.app:Item"))
    }

    @Test("Enabling stores the identifier sorted, and disabling removes it")
    func enableAndDisable() {
        MenuBarItemAlertReveals.setEnabled(true, for: "b:B")
        MenuBarItemAlertReveals.setEnabled(true, for: "a:A")
        MenuBarItemAlertReveals.setEnabled(true, for: "a:A")

        #expect(MenuBarItemAlertReveals.identifiers() == ["a:A", "b:B"])
        #expect(Defaults.stringArray(forKey: .menuBarItemAlertReveals) == ["a:A", "b:B"])
        #expect(MenuBarItemAlertReveals.contains("b:B"))

        MenuBarItemAlertReveals.setEnabled(false, for: "b:B")

        #expect(MenuBarItemAlertReveals.identifiers() == ["a:A"])
        #expect(!MenuBarItemAlertReveals.contains("b:B"))
    }
}
