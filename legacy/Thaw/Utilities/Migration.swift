//
//  Migration.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Brings settings written by an earlier app version up to the current format.
///
/// Ice-format settings arrive through ``IceSettingsImporter``, which converts
/// them as it reads; Thaw's own domain never held the old Ice formats.
@MainActor
struct MigrationManager {
    private let diagLog = DiagLog(category: "Migration")

    let encoder = JSONEncoder()
}

// MARK: - Migrate All

extension MigrationManager {
    func migrateAll() {
        let results = [
            migratePerDisplayIceBar(),
        ]

        for result in results {
            switch result {
            case .success:
                continue
            case let .failureAndLogError(error):
                diagLog.error("Migration failed with error \(error)")
            }
        }
    }
}

// MARK: - Migrate Per-Display Thaw Bar

extension MigrationManager {
    /// Migrates legacy global Thaw Bar settings to per-display configurations.
    private func migratePerDisplayIceBar() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigratedPerDisplayIceBar) else {
            return .success
        }

        let useIceBar = Defaults.bool(forKey: .useIceBar)
        let useOnlyOnNotched = Defaults.bool(forKey: .useIceBarOnlyOnNotchedDisplay)
        let iceBarLocationRaw = Defaults.integer(forKey: .iceBarLocation)
        let iceBarLocation = IceBarLocation(rawValue: iceBarLocationRaw) ?? .dynamic

        // Only create per-display configs if the user had Thaw Bar enabled.
        guard useIceBar else {
            Defaults.set(true, forKey: .hasMigratedPerDisplayIceBar)
            diagLog.info("Per-display Thaw Bar migration: Thaw Bar was disabled, nothing to migrate")
            return .success
        }

        let configs = DisplayIceBarConfiguration.buildConfigurations(
            onlyOnNotched: useOnlyOnNotched,
            location: iceBarLocation
        )

        do {
            let data = try encoder.encode(configs)
            Defaults.set(data, forKey: .displayIceBarConfigurations)
            Defaults.set(true, forKey: .hasMigratedPerDisplayIceBar)
            diagLog.info("Per-display Thaw Bar migration: migrated \(configs.count) display(s)")
        } catch {
            return .failureAndLogError(.perDisplayIceBarMigrationError(error))
        }

        return .success
    }
}

// MARK: - MigrationResult

extension MigrationManager {
    enum MigrationResult {
        case success
        case failureAndLogError(MigrationError)
    }
}

// MARK: - MigrationError

extension MigrationManager {
    enum MigrationError: Error, CustomStringConvertible {
        case perDisplayIceBarMigrationError(any Error)

        var description: String {
            switch self {
            case let .perDisplayIceBarMigrationError(error):
                "Error migrating per-display Thaw Bar configuration: \(error)"
            }
        }
    }
}
