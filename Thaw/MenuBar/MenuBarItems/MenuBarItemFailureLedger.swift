//
//  MenuBarItemFailureLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - MenuBarItemFailureLedger

/// The single record of which menu bar items have been failing us, and how.
///
/// - Should the next bulk apply skip it? Any move failure counts, so one
///   stuck item can't retrigger a cursor-hijacking apply every cycle (#736).
///   Expires on a growing timer.
/// - Should a single operation stop retrying it? Only an owner that never
///   acknowledges events counts (Little Snitch, with GUI Scripting off).
///   Persisted, or it's rediscovered every launch.
///
/// One ledger because one success must clear both at once.
///
/// Neither is a veto: the user can still move a backed-off item, and a
/// marked item is still tried once, so a recovered owner heals on its own.
@MainActor
final class MenuBarItemFailureLedger {
    enum FailureKind {
        case unresponsiveOwner
        case other
    }

    /// How long a persisted mark survives without being renewed.
    ///
    /// Long enough to outlast the user's own restarts, short enough to lapse
    /// if never touched again.
    private static let markLifetime: TimeInterval = 60 * 60 * 24 * 14

    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemFailureLedger")

    /// Bumping it drops every persisted mark once. Marks from before the owner
    /// checks blamed Control Center-hosted items for Control Center's own
    /// timeouts.
    private static let markRuleVersion = 2

    /// The build the persisted marks belong to, qualified by ``markRuleVersion``.
    /// An update drops them, or a fix stays masked for the mark's lifetime.
    private static var currentBuildVersion: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(build)/rule\(markRuleVersion)"
    }

    /// Grows linearly with consecutive failures, capped at 5 minutes.
    static nonisolated func backoffInterval(failureCount: Int) -> Duration {
        .seconds(min(30 * max(failureCount, 1), 300))
    }

    /// Session-scoped failure history driving the backoff window.
    private var backoffHistory = [String: (count: Int, lastFailure: ContinuousClock.Instant)]()

    /// When each marked key was last seen failing as an unresponsive owner.
    private var markDates: [String: Date]

    /// Unresponsive-owner failures this session, for keys not yet marked.
    /// One failure can be semaphore contention, not the owner. Not persisted.
    private var provisionalMarks = [String: Int]()

    /// How many unresponsive-owner failures a key must accumulate in one
    /// session before it earns a persisted mark.
    ///
    /// Contention during a startup restore wave alone can fail an item twice.
    private static let failuresBeforeMarking = 3

    init() {
        let storedBuild = Defaults.string(forKey: .unresponsiveMenuBarItemsBuild)
        let versionChanged = storedBuild != Self.currentBuildVersion

        let stored = versionChanged
            ? [:]
            : Defaults.dictionary(forKey: .unresponsiveMenuBarItems) as? [String: Double] ?? [:]
        let cutoff = Date.now.addingTimeInterval(-Self.markLifetime)
        markDates = stored.compactMapValues { interval in
            let date = Date(timeIntervalSinceReferenceDate: interval)
            return date > cutoff ? date : nil
        }

        if versionChanged {
            Self.diagLog.info("Build changed (\(storedBuild ?? "none") -> \(Self.currentBuildVersion)); dropping persisted failure marks")
        }
        if versionChanged || markDates.count != stored.count {
            persist()
        }
    }

    // MARK: Keys

    /// The key an item is filed under.
    ///
    /// `uniqueIdentifier`, as custom names use.
    private static func key(for item: MenuBarItem) -> String {
        // So an owner that retitles itself earns one verdict.
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }

    /// Whether an item's key means anything after a relaunch.
    ///
    /// UUID namespaces change every session; they get backoff but are
    /// never persisted.
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
    /// Takes a key because the apply loops check before resolving the item.
    ///
    /// - Parameter key: The item's `uniqueIdentifier`.
    func isUnderBackoff(key: String, now: ContinuousClock.Instant = .now) -> Bool {
        guard let entry = backoffHistory[key] else {
            return false
        }
        return now - entry.lastFailure < Self.backoffInterval(failureCount: entry.count)
    }

    /// Whether the item is inside its backoff window.
    ///
    /// Derives the key like ``recordFailure(for:kind:now:)``. The overload
    /// above uses the raw identifier, which misses owners that retitle.
    func isUnderBackoff(for item: MenuBarItem, now: ContinuousClock.Instant = .now) -> Bool {
        isUnderBackoff(key: Self.key(for: item), now: now)
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

    /// Every failure extends the backoff window. Only an unresponsive owner
    /// can earn a persisted mark, and only once it has failed that way
    /// ``failuresBeforeMarking`` times in this session.
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
        if !wasMarked {
            let failures = (provisionalMarks[key] ?? 0) + 1
            provisionalMarks[key] = failures
            guard failures >= Self.failuresBeforeMarking else {
                Self.diagLog.debug(
                    "\(key) failed \(failures) time(s); waiting for \(Self.failuresBeforeMarking) before marking it"
                )
                return
            }
        }
        markDates[key] = .now
        persist()
        if !wasMarked {
            Self.diagLog.info("Marked \(key) as unresponsive to synthetic events")
        }
    }

    /// Clears every record for the item.
    func recordSuccess(for item: MenuBarItem) {
        let key = Self.key(for: item)
        backoffHistory.removeValue(forKey: key)
        provisionalMarks.removeValue(forKey: key)
        guard markDates.removeValue(forKey: key) != nil else {
            return
        }
        persist()
        Self.diagLog.info("\(key) answered again; cleared unresponsive mark")
    }

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
        // Stamped even when empty, to stay in step with the set.
        Defaults.set(Self.currentBuildVersion, forKey: .unresponsiveMenuBarItemsBuild)
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
