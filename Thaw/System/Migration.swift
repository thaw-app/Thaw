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
        removeReorderEditorFlag(from: Defaults.store)
        migrateSearchPresentation(in: Defaults.store)
        migrateLastSettingsPane(in: Defaults.store)
        migrateSpaceAppearanceKeys(in: Defaults.store, spaces: Bridging.getManagedSpaces())
        resetRecordingAlertsOnReturn(in: Defaults.store)
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

// MARK: - Remove Retired Reorder Editor Flag

extension MigrationManager {
    /// The reorder editor is gone; Pop Out opens the Layout window instead.
    static let reorderEditorFlagKey = "useReorderLayoutEditor"

    func removeReorderEditorFlag(from defaults: UserDefaults) {
        defaults.removeObject(forKey: Self.reorderEditorFlagKey)
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

// MARK: - Migrate Search Styles

extension MigrationManager {
    /// Search's three styles became two layouts: stores the layout a saved
    /// style opens as, and drops the frames Detailed saved per display.
    func migrateSearchPresentation(in defaults: UserDefaults) {
        let key = Defaults.Key.menuBarSearchPresentation.rawValue
        if let stored = defaults.string(forKey: key), let layout = SearchPresentation(storedValue: stored), layout.rawValue != stored {
            defaults.set(layout.rawValue, forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("MenuBarSearchPanelFrame_") {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Migrate Retired Settings Pages

extension MigrationManager {
    /// Spaces, Automation, Experiments and Advanced are no longer pages: a
    /// saved last page that names one is stored as the page it opens.
    func migrateLastSettingsPane(in defaults: UserDefaults) {
        let key = Defaults.Key.lastSettingsPane.rawValue
        guard
            let stored = defaults.string(forKey: key), let pane = SettingsNavigationIdentifier(storedValue: stored), pane.rawValue != stored
        else {
            return
        }
        defaults.set(pane.rawValue, forKey: key)
    }
}

// MARK: - Migrate Per-Space Looks to Persistent Keys

extension MigrationManager {
    /// Rekeys per-Space looks from raw Space IDs, which macOS renumbers at logout, to
    /// persistent keys. Unresolved ones wait for a later launch; a persistent entry wins.
    func migrateSpaceAppearanceKeys(in defaults: UserDefaults, spaces: [Bridging.ManagedSpace]) {
        let key = Defaults.Key.menuBarAppearanceSpaceOverrides.rawValue
        guard
            let data = defaults.data(forKey: key), var overrides = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return
        }
        let keysByID = Dictionary(spaces.map { (String($0.spaceID), $0.persistentKey) }) { first, _ in first }
        var changed = false
        for rawID in overrides.keys where rawID.allSatisfy(\.isNumber) {
            guard let persistentKey = keysByID[rawID] else { continue }
            if overrides[persistentKey] == nil {
                overrides[persistentKey] = overrides[rawID]
            }
            overrides[rawID] = nil
            changed = true
        }
        guard changed, let rewritten = try? JSONSerialization.data(withJSONObject: overrides, options: [.sortedKeys]) else {
            return
        }
        defaults.set(rewritten, forKey: key)
    }
}

// MARK: - Reset Returning Recording Alerts

extension MigrationManager {
    /// Marks that the alerts' saved switch was reset once.
    static let recordingAlertsReturnedKey = "RecordingAlertsReturned"

    /// The alerts stayed off while hidden, whatever was saved. Clearing the old switch
    /// once keeps them off until it's turned on again in Visibility.
    func resetRecordingAlertsOnReturn(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: Self.recordingAlertsReturnedKey) else {
            return
        }
        defaults.removeObject(forKey: Defaults.Key.enableRecordingWatch.rawValue)
        defaults.set(true, forKey: Self.recordingAlertsReturnedKey)
    }
}

// MARK: - Migrate Per-Display Thaw Bar

extension MigrationManager {
    /// Migrates legacy global Thaw Bar settings to per-display configurations.
    func migratePerDisplayThawBar() -> MigrationResult {
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
