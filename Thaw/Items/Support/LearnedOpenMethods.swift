//
//  LearnedOpenMethods.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// App updates can change responses, so learned methods are version-specific.
nonisolated struct OpenMethodIdentity: Equatable {
    let key: String
    let appVersion: String
}

/// The concealed-click method that last opened each item, kept in defaults.
nonisolated struct LearnedOpenMethods {
    static let defaultsKey = "MenuBarItemManager.learnedOpenMethods"
    static var standard: LearnedOpenMethods {
        LearnedOpenMethods(defaults: .standard)
    }

    let defaults: UserDefaults

    func method(for identity: OpenMethodIdentity) -> ConcealedItemOpenMethod? {
        guard let entry = stored()[identity.key], entry["version"] == identity.appVersion else { return nil }
        return entry["method"].flatMap(ConcealedItemOpenMethod.init(rawValue:))
    }

    /// Remembers the method that opened the item, or forgets the item when nothing did.
    /// Right clicks try a fixed order, so they neither teach nor forget the left-click method.
    func record(_ opened: ConcealedItemOpenMethod?, for identity: OpenMethodIdentity, clickedWith button: CGMouseButton) {
        guard button != .right else { return }
        var stored = stored()
        if let opened {
            let entry = ["method": opened.rawValue, "version": identity.appVersion]
            guard stored[identity.key] != entry else { return }
            stored[identity.key] = entry
        } else {
            guard stored.removeValue(forKey: identity.key) != nil else { return }
        }
        defaults.set(stored, forKey: Self.defaultsKey)
    }

    private func stored() -> [String: [String: String]] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String: String]] ?? [:]
    }
}
