//
//  BentoTileChoice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// What a card click on the last onboarding screen does. Simple Mode is one page, so a card opens its
/// pane only under All Settings; under Simple Mode it finishes setup and keeps the choice.
enum BentoTileChoice {
    static func outcome(for demo: BentoDemo, simpleMode: Bool) -> (simpleMode: Bool, pane: SettingsNavigationIdentifier?) {
        simpleMode ? (true, nil) : (false, demo.pane)
    }
}
