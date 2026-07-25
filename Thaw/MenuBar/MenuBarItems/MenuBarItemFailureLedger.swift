//
//  MenuBarItemFailureLedger.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

// MARK: - MenuBarItemFailureLedger

/// The single record of which menu bar items have been failing us, and how.
///
/// Two questions get asked about a failing item, and they are not the same
/// question:
///
/// - *Should the next bulk apply skip it?* One persistently unmovable item
///   — a vanished transient Control Center window, an item whose app hangs
///   — must not re-trigger a full cursor-hijacking apply loop on every
///   cache cycle (#736). Any move failure counts here, and the answer
///   expires on a timer that grows with the failure count.
/// - *Should a single operation stop retrying it?* Moving or clicking an
///   item requires its owner to acknowledge the events we post. An owner
///   that is alive but not pumping its event loop never does, so every
///   attempt runs to its timeout and the item visibly jitters while the
///   cursor is warped back and forth. Little Snitch is the recurring case
///   — it ships with GUI Scripting disabled — but any hung owner behaves
///   the same way. Only that kind of failure counts here, and the answer
///   outlives the process, because otherwise the futility is rediscovered
///   from scratch on every launch.
///
/// Keeping both in one ledger is deliberate. They share a subject, a key,
/// and — most importantly — a clearing rule: one success means the item is
/// fine, and both answers must forget it at the same instant. Split across
/// two stores, that invariant is one missed call away from breaking.
///
/// Neither answer is ever a veto. A backed-off item is skipped by bulk
/// apply but still moves when the user asks for it directly, and a marked
/// item is still attempted — just not retried. That way an owner that
/// starts answering again — a relaunch, an update, a permission finally
/// granted — recovers on its own, with no user action and no UI it would
/// have to discover.
@MainActor
final class MenuBarItemFailureLedger {
    /// Why an operation failed, as far as this ledger cares.
    enum FailureKind {
        /// The owner never acknowledged our events.
        case unresponsiveOwner
        /// Anything else: the item vanished, the move did not land, the
        /// event source could not be created.
        case other
    }

    /// How long a persisted mark survives without being renewed.
    ///
    /// Long enough to span the reboots and app restarts a user tries on
    /// their own, short enough that a stale verdict eventually lapses even
    /// if the item is never touched again.
    private static let markLifetime: TimeInterval = 60 * 60 * 24 * 14

    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemFailureLedger")

    /// How long a failed item stays excluded from bulk-apply moves.
    /// Grows linearly with consecutive failures, capped at 5 minutes.
    nonisolated static func backoffInterval(failureCount: Int) -> Duration {
        .seconds(min(30 * max(failureCount, 1), 300))
    }

    /// Session-scoped failure history driving the backoff window.
    private var backoffHistory = [String: (count: Int, lastFailure: ContinuousClock.Instant)]()

    /// When each marked key was last seen failing as an unresponsive owner.
    private var markDates: [String: Date]

    /// Keys that have failed once in this session but are not marked yet.
    ///
    /// A single failure is not evidence. Event operations can time out for
    /// reasons that have nothing to do with the owner — contention on the
    /// event semaphore is the obvious one — and a mark earned that way
    /// would stand for two weeks against an app that was never at fault.
    /// Requiring a second failure costs the pathological case nothing,
    /// since an owner that never answers reaches two within the same
    /// session.
    ///
    /// Deliberately not persisted: a lone failure per session is not the
    /// behaviour this ledger exists to remember.
    private var provisionalMarks = Set<String>()

    init() {
        let stored = Defaults.dictionary(forKey: .unresponsiveMenuBarItems) as? [String: Double] ?? [:]
        let cutoff = Date.now.addingTimeInterval(-Self.markLifetime)
        markDates = stored.compactMapValues { interval in
            let date = Date(timeIntervalSinceReferenceDate: interval)
            return date > cutoff ? date : nil
        }
        if markDates.count != stored.count {
            persist()
        }
    }

