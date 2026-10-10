//
//  MenuBarItemNameMemory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The name each menu bar item last resolved to, remembered across launches.
///
/// On macOS 26, naming an item needs the source-PID Accessibility scan, and
/// until it lands (about three seconds) every item reads "Menu Bar Item".
/// The remembered name covers that gap. Display only: identity, movability,
/// and layout still wait for the real source PID.
///
/// A wrong name is worse than a generic one; see ``isEligible(_:)``.
///
/// `nonisolated` to match `MenuBarItem/autoDetectedName`, and reads user
/// defaults directly as `MenuBarItem/customName` does.
nonisolated enum MenuBarItemNameMemory {
    /// Only bounds growth over years of installs; a typical bar has ~25 items.
    private static let capacity = 512

    /// Whether an item's name may be remembered and restored.
    ///
    /// Refuses:
    ///
    /// - UUID namespaces, which macOS reassigns every session.
    /// - Control Center's `Item-N` slots, whose key reflects this boot's
    ///   agent launch order, not an identity. A restored name could label
    ///   one app's icon with another's.
    static func isEligible(_ item: MenuBarItem) -> Bool {
        guard case .string = item.tag.namespace else {
            return false
        }
        return !item.tag.isControlCenterGenericItem && !item.isControlItem
    }

    /// The name the item resolved to on an earlier pass or launch, or `nil`
    /// when nothing was remembered for it.
    static func rememberedName(for item: MenuBarItem) -> String? {
        guard isEligible(item) else {
            return nil
        }
        let names = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        return names[key(for: item)]
    }

    /// Records the resolved name of every item that has one.
    ///
    /// Skips items without a running source application, whose name is the
    /// generic fallback. Checks the app rather than the PID because that's
    /// what `MenuBarItem/autoDetectedName` checks.
    static func remember(_ items: [MenuBarItem]) {
        var names = Defaults.dictionary(forKey: .menuBarItemResolvedNames) as? [String: String] ?? [:]
        let before = names

        for item in items where item.sourceApplication != nil && isEligible(item) {
            let name = item.autoDetectedName
            guard !name.isEmpty else {
                continue
            }
            names[key(for: item)] = name
        }

        if names.count > capacity {
            // Keep the names of items on the bar right now.
            let live = Set(items.map { key(for: $0) })
            names = names.filter { live.contains($0.key) }
        }

        guard names != before else {
            return
        }
        Defaults.set(names, forKey: .menuBarItemResolvedNames)
    }

    /// Derived exactly as `MenuBarItemFailureLedger` derives its key, so both
    /// agree on what counts as the same item.
    private static func key(for item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }
}
