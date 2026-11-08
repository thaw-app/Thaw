//
//  SpacesSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Observation

/// Model for the Spaces settings on the Displays page.
@MainActor
@Observable
final class SpacesSettings: SettingsURIHandling {
    /// Whether a menu bar item shows the active Space's name.
    var showSpaceIndicator = Defaults.DefaultValue.showSpaceIndicator {
        didSet {
            guard oldValue != showSpaceIndicator else { return }
            Defaults.set(showSpaceIndicator, forKey: .showSpaceIndicator)
        }
    }

    @ObservationIgnored
    private var settingsURIChanges: AnyCancellable?

    func performSetup() {
        loadInitialState()
        settingsURIChanges = subscribeToSettingsURIChanges()
    }

    func loadInitialState() {
        Defaults.ifPresent(key: .showSpaceIndicator, assign: &showSpaceIndicator)
    }

    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<SpacesSettings, Bool>] = [
        "showSpaceIndicator": \.showSpaceIndicator,
    ]

    func handleExternalSettingsChange(_ notification: Notification) {
        applySettingsURIChange(notification, bools: Self.uriBoolKeys)
    }
}
