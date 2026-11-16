//
//  AlertRevealChoices.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation

/// The items set to show when their icon changes, as the Triggers page lists them. The saved
/// choice isn't observable, so the page shows this copy of it.
@MainActor
@Observable
final class AlertRevealChoices {
    private(set) var identifiers: Set<String> = []
    /// Whether the app's item list has arrived, in the settings process.
    private(set) var hasAppItems = false
    /// How the settings process reaches the app, and nil in the app, which lists its own items.
    @ObservationIgnored var remote: () -> SettingsRemote? = { SettingsRemote.current }

    /// True in the settings process until the app's items have arrived, so the page doesn't
    /// say nothing is hidden before it knows.
    var awaitsItems: Bool {
        remote() != nil && !hasAppItems
    }

    /// Reads the saved choice again. Only a different one is assigned, so a reload for
    /// another setting redraws nothing.
    func reload() {
        let saved = MenuBarItemAlertReveals.identifiers()
        if saved != identifiers {
            identifiers = saved
        }
    }

    func setEnabled(_ isEnabled: Bool, for identifier: String) {
        MenuBarItemAlertReveals.setEnabled(isEnabled, for: identifier)
        reload()
    }

    func appItemsArrived() {
        if !hasAppItems {
            hasAppItems = true
        }
    }
}
