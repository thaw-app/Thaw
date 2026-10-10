//
//  MenuBarItemFailureLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

// MARK: - MenuBarItemFailureLedger

/// Persists retry limits for unresponsive owners, cannotComplete moves and stranded boundary repairs to avoid repeated timeouts and neighbour churn.
/// Direct user requests still try; one success clears all verdicts, and build changes invalidate marks.
@MainActor
final class MenuBarItemFailureLedger {
    /// Why an operation failed, as far as this ledger cares.
    enum FailureKind {
        /// The owner never acknowledged events, as with GUI Scripting disabled or a hung app.
        case unresponsiveOwner
        /// Repeated kAXErrorCannotComplete moves, including macOS 27 post-restriction repairs, do not imply owner failure.
        case cannotComplete
        /// Other failures, such as a vanished item, missed move or unavailable event source.
        case other
    }

    /// Marks span reboots and app restarts but eventually lapse even without another attempt.
    private static let markLifetime: TimeInterval = 60 * 60 * 24 * 14

    /// How long a stranded verdict survives. Short, because the bar it was
    /// earned on changes as apps come and go.
    private static let strandLifetime: TimeInterval = 60 * 60 * 24

    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemFailureLedger")

    /// The build string persisted marks are valid for; a change drops them.
    private static var currentBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// Confirmed always-cannotComplete owners bound effort without per-user rediscovery.
    /// These shipped marks are neither persisted nor cleared by success.
    private static let shippedUnmovableOwners: Set<String> = [
        // Add confirmed always-cannotComplete owner bundle identifiers here.
    ]

    /// When each marked key was last seen failing as an unresponsive owner.
    private var markDates: [String: Date]

    /// Persist cannotComplete verdicts separately from owner failures, but clear both on success.
    private var cannotCompleteDates: [String: Date]

    /// When each key last tripped the visible-boundary repair's breaker.
    private var strandedDates: [String: Date]

    /// Require two same-kind failures per session; a lone timeout may be event-semaphore contention, not a hung owner.
    /// Provisional failures are not persisted or counted across kinds.
    private var provisionalMarks = Set<String>()
    private var provisionalCannotComplete = Set<String>()

    init() {
        let cutoff = Date.now.addingTimeInterval(-Self.markLifetime)
        let versionChanged = Defaults.string(forKey: .menuBarFailureLedgerVersion) != Self.currentBuildVersion

        func load(_ key: Defaults.Key, cutoff: Date = cutoff) -> (marks: [String: Date], stored: Int) {
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
        let stranded = load(.strandedMenuBarItems, cutoff: Date.now.addingTimeInterval(-Self.strandLifetime))
        markDates = unresponsive.marks
        cannotCompleteDates = cannot.marks
        strandedDates = stranded.marks

        if versionChanged {
            Self.diagLog.info("build changed; dropping persisted failure marks")
        }
        if versionChanged
            || markDates.count != unresponsive.stored
            || cannotCompleteDates.count != cannot.stored
            || strandedDates.count != stranded.stored
        {
            persist()
        }
    }

    // MARK: Keys

    /// Uses the same relaunch-stable identity as custom names.
    private static func key(for item: MenuBarItem) -> String {
        item.uniqueIdentifier
    }

    /// UUID namespaces change every session, so their failure keys must not be persisted.
    private static func isStableAcrossLaunches(_ item: MenuBarItem) -> Bool {
        if case .string = item.tag.namespace {
            return true
        }
        return false
    }

    // MARK: Persisted verdicts

    /// Bounds single-operation retries, never direct requests; bulk apply uses separate backoff and circuit breakers.
    /// On macOS 27, applySectionItemOrder checks destination-scoped recentMoveFailures and item-scoped breakers.
    func isUnresponsive(_ item: MenuBarItem) -> Bool {
        isMarked(item, in: \.markDates)
    }

    /// Bounds cannotComplete repair retries, but direct user moves still try.
    func cannotCompleteMarked(_ item: MenuBarItem) -> Bool {
        if let bundleID = item.sourceApplication?.bundleIdentifier ?? item.owningApplication?.bundleIdentifier,
           Self.shippedUnmovableOwners.contains(bundleID)
        {
            return true
        }
        return isMarked(item, in: \.cannotCompleteDates)
    }

    /// Whether the visible-boundary repair gave up on the item within the
    /// last day.
    func strandedMarked(_ item: MenuBarItem) -> Bool {
        isMarked(item, in: \.strandedDates, lifetime: Self.strandLifetime)
    }

    private func isMarked(
        _ item: MenuBarItem,
        in dates: ReferenceWritableKeyPath<MenuBarItemFailureLedger, [String: Date]>,
        lifetime: TimeInterval = markLifetime
    ) -> Bool {
        let key = Self.key(for: item)
        guard let date = self[keyPath: dates][key] else {
            return false
        }
        guard date > Date.now.addingTimeInterval(-lifetime) else {
            self[keyPath: dates][key] = nil
            persist()
            return false
        }
        return true
    }

    // MARK: Recording

    /// Persists only a second same-kind unresponsive or cannotComplete failure with a launch-stable key.
    func recordFailure(
        for item: MenuBarItem,
        kind: FailureKind,
        now _: ContinuousClock.Instant = .now
    ) {
        let key = Self.key(for: item)

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

    /// Marks strands immediately because the repair's trip limit already required repeated failures.
    func recordStrand(for item: MenuBarItem) {
        guard Self.isStableAcrossLaunches(item) else {
            return
        }
        let key = Self.key(for: item)
        let isNew = strandedDates[key] == nil
        strandedDates[key] = .now
        persist()
        if isNew {
            Self.diagLog.info("Marked \(key) as stranded")
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

    /// Persist after mark's inout access ends; reading both dictionaries during that access violates Swift exclusivity.
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

    /// One success clears every provisional and persisted verdict for the item.
    func recordSuccess(for item: MenuBarItem) {
        let key = Self.key(for: item)
        provisionalMarks.remove(key)
        provisionalCannotComplete.remove(key)
        let hadUnresponsive = markDates.removeValue(forKey: key) != nil
        let hadCannotComplete = cannotCompleteDates.removeValue(forKey: key) != nil
        let hadStrand = strandedDates.removeValue(forKey: key) != nil
        guard hadUnresponsive || hadCannotComplete || hadStrand else {
            return
        }
        persist()
        Self.diagLog.info("\(key) answered again; cleared failure marks")
    }

    func removeAll() {
        provisionalMarks.removeAll()
        provisionalCannotComplete.removeAll()
        guard !markDates.isEmpty || !cannotCompleteDates.isEmpty || !strandedDates.isEmpty else {
            return
        }
        markDates.removeAll()
        cannotCompleteDates.removeAll()
        strandedDates.removeAll()
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
        store(strandedDates, forKey: .strandedMenuBarItems)
        Defaults.set(Self.currentBuildVersion, forKey: .menuBarFailureLedgerVersion)
    }
}
