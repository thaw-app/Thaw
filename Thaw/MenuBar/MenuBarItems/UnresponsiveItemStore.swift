//
//  UnresponsiveItemStore.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - UnresponsiveItemStore

/// Remembers which menu bar items belong to owners that do not answer
/// synthetic events.
///
/// Moving or clicking an item requires its owning process to acknowledge
/// the events we post. An owner that is alive but not pumping its event
/// loop never does, so every attempt runs to its timeout and the item
/// visibly jitters while the cursor is warped back and forth. Little
/// Snitch is the recurring case — it ships with GUI Scripting disabled —
/// but any hung owner behaves the same way.
///
/// Retrying such an item is futile, and today the futility is rediscovered
/// on every attempt because nothing outlives the process. This store keeps
/// the verdict, so the second encounter costs one bounded attempt instead
/// of three.
///
/// The record is a hint, never a veto: a marked item is still attempted
/// once, and a single success clears it. That way an owner that starts
/// answering again — a relaunch, an update, a permission finally granted —
/// recovers on its own without the user having to know this list exists.
@MainActor
final class UnresponsiveItemStore {
    /// How long a record survives without being renewed.
    ///
    /// Long enough to span the reboots and app restarts that a user tries
    /// on their own, short enough that a stale verdict eventually lapses
    /// even if the item is never clicked again.
    private static let recordLifetime: TimeInterval = 60 * 60 * 24 * 14

    /// Diagnostic logger for the unresponsive item store.
    private static nonisolated let diagLog = DiagLog(category: "UnresponsiveItemStore")

    /// The last time each key was seen failing, keyed by ``persistenceKey(for:)``.
    private var lastFailureDates: [String: Date]

    init() {
        let stored = Defaults.dictionary(forKey: .unresponsiveMenuBarItems) as? [String: Double] ?? [:]
        let cutoff = Date.now.addingTimeInterval(-Self.recordLifetime)
        lastFailureDates = stored.compactMapValues { interval in
            let date = Date(timeIntervalSinceReferenceDate: interval)
            return date > cutoff ? date : nil
        }
        if lastFailureDates.count != stored.count {
            persist()
        }
    }

    /// A key that identifies the item's owner and role across relaunches.
    ///
    /// Window IDs and instance indices are reassigned every session, so
    /// only the namespace and title carry over. A UUID namespace is itself
    /// per-session, which leaves nothing stable to key on, so those items
    /// are not tracked at all rather than tracked under a key that will
    /// never match again.
    private static func persistenceKey(for tag: MenuBarItemTag) -> String? {
        guard case let .string(namespace) = tag.namespace else {
            return nil
        }
        return "\(namespace):\(tag.title)"
    }

    /// Whether the item's owner has recently failed to answer our events.
    ///
    /// Callers should use this to bound their effort, not to skip the item.
    func isUnresponsive(_ tag: MenuBarItemTag) -> Bool {
        guard let key = Self.persistenceKey(for: tag), let date = lastFailureDates[key] else {
            return false
        }
        guard date > Date.now.addingTimeInterval(-Self.recordLifetime) else {
            lastFailureDates[key] = nil
            persist()
            return false
        }
        return true
    }

    /// Records that the item's owner failed to answer, renewing its lifetime.
    func recordFailure(for tag: MenuBarItemTag) {
        guard let key = Self.persistenceKey(for: tag) else {
            return
        }
        let wasKnown = lastFailureDates[key] != nil
        lastFailureDates[key] = .now
        persist()
        if !wasKnown {
            Self.diagLog.info("Marked \(key) as unresponsive to synthetic events")
        }
    }

    /// Clears any record for the item, because its owner just answered.
    func recordSuccess(for tag: MenuBarItemTag) {
        guard let key = Self.persistenceKey(for: tag), lastFailureDates.removeValue(forKey: key) != nil else {
            return
        }
        persist()
        Self.diagLog.info("\(key) answered again; cleared unresponsive mark")
    }

    /// Forgets every record.
    func removeAll() {
        guard !lastFailureDates.isEmpty else {
            return
        }
        lastFailureDates.removeAll()
        persist()
    }

    private func persist() {
        if lastFailureDates.isEmpty {
            Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
        } else {
            Defaults.set(
                lastFailureDates.mapValues(\.timeIntervalSinceReferenceDate),
                forKey: .unresponsiveMenuBarItems
            )
        }
    }
}
