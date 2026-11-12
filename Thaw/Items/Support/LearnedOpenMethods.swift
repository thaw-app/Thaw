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
///
/// The real click moves the pointer, so it is learned only when it was needed for two opens of
/// the item in a row: a menu that opened from a press but wasn't seen, or one closed right away,
/// can't send the item to it.
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
        let current = stored[identity.key].flatMap { $0["version"] == identity.appVersion ? $0 : nil }
        if let entry = Self.entry(after: opened, current: current, appVersion: identity.appVersion) {
            guard stored[identity.key] != entry else { return }
            stored[identity.key] = entry
        } else {
            guard stored.removeValue(forKey: identity.key) != nil else { return }
        }
        defaults.set(stored, forKey: Self.defaultsKey)
    }

    /// The entry to keep after a left click: the method that opened the item, the real click only
    /// on its second open in a row, and nil when nothing opened it. The first real click keeps
    /// what was learned and marks it, so the next one can tell.
    static func entry(
        after opened: ConcealedItemOpenMethod?,
        current: [String: String]?,
        appVersion: String
    ) -> [String: String]? {
        guard let opened else { return nil }
        var entry = ["version": appVersion]
        guard opened == .revealAndClick else {
            entry["method"] = opened.rawValue
            return entry
        }
        if current?[realClickKey] != nil || current?["method"] == opened.rawValue {
            entry["method"] = opened.rawValue
        } else {
            entry["method"] = current?["method"]
        }
        entry[realClickKey] = "1"
        return entry
    }

    /// Marks an entry whose last open needed the real click.
    private static let realClickKey = "neededRealClick"

    private func stored() -> [String: [String: String]] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String: String]] ?? [:]
    }
}
