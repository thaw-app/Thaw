//
//  SavedScripts.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Every script the user chose: one before and one after any switch, and a
/// pair for each profile.
public struct HookConfiguration: Codable, Equatable, Sendable {
    public var globalPreHook: HookScript?
    public var globalPostHook: HookScript?
    public var profileHooks: [UUID: ProfileAutomation]

    /// A configuration with the given scripts, none by default.
    public init(
        globalPreHook: HookScript? = nil,
        globalPostHook: HookScript? = nil,
        profileHooks: [UUID: ProfileAutomation] = [:]
    ) {
        self.globalPreHook = globalPreHook
        self.globalPostHook = globalPostHook
        self.profileHooks = profileHooks
    }
}

/// Where the Scripts module saves its scripts, so Thaw can export or copy a
/// profile with the scripts the user has now, not the ones its file carried.
public enum SavedScripts {
    public static let configurationKey = "HookConfiguration"
    /// The profiles whose scripts the module has taken from their files.
    public static let knownProfilesKey = "KnownProfileIDs"

    /// The Scripts module's defaults domain for a Thaw, as in com.example.Thaw.module.automation.
    public static func domain(hostBundleIdentifier: String) -> String {
        hostBundleIdentifier + ModuleLaunchEnvironment.moduleBundleSeparator + ModuleIdentifier.scripts.rawValue
    }

    /// A profile's scripts as the user has them now. Once the module has taken a profile
    /// over, its copy is the one that runs; before that, the file's scripts are.
    public static func automation(
        forProfileID id: UUID,
        inFile fileAutomation: ProfileAutomation?,
        moduleDefaults defaults: UserDefaults?
    ) -> ProfileAutomation? {
        guard let defaults, defaults.stringArray(forKey: knownProfilesKey)?.contains(id.uuidString) == true
        else {
            return fileAutomation
        }
        let configuration = defaults.data(forKey: configurationKey)
            .flatMap { try? JSONDecoder().decode(HookConfiguration.self, from: $0) }
        return configuration?.profileHooks[id]
    }
}
