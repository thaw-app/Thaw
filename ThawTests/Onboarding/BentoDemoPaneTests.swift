//
//  BentoDemoPaneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// A click on an onboarding card opens the pane that holds what the card shows.
@MainActor
@Suite("Onboarding card panes")
struct BentoDemoPaneTests {
    @Test("Each card opens its pane", arguments: [
        (BentoDemo.find, SettingsNavigationIdentifier.visibility),
        (BentoDemo.style, SettingsNavigationIdentifier.menuBarAppearance),
        (BentoDemo.reveal, SettingsNavigationIdentifier.visibility),
        (BentoDemo.thawBar, SettingsNavigationIdentifier.thawBar),
        (BentoDemo.triggers, SettingsNavigationIdentifier.triggers),
        (BentoDemo.profiles, SettingsNavigationIdentifier.profiles),
        (BentoDemo.zen, SettingsNavigationIdentifier.hotkeys),
        (BentoDemo.integrations, SettingsNavigationIdentifier.automation),
    ])
    func cardOpensItsPane(demo: BentoDemo, pane: SettingsNavigationIdentifier) {
        #expect(demo.pane == pane)
    }
}
