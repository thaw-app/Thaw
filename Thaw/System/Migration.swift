//
//  Migration.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

/// Updates older settings and removes data for retired features.
/// There are no Ice migrations: the app only reads its own defaults domain.
@MainActor
struct MigrationManager {
    private let diagLog = DiagLog(category: "Migration")

    let encoder = JSONEncoder()
}

// MARK: - Entry Point

extension MigrationManager {
    /// Runs every outstanding migration and logs whatever each one reported.
    func migrateAll() {
        removeMenuBarHistory(from: Defaults.store)
        removeAXBridgeLogs()
        let results = [
            migratePerDisplayThawBar(),
        ]
        for case let .failureAndLogError(error) in results {
            diagLog.error("Migration failed with error \(error)")
        }
    }
}

// MARK: - Remove Retired Menu Bar History

extension MigrationManager {
    func removeMenuBarHistory(from defaults: UserDefaults) {
        defaults.removeObject(forKey: "EnableBarHygieneAudit")
        defaults.removeObject(forKey: "MenuBarHygieneLedger")
        defaults.removeObject(forKey: "LayoutSuggestions.dismissed.unusedItems")
    }
}

// MARK: - Remove Retired AX Bridge Logs

extension MigrationManager {
    /// The AX bridge breadcrumb log is gone; nothing else would ever delete the files it left.
    func removeAXBridgeLogs(
        in directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Thaw", isDirectory: true)
    ) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("ax-bridge-") && file.pathExtension == "txt" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - Migrate Per-Display Thaw Bar

extension MigrationManager {
    /// Migrates legacy global Thaw Bar settings to per-display configurations.
    private func migratePerDisplayThawBar() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigratedPerDisplayThawBar) else {
            return .success
        }

        let useThawBar = Defaults.bool(forKey: .useThawBar)
        let useOnlyOnNotched = Defaults.bool(forKey: .useThawBarOnlyOnNotchedDisplay)
        let thawBarLocationRaw = Defaults.integer(forKey: .thawBarLocation)
        let thawBarLocation = ThawBarLocation(rawValue: thawBarLocationRaw) ?? .dynamic

        // Only create per-display configs if the user had Thaw Bar enabled.
        guard useThawBar else {
            Defaults.set(true, forKey: .hasMigratedPerDisplayThawBar)
            diagLog.info("Per-display Thaw Bar migration: Thaw Bar was disabled, nothing to migrate")
            return .success
        }

        let configs = DisplayThawBarConfiguration.buildConfigurations(
            onlyOnNotched: useOnlyOnNotched,
            location: thawBarLocation
        )

        do {
            let data = try encoder.encode(configs)
            Defaults.set(data, forKey: .displayThawBarConfigurations)
            Defaults.set(true, forKey: .hasMigratedPerDisplayThawBar)
            diagLog.info("Per-display Thaw Bar migration: migrated \(configs.count) display(s)")
        } catch {
            return .failureAndLogError(.perDisplayThawBarMigrationError(error))
        }

        return .success
    }
}

// MARK: - Step Outcomes

extension MigrationManager {
    /// What a migration step has to say for itself once it is finished.
    enum MigrationResult {
        /// The step finished with nothing to report.
        case success

        /// The step could not finish, and should be attempted again later.
        case failureAndLogError(MigrationError)
    }
}

// MARK: - Step Failures

extension MigrationManager {
    enum MigrationError: Error, CustomStringConvertible {
        case perDisplayThawBarMigrationError(any Error)

        var description: String {
            switch self {
            case let .perDisplayThawBarMigrationError(error):
                "Error migrating per-display Thaw Bar configuration: \(error)"
            }
        }
    }
}