    // MARK: Keys

    /// The key an item is filed under.
    ///
    /// `uniqueIdentifier` is already the codebase's convention for
    /// identifying an item across relaunches — it is what custom names are
    /// stored against — so this ledger uses it rather than inventing a
    /// second scheme that would drift from it.
    private static func key(for item: MenuBarItem) -> String {
        item.uniqueIdentifier
    }

    /// Whether an item's key means anything after a relaunch.
    ///
    /// A UUID namespace is reassigned every session, which leaves nothing
    /// stable to key on. Such items still get session backoff, but are
    /// never persisted under a key that could never match again.
    private static func isStableAcrossLaunches(_ item: MenuBarItem) -> Bool {
        if case .string = item.tag.namespace {
            return true
        }
        return false
    }

    // MARK: Bulk-apply backoff

    /// Whether the bulk-apply loops should skip the item because it failed
    /// recently and is still inside its backoff window.
    ///
    /// Takes a key rather than an item because the apply loops decide
    /// whether to skip before they resolve the item, and resolving one just
    /// to answer this would undo the saving.
    ///
    /// - Parameter key: The item's `uniqueIdentifier`.
    func isUnderBackoff(key: String, now: ContinuousClock.Instant = .now) -> Bool {
        guard let entry = backoffHistory[key] else {
            return false
        }
        return now - entry.lastFailure < Self.backoffInterval(failureCount: entry.count)
    }

    // MARK: Unresponsive-owner mark

    /// Whether the item's owner has a standing record of ignoring our events.
    ///
    /// Callers should use this to bound their effort, not to skip the item.
    func isUnresponsive(_ item: MenuBarItem) -> Bool {
        let key = Self.key(for: item)
        guard let date = markDates[key] else {
            return false
        }
        guard date > Date.now.addingTimeInterval(-Self.markLifetime) else {
            markDates[key] = nil
            persist()
            return false
        }
        return true
    }

    // MARK: Recording

    /// Records a failed operation.
    ///
    /// Every failure extends the backoff window. Only an unresponsive owner
    /// can earn a persisted mark, and only on its second such failure.
    func recordFailure(
        for item: MenuBarItem,
        kind: FailureKind,
        now: ContinuousClock.Instant = .now
    ) {
        let key = Self.key(for: item)
        backoffHistory[key] = (count: (backoffHistory[key]?.count ?? 0) + 1, lastFailure: now)

        guard kind == .unresponsiveOwner, Self.isStableAcrossLaunches(item) else {
            return
        }
        let wasMarked = markDates[key] != nil
        guard wasMarked || !provisionalMarks.insert(key).inserted else {
            Self.diagLog.debug("\(key) failed once; waiting for a second failure before marking it")
            return
        }
        markDates[key] = .now
        persist()
        if !wasMarked {
            Self.diagLog.info("Marked \(key) as unresponsive to synthetic events")
        }
    }

    /// Records a successful operation, clearing every record for the item.
    ///
    /// One success is enough for all of them. An item that just worked is
    /// not backed off, not provisionally suspect, and not unresponsive.
    func recordSuccess(for item: MenuBarItem) {
        let key = Self.key(for: item)
        backoffHistory.removeValue(forKey: key)
        provisionalMarks.remove(key)
        guard markDates.removeValue(forKey: key) != nil else {
            return
        }
        persist()
        Self.diagLog.info("\(key) answered again; cleared unresponsive mark")
    }

    /// Forgets everything.
    func removeAll() {
        backoffHistory.removeAll()
        provisionalMarks.removeAll()
        guard !markDates.isEmpty else {
            return
        }
        markDates.removeAll()
        persist()
    }

    private func persist() {
        if markDates.isEmpty {
            Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
        } else {
            Defaults.set(
                markDates.mapValues(\.timeIntervalSinceReferenceDate),
                forKey: .unresponsiveMenuBarItems
            )
        }
    }
}
