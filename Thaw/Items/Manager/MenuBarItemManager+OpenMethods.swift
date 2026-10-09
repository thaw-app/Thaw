//
//  MenuBarItemManager+OpenMethods.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

extension MenuBarItemManager {
    private static let learnedOpenMethodsKey = "MenuBarItemManager.learnedOpenMethods"

    /// App updates can change responses, so learned methods are version-specific.
    struct OpenMethodIdentity: Equatable {
        let key: String
        let appVersion: String
    }

    func openMethodIdentity(for item: MenuBarItem) -> OpenMethodIdentity {
        let bundleURL = NSRunningApplication(processIdentifier: resolvedPID(for: item))?.bundleURL
        let version = bundleURL
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleVersion"] as? String } ?? ""
        return OpenMethodIdentity(
            key: MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier),
            appVersion: version
        )
    }

    func learnedOpenMethod(for identity: OpenMethodIdentity) -> ConcealedItemOpenMethod? {
        guard let entry = Self.storedOpenMethods()[identity.key],
              entry["version"] == identity.appVersion
        else {
            return nil
        }
        return entry["method"].flatMap(ConcealedItemOpenMethod.init(rawValue:))
    }

    func rememberOpenMethod(_ method: ConcealedItemOpenMethod, for identity: OpenMethodIdentity) {
        var stored = Self.storedOpenMethods()
        let entry = ["method": method.rawValue, "version": identity.appVersion]
        guard stored[identity.key] != entry else { return }
        stored[identity.key] = entry
        UserDefaults.standard.set(stored, forKey: Self.learnedOpenMethodsKey)
    }

    func forgetOpenMethod(for identity: OpenMethodIdentity) {
        var stored = Self.storedOpenMethods()
        guard stored.removeValue(forKey: identity.key) != nil else { return }
        UserDefaults.standard.set(stored, forKey: Self.learnedOpenMethodsKey)
    }

    private static func storedOpenMethods() -> [String: [String: String]] {
        UserDefaults.standard.dictionary(forKey: learnedOpenMethodsKey) as? [String: [String: String]] ?? [:]
    }
}
