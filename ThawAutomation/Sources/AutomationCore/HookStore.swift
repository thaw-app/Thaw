//
//  HookStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation
import ThawModuleKit

/// Every script the user chose: one before and one after any switch, and a
/// pair for each profile.
public struct HookConfiguration: Codable, Equatable, Sendable {
    public var globalPreHook: HookScript?
    public var globalPostHook: HookScript?
    public var profileHooks: [UUID: ProfileAutomation]

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

/// Keeps the module's scripts in its own defaults, and takes over the
/// scripts Thaw stored before they moved into the module.
@MainActor
@Observable
public final class HookStore {
    /// The keys Thaw stored its global scripts under.
    public static let thawGlobalPreKey = "GlobalPreProfileHook"
    public static let thawGlobalPostKey = "GlobalPostProfileHook"

    private enum Key {
        static let configuration = "HookConfiguration"
        static let importedGlobals = "ImportedThawGlobalHooks"
        static let knownProfiles = "KnownProfileIDs"
    }

    public private(set) var configuration: HookConfiguration

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        configuration = defaults.data(forKey: Key.configuration)
            .flatMap { try? JSONDecoder().decode(HookConfiguration.self, from: $0) } ?? HookConfiguration()
    }

    public func update(_ change: (inout HookConfiguration) -> Void) {
        change(&configuration)
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Key.configuration)
        }
    }

    /// Takes Thaw's global scripts the first time, and the scripts of every
    /// profile the module hasn't seen before. A profile imported from a file
    /// later still brings its scripts, which Thaw already switched off.
    public func importFromThaw(hostDefaults: UserDefaults?, catalog: ProfileCatalog) {
        let decoder = JSONDecoder()
        let globalHook: (String) -> HookScript? = { key in
            hostDefaults?.data(forKey: key).flatMap { try? decoder.decode(HookScript.self, from: $0) }
        }
        let importsGlobals = !defaults.bool(forKey: Key.importedGlobals)
        var known = Set(defaults.stringArray(forKey: Key.knownProfiles) ?? [])
        let unseen = catalog.profiles().filter { !known.contains($0.id.uuidString) }

        update { configuration in
            if importsGlobals {
                configuration.globalPreHook = configuration.globalPreHook ?? globalHook(Self.thawGlobalPreKey)
                configuration.globalPostHook = configuration.globalPostHook ?? globalHook(Self.thawGlobalPostKey)
            }
            for profile in unseen {
                if let automation = catalog.automation(forProfileID: profile.id) {
                    configuration.profileHooks[profile.id] = automation
                }
            }
        }
        defaults.set(true, forKey: Key.importedGlobals)
        known.formUnion(unseen.map(\.id.uuidString))
        defaults.set(known.sorted(), forKey: Key.knownProfiles)
    }
}
