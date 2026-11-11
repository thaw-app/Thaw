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

    /// Start a new log file once the current one reaches this many megabytes; 0 turns it off.
    var diagnosticLogMaxSizeMB = Defaults.DefaultValue.diagnosticLogMaxSizeMB {
        didSet {
            guard oldValue != diagnosticLogMaxSizeMB else { return }
            Defaults.set(diagnosticLogMaxSizeMB, forKey: .diagnosticLogMaxSizeMB)
            applyLogRotationPolicy()
        }
    }

    var diagnosticLogRetentionDays = Defaults.DefaultValue.diagnosticLogRetentionDays {
        didSet {
            guard oldValue != diagnosticLogRetentionDays else { return }
            Defaults.set(diagnosticLogRetentionDays, forKey: .diagnosticLogRetentionDays)
            applyLogRotationPolicy()
        }
    }

    var diagnosticLogRotationInterval = Defaults.DefaultValue.diagnosticLogRotationInterval {
        didSet {
            guard oldValue != diagnosticLogRotationInterval else { return }
            Defaults.set(diagnosticLogRotationInterval.rawValue, forKey: .diagnosticLogRotationInterval)
            applyLogRotationPolicy()
        }
    }

    @ObservationIgnored
    private var settingsURIChanges: AnyCancellable?

    /// Only guards the conversion to bytes against overflow from a stored value.
    private nonisolated static let maxDiagnosticLogSizeMB = 1_000_000

    /// Where a changed policy goes; the logger prunes old files by it at once.
    @ObservationIgnored
    var sendRotationPolicy: (DiagnosticLogger.RotationPolicy) -> Void = { DiagnosticLogger.shared.setRotationPolicy($0) }

    /// Set while the stored values load, so the logger never prunes by a policy that is half defaults.
    @ObservationIgnored
    private var isLoadingStoredValues = false

    func applyLogRotationPolicy() {
        guard !isLoadingStoredValues else { return }
        sendRotationPolicy(Self.rotationPolicy(
            maxSizeMB: diagnosticLogMaxSizeMB,
            retentionDays: diagnosticLogRetentionDays,
            interval: diagnosticLogRotationInterval
        ))
    }

    nonisolated static func rotationPolicy(maxSizeMB: Int, retentionDays: Int, interval: LogRotationInterval) -> DiagnosticLogger.RotationPolicy {
        let megabytes = min(max(0, maxSizeMB), maxDiagnosticLogSizeMB)
        return DiagnosticLogger.RotationPolicy(
            maxFileSizeBytes: UInt64(megabytes) * 1024 * 1024,
            rotationInterval: interval.seconds,
            retentionDays: max(1, retentionDays)
        )
    }

    /// Starts the log at launch, before this model exists, with the stored
    /// policy set first: opening the log prunes old files by it.
    static func startDiagnosticLogging() {
        DiagnosticLogger.shared.setRotationPolicy(persistedRotationPolicy())
        #if DEBUG
            // Debug builds always log, so development doesn't depend on the toggle.
            DiagnosticLogger.shared.isEnabled = true
        #else
            if Defaults.bool(forKey: .enableDiagnosticLogging) {
                DiagnosticLogger.shared.isEnabled = true
            }
        #endif
    }

    /// The stored policy, read before this model exists: logging starts first, and
    /// pruning by the defaults would delete files the user chose to keep.
    nonisolated static func persistedRotationPolicy(in defaults: UserDefaults = Defaults.store) -> DiagnosticLogger.RotationPolicy {
        let maxSize = defaults.object(forKey: Defaults.Key.diagnosticLogMaxSizeMB.rawValue) as? Int ?? Defaults.DefaultValue.diagnosticLogMaxSizeMB
        let retention = defaults.object(forKey: Defaults.Key.diagnosticLogRetentionDays.rawValue) as? Int ?? Defaults.DefaultValue.diagnosticLogRetentionDays
        let interval = defaults.string(forKey: Defaults.Key.diagnosticLogRotationInterval.rawValue)
            .flatMap(LogRotationInterval.init(rawValue:)) ?? Defaults.DefaultValue.diagnosticLogRotationInterval
        return rotationPolicy(maxSizeMB: maxSize, retentionDays: retention, interval: interval)
    }

    func performSetup() {
        loadInitialState()
        settingsURIChanges = subscribeToSettingsURIChanges()
    }

    func loadInitialState() {
        isLoadingStoredValues = true
        Defaults.ifPresent(key: .enableDiagnosticLogging, assign: &enableDiagnosticLogging)
        Defaults.ifPresent(key: .diagnosticLogMaxSizeMB, assign: &diagnosticLogMaxSizeMB)
        Defaults.ifPresent(key: .diagnosticLogRetentionDays, assign: &diagnosticLogRetentionDays)
        Defaults.ifPresent(key: .diagnosticLogRotationInterval) { (raw: String) in
            if let interval = LogRotationInterval(rawValue: raw) {
                diagnosticLogRotationInterval = interval
            }
        }
        isLoadingStoredValues = false
        applyLogRotationPolicy()
    }

    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<ToolsSettings, Bool>] = [
        "enableDiagnosticLogging": \.enableDiagnosticLogging,
    ]

    func handleExternalSettingsChange(_ notification: Notification) {
        applySettingsURIChange(notification, bools: Self.uriBoolKeys)
    }
}
