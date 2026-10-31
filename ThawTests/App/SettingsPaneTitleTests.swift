//
//  SettingsPaneTitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Settings pane titles")
struct SettingsPaneTitleTests {
    private func title(of pane: some NavigationIdentifier) -> String {
        String(localized: pane.localized)
    }

    @Test("The Extras page keeps its stored identifier, so saved settings and links still find it")
    func extrasKeepsItsIdentifier() {
        #expect(SettingsNavigationIdentifier.modules.rawValue == "Modules")
    }

    @Test("A page is named by its label, not its stored identifier", arguments: [
        (SettingsNavigationIdentifier.menuBarLayout, "Layout"),
        (.menuBarAppearance, "Appearance"),
        (.hotkeys, "Shortcuts"),
        (.displays, "Displays"),
        (.modules, "Extras"),
        (.triggers, "Triggers"),
        (.scripts, "Scripts"),
        (.widgets, "Widgets"),
    ])
    func labelNotIdentifier(pane: SettingsNavigationIdentifier, label: String) {
        #expect(String(localized: pane.localized) == label)
        #expect(title(of: pane) == label)
    }
}
