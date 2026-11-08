//
//  WidgetsSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Observation

/// Model for the Widgets page's settings.
@MainActor
@Observable
final class WidgetsSettings: SettingsURIHandling {
    /// Replaces Thaw's status menu with a panel; disabled secondary clicks use NSMenu.
    var enableControlItemPanel = Defaults.DefaultValue.enableControlItemPanel {
        didSet {
            guard oldValue != enableControlItemPanel else { return }
            Defaults.set(enableControlItemPanel, forKey: .enableControlItemPanel)
        }
    }

    @ObservationIgnored
    private var settingsURIChanges: AnyCancellable?

    func performSetup() {
        loadInitialState()
        settingsURIChanges = subscribeToSettingsURIChanges()
    }

    /// Reads the stored values.
    func loadInitialState() {
        Defaults.ifPresent(key: .enableControlItemPanel, assign: &enableControlItemPanel)
    }

    /// The thaw:// keys of this page's Bool settings.
    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<WidgetsSettings, Bool>] = [
        "enableControlItemPanel": \.enableControlItemPanel,
    ]

    /// Applies a thaw:// settings change for one of this page's keys.
    func handleExternalSettingsChange(_ notification: Notification) {
        applySettingsURIChange(notification, bools: Self.uriBoolKeys)
    }
}
