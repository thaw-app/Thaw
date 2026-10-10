//
//  MenuBarItemManager+OpenMethods.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Apps differ in which concealed-menu methods they answer.
/// Moving beside Thaw is unsafe: the agent refuses the concealed move back, stranding the item.
nonisolated enum ConcealedItemOpenMethod: String, CaseIterable, Sendable {
    /// Accessibility press on the parked item. Nothing appears in the bar.
    case pressInPlace
    /// Reveal the item where it sits and click it there.
    case revealInPlace
}

extension MenuBarItemManager {
    private static let learnedOpenMethodsKey = "MenuBarItemManager.learnedOpenMethods"

    /// App updates can change responses, so learned methods are version-specific.
    struct OpenMethodIdentity: Equatable {
        let key: String
        let appVersion: String
    }

    /// Try the learned method first, then the cheapest; right clicks skip press because it opens the default action.
    /// showInMenuBar overrides learning to reveal first, falling back to press if the click fails.
    static nonisolated func openMethodOrder(
        for mouseButton: CGMouseButton,
        learned: ConcealedItemOpenMethod?,
        showInMenuBar: Bool = false
    ) -> [ConcealedItemOpenMethod] {
        if mouseButton == .right {
            return [.revealInPlace]
        }
        if showInMenuBar {
            return [.revealInPlace, .pressInPlace]
        }
        let candidates: [ConcealedItemOpenMethod] = [.pressInPlace, .revealInPlace]
        guard let learned else { return candidates }
        return [learned] + candidates.filter { $0 != learned }
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
