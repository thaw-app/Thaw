//
//  ToolsSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel
import Observation

/// Model for the Troubleshooting page's settings.
@MainActor
@Observable
final class ToolsSettings: SettingsURIHandling {
    var enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging {
        didSet {
            guard oldValue != enableDiagnosticLogging else { return }
            Defaults.set(enableDiagnosticLogging, forKey: .enableDiagnosticLogging)
            #if DEBUG
                // Keep debug logging enabled despite profile swaps or toggles to retain capture diagnostics.
                DiagnosticLogger.shared.isEnabled = true
            #else
                DiagnosticLogger.shared.isEnabled = enableDiagnosticLogging
            #endif
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
        Defaults.ifPresent(key: .enableDiagnosticLogging, assign: &enableDiagnosticLogging)
    }

    /// The thaw:// keys of this page's Bool settings.
    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<ToolsSettings, Bool>] = [
        "enableDiagnosticLogging": \.enableDiagnosticLogging,
    ]

    /// Applies a thaw:// settings change for one of this page's keys.
    func handleExternalSettingsChange(_ notification: Notification) {
        applySettingsURIChange(notification, bools: Self.uriBoolKeys)
    }
}
