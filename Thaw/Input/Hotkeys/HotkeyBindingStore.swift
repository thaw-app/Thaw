//
//  HotkeyBindingStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import ThawUI

/// One defaults dictionary of saved shortcuts: each value a JSON-encoded KeyCombination,
/// keyed by action, profile ID or item identifier.
nonisolated struct HotkeyBindingStore {
    let key: Defaults.Key
    /// A store to use in place of the app's; nil follows Defaults.store, also when that is swapped later.
    var defaults: UserDefaults?

    private var store: UserDefaults {
        defaults ?? Defaults.store
    }

    /// Shortcuts for the built-in actions, keyed by HotkeyAction raw value.
    static var actions: HotkeyBindingStore { HotkeyBindingStore(key: .hotkeys) }
    /// The shortcut that applies each profile, keyed by profile ID.
    static var profiles: HotkeyBindingStore { HotkeyBindingStore(key: .profileHotkeys) }
    /// The shortcut that opens each menu bar item, keyed by item identifier.
    static var items: HotkeyBindingStore { HotkeyBindingStore(key: .menuBarItemHotkeys) }

    /// Every saved binding, still encoded.
    func rawBindings() -> [String: Data] {
        store.dictionary(forKey: key.rawValue) as? [String: Data] ?? [:]
    }

    /// Replaces every saved binding.
    func setRawBindings(_ bindings: [String: Data]) {
        store.set(bindings, forKey: key.rawValue)
    }

    /// The combination an encoded binding holds; nil for a stored JSON null.
    static func combination(from data: Data) throws -> KeyCombination? {
        try JSONDecoder().decode(KeyCombination?.self, from: data)
    }

    /// Saves one binding. A cleared binding removes its key; encoding the optional would store a dead JSON null.
    func set(_ combination: KeyCombination?, for identifier: String) throws {
        let data = try combination.map { try JSONEncoder().encode($0) }
        var bindings = store.dictionary(forKey: key.rawValue) ?? [:]
        bindings[identifier] = data
        store.set(bindings, forKey: key.rawValue)
    }
}
