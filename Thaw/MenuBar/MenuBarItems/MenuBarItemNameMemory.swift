//
//  MenuBarItemNameMemory.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The name each menu bar item last resolved to, remembered across launches.
///
/// Naming an item requires knowing which process created it, and as of
/// macOS 26 that takes an Accessibility scan the app deliberately does not
/// wait for: the first cache pass runs without source-PID resolution so the
/// bar is usable immediately, and a second pass upgrades the items once the
/// scan lands. Between the two — about three seconds in the log attached to
/// #956 — every item answers to the generic "Menu Bar Item", which is what
/// the user sees on hover and in the search panel.
///
/// The name an item resolved to last time is almost always the name it will
/// resolve to this time, so remembering it closes that window. This is a
/// display fallback only: it never feeds identity, movability, or layout
/// decisions, all of which continue to wait for the real source PID.
///
/// Not every item may be remembered — see ``isEligible(_:)``. A confidently
/// wrong name is worse than a generic one, because the user acts on it.
///
/// `nonisolated` because `MenuBarItem/autoDetectedName` is, and it reads
/// user defaults directly for the same reason `MenuBarItem/customName`
/// does: the values are already resident, and threading a store through
/// every naming site would isolate a property that has never been isolated.
nonisolated enum MenuBarItemNameMemory {
    /// The largest number of remembered names kept.
    ///
    /// Names are cheap and a name for an item that no longer exists is never
    /// read, so this exists only to bound growth across years of installing
    /// and removing menu bar apps. A typical bar holds ~25 items.
    private static let capacity = 512

    /// Whether an item's name may be remembered and restored.
    ///
    /// Two kinds of item are refused:
    ///
    /// - Items with a UUID namespace, which macOS reassigns every session.
    ///   Their key cannot match after a relaunch, so storing one only grows
    ///   the dictionary. This mirrors `MenuBarItemFailureLedger`.
    /// - Control Center's generic `Item-N` slots. Their key encodes a
    ///   position in Control Center's hosting order, not an identity: which
    ///   slot is `Item-0` versus `Item-0:9` depends on which agents launched
    ///   this boot and in what order. Restoring a name onto one would
    ///   eventually label Adobe's icon "Docker" — and unlike a generic
    ///   label, a wrong one gets clicked. These are exactly the items that
    ///   `MenuBarItem/immovabilityReason` already parks as
    ///   `unresolvedControlCenterPlaceholder` until their real owner is
    ///   known, for the same reason.
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
    /// Items whose source process has not resolved are skipped rather than
    /// stored: their name is the generic fallback this type exists to avoid
    /// showing, and writing it back would make the memory self-defeating.
    /// The test is the running application rather than the source PID,
    /// because that is precisely the condition under which
    /// `MenuBarItem/autoDetectedName` takes its resolved path — a PID whose
    /// process has since exited would otherwise store the fallback.
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
            // Keep the names of items that are on the bar right now; the
            // overflow is necessarily made up of items that are not.
            let live = Set(items.map { key(for: $0) })
            names = names.filter { live.contains($0.key) }
        }

        guard names != before else {
            return
        }
        Defaults.set(names, forKey: .menuBarItemResolvedNames)
    }

    /// The key an item's name is stored under.
    ///
    /// Derived exactly as `MenuBarItemFailureLedger` derives its own, so the
    /// two stores agree on what counts as the same item across launches.
    private static func key(for item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }
}
