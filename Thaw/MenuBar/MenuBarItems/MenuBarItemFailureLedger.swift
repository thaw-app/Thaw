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
///   cursor is warped back and forth. The recurring case is an owner that
///   ships with GUI Scripting disabled, but any hung owner behaves the same
///   way. Only that kind of failure counts here, and the answer
///   outlives the process, because otherwise the futility is rediscovered
///   from scratch on every launch.
///
/// A third, related verdict is `cannotComplete`: a move that keeps returning
/// `kAXErrorCannotComplete` will keep returning it. On macOS 27 this is the
/// post-restriction repair path — after the Assessment Mode assertion reflows
/// the bar, restoring a displaced visible item can hit this wall for items
/// that simply cannot be moved. It is *not* the owner's fault (unlike an
/// unresponsive owner), so it earns a separate persisted verdict rather than
/// contaminating the unresponsive-owner marks.
///
/// Keeping all of this in one ledger is deliberate. The verdicts share a
/// subject, a key, and — most importantly — a clearing rule: one success means
/// the item is fine, and every answer must forget it at the same instant.
/// Split across separate stores, that invariant is one missed call away from
/// breaking.
///
/// A version stamp guards the persisted verdicts: on a Thaw or OS build change
/// the marks are dropped, so a fix that makes a previously stuck item movable
/// is not hidden behind a two-week TTL.
///
/// No answer is ever a veto. A backed-off item is skipped by bulk apply but
/// still moves when the user asks for it directly, and a marked item is still
/// attempted — just not retried. That way an owner that starts answering again
/// — a relaunch, an update, a permission finally granted — recovers on its
/// own, with no user action and no UI it would have to discover.
@MainActor
final class MenuBarItemFailureLedger {
    /// Why an operation failed, as far as this ledger cares.
    enum FailureKind {
        /// The owner never acknowledged our events.
        case unresponsiveOwner
        /// A move repeatedly returned `kAXErrorCannotComplete`. The catch-all
        /// AX failure, so it does not blame the owner — but an item that keeps
        /// returning it will not move, and earns its own persisted verdict.
        case cannotComplete
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

    /// The build string persisted marks are valid for; a change drops them.
    private static var currentBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// Owner bundle identifiers shipped as known-unmovable: their items return
    /// `cannotComplete` on every install, so there is no reason to re-discover
    /// that per user. These
    /// short-circuit the effort budget the way a learned mark does, but are not
    /// persisted and are never cleared by a success — a shipped fact, not an
    /// observation. Seed list; populate from confirmed reports.
    private static let shippedUnmovableOwners: Set<String> = [
        // Add confirmed always-`cannotComplete` owner bundle identifiers here.
    ]

    /// How long a failed item stays excluded from bulk-apply moves.
    /// Grows linearly with consecutive failures, capped at 5 minutes.
    nonisolated static func backoffInterval(failureCount: Int) -> Duration {
        .seconds(min(30 * max(failureCount, 1), 300))
    }

    /// Session-scoped failure history driving the backoff window.
    private var backoffHistory = [String: (count: Int, lastFailure: ContinuousClock.Instant)]()

    /// When each marked key was last seen failing as an unresponsive owner.
    private var markDates: [String: Date]

    /// When each key was last seen failing with `cannotComplete` often enough
    /// to be treated as unmovable. Persisted separately from `markDates` so the
    /// two verdicts never contaminate each other, but cleared together.
    private var cannotCompleteDates: [String: Date]

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
    /// behaviour this ledger exists to remember. Kept per kind so a single
    /// failure of one kind never counts toward the other.
    private var provisionalMarks = Set<String>()
    private var provisionalCannotComplete = Set<String>()

