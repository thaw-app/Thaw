//
//  ModuleLaunchRules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawModuleKit

/// What a module's Info.plist says about it.
nonisolated struct ModuleManifest: Equatable, Sendable {
    static let identifierKey = "ThawModuleIdentifier"
    static let minimumAPIVersionKey = "ThawModuleMinimumAPIVersion"

    /// The short name Thaw stores the module under, such as "automation".
    let identifier: String
    /// The name shown in Settings, from the bundle's name.
    let name: String
    let bundleIdentifier: String
    let version: String
    /// The lowest module API version the module works with.
    let minimumAPIVersion: Int

    init(identifier: String, name: String? = nil, bundleIdentifier: String, version: String, minimumAPIVersion: Int) {
        self.identifier = identifier
        self.name = name ?? identifier
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.minimumAPIVersion = minimumAPIVersion
    }

    /// Reads a manifest, or returns nil when the bundle doesn't declare itself a module.
    init?(infoDictionary info: [String: Any]) {
        guard let identifier = info[Self.identifierKey] as? String, !identifier.isEmpty,
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              let minimumAPIVersion = info[Self.minimumAPIVersionKey] as? Int, minimumAPIVersion > 0
        else {
            return nil
        }
        self.init(
            identifier: identifier,
            name: info["CFBundleName"] as? String,
            bundleIdentifier: bundleIdentifier,
            version: info["CFBundleShortVersionString"] as? String ?? "0",
            minimumAPIVersion: minimumAPIVersion
        )
    }
}

/// Whether an installed module may be launched.
nonisolated enum ModuleLaunchVerdict: Equatable, Sendable {
    case launch
    case notAModule
    case untrusted
    case needsNewerThaw(requiredAPIVersion: Int)
}

nonisolated enum ModuleLaunchRules {
    /// The module API version this build of Thaw provides.
    static let apiVersion = 1

    /// Decides whether a module may launch. A module must be signed by the same
    /// team as Thaw, and both team IDs must be known, the same rule Thaw applies
    /// to Floe as a built-in trusted sender.
    static func verdict(
        manifest: ModuleManifest?,
        moduleTeamID: String?,
        ownTeamID: String?,
        apiVersion: Int = apiVersion
    ) -> ModuleLaunchVerdict {
        guard let manifest else { return .notAModule }
        guard let moduleTeamID, let ownTeamID, moduleTeamID == ownTeamID else { return .untrusted }
        guard manifest.minimumAPIVersion <= apiVersion else {
            return .needsNewerThaw(requiredAPIVersion: manifest.minimumAPIVersion)
        }
        return .launch
    }
}

/// Which modules start switched on before the user has chosen.
nonisolated enum ModuleDefaults {
    /// A module starts on when Thaw already had work for it from before it
    /// became a module. Each check is keyed by the module's identifier and
    /// only runs for that module.
    static func startsEnabled(_ identifier: String, priorWork: [String: () -> Bool]) -> Bool {
        priorWork[identifier]?() ?? false
    }

    /// Each module's check for work Thaw had before it became a module: scripts
    /// for Thaw Scripts, saved triggers for Thaw Triggers, the widget icon in
    /// the menu bar for Thaw Widgets. Profile files are read only when asked.
    static func priorWorkInThawSettings(profileFiles: @escaping () -> [Data]) -> [String: () -> Bool] {
        [
            ModuleIdentifier.scripts.rawValue: {
                automationHadScripts(
                    globalHookData: [Defaults.Key.globalPreProfileHook, .globalPostProfileHook].map(Defaults.data(forKey:)),
                    profileFiles: profileFiles()
                )
            },
            ModuleIdentifier.triggers.rawValue: { Defaults.data(forKey: .appRunningTriggers) != nil },
            ModuleIdentifier.widgets.rawValue: { Defaults.bool(forKey: .widgetIconPublished) },
        ]
    }

    /// Thaw Scripts starts on when Thaw already had scripts to run:
    /// a global script in Thaw's settings or a script saved in any profile.
    static func automationHadScripts(globalHookData: [Data?], profileFiles: [Data]) -> Bool {
        if globalHookData.contains(where: { $0 != nil }) {
            return true
        }
        let decoder = JSONDecoder()
        return profileFiles.contains { data in
            (try? decoder.decode(ProfileScripts.self, from: data))?.automation.map { !$0.isEmpty } ?? false
        }
    }

    private struct ProfileScripts: Decodable {
        let automation: ProfileAutomation?
    }
}

/// What to do after a module quits unexpectedly.
nonisolated enum ModuleRestartDecision: Equatable, Sendable {
    case restart(after: TimeInterval)
    case stop
}

/// Restarts a crashed module with a doubling delay, and stops it once it
/// crashes too often in a short time.
nonisolated struct ModuleRestartPolicy: Sendable {
    var window: TimeInterval = 600
    var maxCrashes = 5
    var baseDelay: TimeInterval = 1
    var maxDelay: TimeInterval = 30

    func decision(crashes: [Date], now: Date) -> ModuleRestartDecision {
        let recent = crashes.filter { now.timeIntervalSince($0) <= window }.count
        guard recent < maxCrashes else { return .stop }
        let delay = baseDelay * pow(2, Double(max(recent - 1, 0)))
        return .restart(after: min(delay, maxDelay))
    }
}
