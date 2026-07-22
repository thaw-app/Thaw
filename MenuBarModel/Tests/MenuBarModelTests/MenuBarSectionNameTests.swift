//
//  MenuBarSectionNameTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing

@Suite("Menu bar section names")
struct MenuBarSectionNameTests {
    @Test("Cases and wire values remain stable")
    func casesAndWireValuesRemainStable() {
        #expect(MenuBarSectionName.allCases == [.visible, .hidden, .alwaysHidden])
        #expect(MenuBarSectionName.visible.rawValue == "visible")
        #expect(MenuBarSectionName.hidden.rawValue == "hidden")
        #expect(MenuBarSectionName.alwaysHidden.rawValue == "alwaysHidden")
    }

    @Test("Display and log labels remain stable")
    func labelsRemainStable() {
        let expected: [(MenuBarSectionName, String, String)] = [
            (.visible, "Visible", "visible section"),
            (.hidden, "Hidden", "hidden section"),
            (.alwaysHidden, "Always-Hidden", "always-hidden section"),
        ]

        for (section, displayString, logString) in expected {
            #expect(section.displayString == displayString)
            #expect(section.logString == logString)
        }
    }
}