    init() {
        let cutoff = Date.now.addingTimeInterval(-Self.markLifetime)
        let versionChanged = Defaults.string(forKey: .menuBarFailureLedgerVersion) != Self.currentBuildVersion

        func load(_ key: Defaults.Key) -> (marks: [String: Date], stored: Int) {
            let stored = Defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
            guard !versionChanged else {
                return ([:], stored.count)
            }
            let marks = stored.compactMapValues { interval -> Date? in
                let date = Date(timeIntervalSinceReferenceDate: interval)
                return date > cutoff ? date : nil
            }
            return (marks, stored.count)
        }

        let unresponsive = load(.unresponsiveMenuBarItems)
        let cannot = load(.cannotCompleteMenuBarItems)
        markDates = unresponsive.marks
        cannotCompleteDates = cannot.marks

        if versionChanged {
            Self.diagLog.info("build changed; dropping persisted failure marks")
        }
        if versionChanged
            || markDates.count != unresponsive.stored
            || cannotCompleteDates.count != cannot.stored {
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

    // MARK: Persisted verdicts

    /// Whether the item's owner has a standing record of ignoring our events.
    ///
    /// Callers should use this to bound their effort, not to skip the item.
    func isUnresponsive(_ item: MenuBarItem) -> Bool {
        isMarked(item, in: \.markDates)
    }

    /// Whether the item has a standing record of returning `cannotComplete`.
    ///
    /// Callers should use this to bound their effort (e.g. skip re-attempting
    /// the post-restriction repair), not as a veto — a direct user move still
    /// tries.
    func cannotCompleteMarked(_ item: MenuBarItem) -> Bool {
        if let bundleID = item.sourceApplication?.bundleIdentifier ?? item.owningApplication?.bundleIdentifier,
           Self.shippedUnmovableOwners.contains(bundleID) {
            return true
        }
        return isMarked(item, in: \.cannotCompleteDates)
    }

    private func isMarked(
        _ item: MenuBarItem,
        in dates: ReferenceWritableKeyPath<MenuBarItemFailureLedger, [String: Date]>
    ) -> Bool {
        let key = Self.key(for: item)
        guard let date = self[keyPath: dates][key] else {
            return false
        }
        guard date > Date.now.addingTimeInterval(-Self.markLifetime) else {
            self[keyPath: dates][key] = nil
            persist()
            return false
        }
        return true
    }

    // MARK: Recording

    /// Records a failed operation.
    ///
    /// Every failure extends the backoff window. Only an unresponsive owner or
    /// a `cannotComplete` can earn a persisted mark, and only on the second
    /// such failure, and only for an item with a launch-stable key.
    func recordFailure(
        for item: MenuBarItem,
        kind: FailureKind,
        now: ContinuousClock.Instant = .now
    ) {
        let key = Self.key(for: item)
        backoffHistory[key] = (count: (backoffHistory[key]?.count ?? 0) + 1, lastFailure: now)

        guard Self.isStableAcrossLaunches(item) else {
            return
        }
        switch kind {
        case .unresponsiveOwner:
            let result = Self.mark(key, in: &markDates, provisional: &provisionalMarks)
            persistMark(result, key: key, label: "unresponsive to synthetic events")
        case .cannotComplete:
            let result = Self.mark(key, in: &cannotCompleteDates, provisional: &provisionalCannotComplete)
            persistMark(result, key: key, label: "unmovable (cannotComplete)")
        case .other:
            break
        }
    }

    /// Applies the two-strike rule: a lone failure is only provisional; a
    /// second promotes it to a persisted, dated mark.
    private static func mark(
        _ key: String,
        in dates: inout [String: Date],
        provisional: inout Set<String>
    ) -> Bool? {
        let wasMarked = dates[key] != nil
        guard wasMarked || !provisional.insert(key).inserted else {
            Self.diagLog.debug("\(key) failed once; waiting for a second failure before marking it")
            return nil
        }
        dates[key] = .now
        return !wasMarked
    }

    /// Persists only after the `inout` access in `mark` has ended. Calling
    /// `persist()` from inside that access reads both dictionaries and trips
    /// Swift's exclusivity enforcement in Xcode 27 beta 4.
    private func persistMark(
        _ newlyMarked: Bool?,
        key: String,
        label: String
    ) {
        guard let newlyMarked else {
            return
        }
        persist()
        if newlyMarked {
            Self.diagLog.info("Marked \(key) as \(label)")
        }
    }

    /// Records a successful operation, clearing every record for the item.
    ///
    /// One success is enough for all of them. An item that just worked is
    /// not backed off, not provisionally suspect, not unresponsive, and not
    /// unmovable.
    func recordSuccess(for item: MenuBarItem) {
        let key = Self.key(for: item)
        backoffHistory.removeValue(forKey: key)
        provisionalMarks.remove(key)
        provisionalCannotComplete.remove(key)
        let hadUnresponsive = markDates.removeValue(forKey: key) != nil
        let hadCannotComplete = cannotCompleteDates.removeValue(forKey: key) != nil
        guard hadUnresponsive || hadCannotComplete else {
            return
        }
        persist()
        Self.diagLog.info("\(key) answered again; cleared failure marks")
    }

    /// Forgets everything.
    func removeAll() {
        backoffHistory.removeAll()
        provisionalMarks.removeAll()
        provisionalCannotComplete.removeAll()
        guard !markDates.isEmpty || !cannotCompleteDates.isEmpty else {
            return
        }
        markDates.removeAll()
        cannotCompleteDates.removeAll()
        persist()
    }

    private func persist() {
        func store(_ dates: [String: Date], forKey key: Defaults.Key) {
            if dates.isEmpty {
                Defaults.removeObject(forKey: key)
            } else {
                Defaults.set(dates.mapValues(\.timeIntervalSinceReferenceDate), forKey: key)
            }
        }
        store(markDates, forKey: .unresponsiveMenuBarItems)
        store(cannotCompleteDates, forKey: .cannotCompleteMenuBarItems)
        Defaults.set(Self.currentBuildVersion, forKey: .menuBarFailureLedgerVersion)
    }
}
