//
//  MenuBarItemManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import AXSwift6
import Cocoa
import Collections
import Combine

// @preconcurrency retained: CoreGraphics event types (CGEventSource/CGEvent) are
// still not Sendable-annotated in the macOS 26/27 SDK, yet are used off the main
// actor under OSAllocatedUnfairLock for menu-bar event posting. Removing the shim
// would force @unchecked Sendable wrappers. Drop this once Apple annotates them.
@preconcurrency import CoreGraphics
import Observation
import os.lock

/// Simple actor-based semaphore to prevent overlapping operations
actor SimpleSemaphore {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var value: Int
    private var waiters: Deque<Waiter> = [] // FIFO; O(1) popFirst instead of Array's O(n) removeFirst

    init(value: Int) {
        precondition(value >= 0, "SimpleSemaphore requires a non-negative value")
        self.value = value
    }

    /// Waits for, or decrements, the semaphore, throwing on cancellation.
    func wait() async throws {
        if Task.isCancelled {
            throw CancellationError()
        }

        value -= 1
        if value >= 0 {
            return
        }

        let id = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: { [weak self] in
            Task.detached { await self?.cancelWaiter(withID: id) }
        }
    }

    private func cancelWaiter(withID id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            // The waiter was already consumed by signal(); don't touch the value.
            return
        }
        value += 1
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    /// An error that indicates the semaphore wait timed out.
    struct TimeoutError: Error {}

    private enum WaitOutcome {
        case acquired
        case timedOut
    }

    /// Waits for, or decrements, the semaphore with a timeout.
    /// Throws ``CancellationError`` on cancellation or
    /// ``TimeoutError`` on timeout.
    ///
    /// Invariant 1: on `TimeoutError`, the semaphore's state is exactly as
    /// if this call never happened (no permit held, no waiter left behind).
    /// Invariant 2: on normal return, exactly one permit is held.
    func wait(timeout: Duration) async throws {
        let outcome: WaitOutcome = try await withThrowingTaskGroup(of: WaitOutcome.self) { group in
            group.addTask {
                try await self.wait()
                return .acquired
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .timedOut
            }
            // The first child to finish wins. The group always has exactly
            // two children at this point, so next() must return a value.
            guard let first = try await group.next() else {
                preconditionFailure("SimpleSemaphore.wait: task group unexpectedly empty")
            }
            group.cancelAll()
            if first == .timedOut {
                // The acquire child may STILL have won the race against
                // cancellation (it may have decremented `value` before
                // cancelAll() landed). Drain it: an .acquired result means
                // we hold a permit nobody will use, so give it back to
                // preserve invariant 1. A CancellationError from the drain
                // is the normal case (the acquire child was cancelled
                // cleanly before winning) and is swallowed.
                do {
                    while let drained = try await group.next() {
                        if drained == .acquired {
                            self.signal()
                        }
                    }
                } catch is CancellationError {
                    // Acquire child cancelled cleanly — nothing held.
                }
            } else {
                // Acquired. Drain the cancelled timeout-sleep child and
                // ignore its error (CancellationError); this preserves
                // invariant 2.
                while await (try? group.next()) != nil {
                    // Intentionally empty: draining the cancelled child, result discarded.
                }
            }
            return first
        }
        if outcome == .timedOut {
            throw TimeoutError()
        }
    }

    /// Signals the semaphore, resuming the next waiter if present.
    ///
    /// Standard counting-semaphore semantics: always increment value,
    /// then wake a queued waiter only when the post-increment value is
    /// still non-positive (meaning waiters remain). The previous
    /// implementation skipped the increment when waking a waiter, which
    /// caused value to drift negative when concurrent callers queued
    /// up during a long-running holder; every subsequent caller would
    /// then see value < 0 in wait and suspend forever even after all
    /// prior holders had released.
    func signal() {
        value += 1
        if value <= 0, let waiter = waiters.popFirst() {
            waiter.continuation.resume(returning: ())
        }
    }

    /// Resets the semaphore to a given value, cancelling all pending waiters.
    /// Use ONLY as a last resort when the semaphore is suspected to be leaked.
    func reset(to value: Int = 1) {
        for waiter in waiters {
            waiter.continuation.resume(throwing: CancellationError())
        }
        waiters.removeAll()
        self.value = value
    }
}

/// Manager for menu bar items.
@MainActor
@Observable
final class MenuBarItemManager {
    static let layoutWatchdogTimeout: Duration = .seconds(6)

    /// Delay between relocation/restore moves and the subsequent recache,
    /// giving macOS time to settle menu bar item positions.
    static let uiSettleDelay: Duration = .milliseconds(300)

    /// The current cache of menu bar items.
    private(set) var itemCache = ItemCache(displayID: nil)

    /// A Boolean value that indicates whether the control items for the
    /// hidden sections are missing from the menu bar.
    private(set) var areControlItemsMissing = false

    /// Number of consecutive `ControlItemPair` lookup failures seen by
    /// `cacheItemsRegardless`. Reset to zero on the first successful lookup.
    /// Once this reaches `controlItemRebuildThreshold`, the hidden and
    /// always-hidden control items' underlying status items are rebuilt once
    /// for that uninterrupted failure episode (see `recreateStatusItem()`).
    private var controlItemLookupFailureStreak = 0

    /// Whether the current uninterrupted lookup-failure episode has already
    /// rebuilt the control items. Re-armed only after a successful lookup.
    private var didRebuildControlItemsForCurrentFailureEpisode = false

    /// When the most recent `ControlItemPair` lookup failure was recorded.
    /// Feeds ``controlItemLookupRetryBackoff(consecutiveFailures:threshold:baseDelay:maxDelay:)``
    /// so the change-detector poll stops re-running a full recache every
    /// tick against a failure that is not going away (#933). Cleared on
    /// the first successful lookup.
    private var lastControlItemLookupFailureAt: ContinuousClock.Instant?

    /// Consecutive authoritative cache readings in which the hidden section
    /// has no geometric span despite a populated saved hidden section.
    private var hiddenSectionCollapseStreak = 0

    /// Prevents repeated divider recreation until healthy geometry re-arms
    /// recovery for a later collapse episode.
    private var didRecoverHiddenSectionForCurrentCollapse = false

    /// Consecutive authoritative layout applies that need to move a hidden
    /// divider which macOS has parked off every display.
    private var parkedHiddenDividerMismatchStreak = 0

    /// Prevents repeated divider recreation until the mismatch or parked
    /// geometry clears and re-arms recovery for a later episode.
    private var didRecoverParkedHiddenDividerForCurrentMismatch = false

    /// Number of consecutive `ControlItemPair` lookup failures required
    /// before the control items' status items are rebuilt.
    static nonisolated let controlItemRebuildThreshold = 3

    /// Number of consecutive collapsed readings required before discarding a
    /// hidden divider's stale autosave position.
    static nonisolated let hiddenSectionCollapseRecoveryThreshold = 3

    /// Number of authoritative mismatch applies required before discarding a
    /// parked hidden divider's stale autosave position.
    static nonisolated let parkedHiddenDividerRecoveryThreshold = 2

    /// Supplementary AX-derived identity for items whose CG-side identity is
    /// degraded (a Control-Center generic `Item-N` placeholder title, or a
    /// bundle-id-shaped title — see `86f2514e`). Populated at most once per
    /// `cacheItemsRegardless` pass, only when at least one degraded item is
    /// present in that pass. Additive and display-only: this map is never
    /// consulted for matching, section assignment, or persisted layout keys
    /// — see plan 014. No display consumer exists on this branch, so this
    /// is groundwork for a future tooltip/display-name path.
    private(set) var degradedItemAXIdentities = [CGWindowID: AXIdentityCatalog.AXItemIdentity]()

    /// Gates the AX enrichment pass in `cacheItemsRegardless`. No consumer of
    /// `degradedItemAXIdentities` exists yet (see its declaration), so the
    /// per-cycle `AXIdentityCatalog.snapshot` and per-item window bounds
    /// lookups run only when explicitly enabled for diagnostics.
    static nonisolated let isDegradedIdentityEnrichmentEnabled =
        Defaults.store.bool(forKey: "EnableDegradedItemAXEnrichment")

    /// Widest a control item can be while still counting as a marker rather
    /// than a collapsed section's stretched divider.
    ///
    /// A collapsed section sets its control item to `Lengths.expanded`
    /// (10000 pt, which the window server clamps to roughly the span of the
    /// displays); an expanded one uses `NSStatusItem.variableLength`, which
    /// measures in single digits. Anything between the two is not a real
    /// state, so the exact value only has to separate them.
    private static nonisolated let markerWidthCeiling: CGFloat = 256

    /// Whether a divider's geometry contradicts its section's logical state,
    /// meaning the snapshot was taken part-way through an expand or collapse.
    ///
    /// The two do not move together: `section.show()` drags the control item
    /// and resizes it in separate steps, so a cache pass can observe items
    /// already at their revealed coordinates while the divider still carries
    /// the stretched width of the collapsed layout. Classifying against that
    /// mixture puts the whole hidden section into `visible` — which is what
    /// empties the hidden row in the layout editor while it sits open (#851).
    ///
    /// - Parameters:
    ///   - dividerWidth: Width of the section's control item.
    ///   - isSectionCollapsed: Whether the section's logical state is hidden.
    ///
    /// - Returns: `true` when geometry and logical state disagree.
    static nonisolated func isMidSectionTransition(
        dividerWidth: CGFloat,
        isSectionCollapsed: Bool
    ) -> Bool {
        (dividerWidth > markerWidthCeiling) != isSectionCollapsed
    }

    /// The item windowIDs enumerated in each of the last few cache cycles,
    /// oldest first.
    ///
    /// The relocation planner distinguishes a genuinely new item from one
    /// whose identifier merely changed by asking whether it has seen the
    /// windowID before, and the only history it had was the immediately
    /// preceding cycle. A single degraded enumeration is enough to lose an
    /// established windowID — a Space switch drops the whole list, and the
    /// menu bar item window list is published incrementally after a display
    /// change — after which the item reads as brand new and gets dragged out
    /// of the section the user put it in (#849).
    ///
    /// Keeping several cycles of history absorbs those gaps. It is deliberately
    /// not "every windowID ever seen": the window server recycles windowIDs,
    /// and a recycled ID mistaken for a known one would silently skip
    /// relocating a genuinely new item.
    private var recentItemWindowIDCycles: Deque<Set<CGWindowID>> = []

    /// Consecutive cache passes discarded as mid expand/collapse.
    ///
    /// Bounds the guard: if geometry and logical state disagree persistently
    /// rather than transiently, the cache must still be allowed to move
    /// forward instead of serving a stale layout indefinitely.
    private var midTransitionSkipStreak = 0

    /// How many consecutive passes may be discarded as mid expand/collapse
    /// before one is accepted regardless.
    private static let maxMidTransitionSkips = 3

    /// How many cache cycles a windowID stays eligible as "recently seen".
    private static let recentWindowIDCycleWindow = 10

    /// Diagnostic logger for the menu bar item manager.
    fileprivate static nonisolated let diagLog = DiagLog(category: "MenuBarItemManager")

    /// Semaphore to prevent overlapping event operations.
    private let eventSemaphore = SimpleSemaphore(value: 1)

    /// The single record of which items have been failing, and how.
    let failureLedger = MenuBarItemFailureLedger()

    /// The record of which saved identifiers no longer match anything.
    let staleIdentifierLedger = StaleIdentifierLedger()

    /// Actor for managing menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Contexts for temporarily shown menu bar items.
    private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    private var rehideTimer: Timer?
    private var rehideCancellable: AnyCancellable?

    /// Timestamp of the most recent menu bar item move operation.
    private var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// Cached timeouts for move operations.
    private var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// Cached timeouts for click operations (adaptive per app).
    private var clickOperationTimeouts = [MenuBarItemTag: Duration]()
    /// Serialization gate for cache operations.
    private let cacheGate = CacheGate()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Observes `appState.navigationState`'s @Observable properties (wave 3).
    private var navigationStateObservationTask: Task<Void, Never>?

    /// A candidate menu window matched by the open-menu probe.
    nonisolated struct MenuWindowCandidate: Sendable {
        let windowID: CGWindowID
        let bounds: CGRect
    }

    /// The currently running "is any menu open" probe, reused so concurrent
    /// smart-rehide callers do not all trigger their own full menu-bar scan.
    /// Returns the candidate menu windows owned by menu bar item processes;
    /// persistence filtering happens on the actor.
    private var menuOpenCheckTask: Task<[MenuWindowCandidate], Never>?

    /// The most recent open-menu probe result and its timestamp.
    private var menuOpenCheckCachedResult: Bool?
    private var menuOpenCheckCachedAt: ContinuousClock.Instant?

    /// First-seen timestamps for candidate menu windows, keyed by window ID.
    /// A real menu is transient; a window that stays on screen longer than
    /// ``menuWindowPersistenceThreshold`` is persistent furniture (Droppy's
    /// shelf, notch HUDs) and must not block moves (#879 regression).
    private var menuWindowFirstSeen: [CGWindowID: ContinuousClock.Instant] = [:]

    /// Whether the open-menu probe has run at least once. Windows already
    /// on screen at the first probe are grandfathered as persistent.
    private var hasSeededMenuWindowProbe = false

    /// How long a candidate menu window may stay on screen before it is
    /// reclassified as persistent furniture rather than an open menu.
    static nonisolated let menuWindowPersistenceThreshold: Duration = .seconds(30)

    /// Timer for lightweight periodic cache checks.
    private var cacheTickCancellable: AnyCancellable?

    /// Persisted identifiers of menu bar items we've already seen.
    private var knownItemIdentifiers = Set<String>()
    /// Suppresses the next automatic relocation of newly seen leftmost items.
    private var suppressNextNewLeftmostItemRelocation = false

    @MainActor
    deinit {
        rehideTimer?.invalidate()
        rehideCancellable?.cancel()
        cacheTickCancellable?.cancel()
        menuOpenCheckTask?.cancel()
        navigationStateObservationTask?.cancel()
    }

    /// Continuations waiting for a background cache cycle to complete,
    /// keyed by an opaque token.
    ///
    /// A dictionary rather than a single slot: several callers may await a
    /// cache cycle concurrently, and a shared slot let an unrelated caller's
    /// early bail resume — or permanently strand — someone else's waiter.
    private var backgroundCacheWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    /// Source of tokens for ``backgroundCacheWaiters``.
    private var nextBackgroundCacheWaiterToken = 0

    /// Registers `continuation` as a waiter and returns its token.
    private func addBackgroundCacheWaiter(_ continuation: CheckedContinuation<Void, Never>) -> Int {
        nextBackgroundCacheWaiterToken += 1
        let token = nextBackgroundCacheWaiterToken
        backgroundCacheWaiters[token] = continuation
        return token
    }

    /// Resumes the waiter for `token`, if it has not already been resumed.
    ///
    /// Removing before resuming is what makes this safe to call more than
    /// once: a second call finds nothing and does nothing. Resuming a
    /// `CheckedContinuation` twice is a hard crash, so this ordering is
    /// load-bearing — do not "simplify" it to a lookup followed by a removal.
    private func resumeBackgroundCacheWaiter(_ token: Int) {
        backgroundCacheWaiters.removeValue(forKey: token)?.resume()
    }

    // MARK: - Layout coordination state

    //
    // The flags below coordinate three overlapping concerns. They are
    // not collapsed into a single token because the AX-timing and live-
    // Window-Server interactions each one guards have evolved
    // independently from production incidents. Any consolidation needs
    // manual smoke-testing on real hardware to catch regressions that
    // unit tests cannot.
    //
    // 1. In-flight gating of the cache cycle. While one of these is
    //    set, cacheItemsRegardless suppresses restore, late-arrival
    //    detection, or section-order saves so an in-flight operation
    //    isn't fought by the cycle:
    //      - isResettingLayout
    //      - isRestoringItemOrder (+ isRestoringItemOrderTimestamp)
    //      - isApplyingProfileLayout
    //      - suppressNextNewLeftmostItemRelocation
    //
    // 2. Startup settling. Gates restore and saves during the cold-boot
    //    or post-permission-grant window when many apps appear at once:
    //      - isInStartupSettling (+ startupSettlingTask)
    //      - settlingDeadline
    //      - settlingExpectedBundleIDs
    //      - settlingKind
    //
    // 3. Active-profile re-sort. Caches the last-applied profile spec so
    //    a late-arriving profile item can be reinserted without a full
    //    re-apply:
    //      - activeProfileLayout
    //      - activeProfileItemIdentifiers
    //      - profileSortedItemIdentifiers
    //      - profileResortTask
    //
    // isApplyingProfileLayout sits in both group 1 and group 3 because
    // it both gates the cache cycle and marks an active profile apply
    // window for the re-sort path.

    /// Suppresses image cache updates during layout reset to prevent stale cache during moves.
    var isResettingLayout = false
    /// Suppresses saving section order during an active order-restore pass.
    private var isRestoringItemOrder = false
    /// Timestamp when isRestoringItemOrder was set (for timeout detection).
    private var isRestoringItemOrderTimestamp: Date?
    /// True during the startup settling period, during which restore operations
    /// and section-order saves are suppressed. This prevents cascading icon moves
    /// when many apps launch at login (login item boot) or restart in quick succession
    /// (e.g. app update checks). Cleared after a fixed delay, then one final
    /// restore runs to enforce the user's saved layout.
    private var isInStartupSettling = false
    /// Whether the early, resolved-identities-only saved-layout apply has
    /// already been attempted for the current settling period. Bounds that
    /// pass to one attempt per launch: it exists to get the identifiable
    /// items into place while sourcePID resolution is still catching up, and
    /// the unrestricted settling-end pass covers whatever it left behind.
    private var didAttemptEarlySavedLayoutApply = false
    /// Handle to the in-flight startup settling Task. Retained so that a
    /// subsequent performSetup() call can cancel the previous settling period
    /// before starting a new one, preventing multiple concurrent settling tasks.
    private var startupSettlingTask: Task<Void, Never>?
    /// Handle to the initial cache warm-up task. The first full cache can be
    /// expensive on dense menu bars, so it runs off the startup critical path.
    private var initialCacheTask: Task<Void, Never>?
    /// Absolute deadline for the current startup settling period. Stored so
    /// that a re-entry of performSetup() (e.g. permission re-grant) can
    /// preserve any remaining time from the original period rather than
    /// resetting to a shorter delay based on current systemUptime.
    private var settlingDeadline: ContinuousClock.Instant?
    /// Bundle IDs the current settling period is waiting on. Empty for a
    /// preflight (count-stability) settling. Promoted to non-empty when
    /// startSettlingPeriod is called with expectedBundleIDs after a real
    /// relaunch wave; cancelSettlingPeriod refuses to tear down a promoted
    /// settling so a concurrent no-op apply cannot clobber an in-flight
    /// wait for relaunched apps to reattach.
    private var settlingExpectedBundleIDs = Set<String>()

    /// Authority class of the current settling period. Used so that a
    /// less-authoritative preflight cannot tear down or replace a
    /// more-authoritative settling already in flight.
    ///
    /// - cold: started by performSetup; the cold-boot wait while menu
    ///   bar items are still loading. Cannot be cancelled or replaced
    ///   by a preflight, only by another cold (re-entry) or a real
    ///   expected-set relaunch.
    /// - preflight: started before applyOffset to suppress restore
    ///   while the wave runs. Cancellable by the matching no-op path.
    /// - expectedSet: post-relaunch wave waiting on specific bundle IDs
    ///   to reattach. Cancellation is already gated by the non-empty
    ///   settlingExpectedBundleIDs; tracked here for parity.
    private enum SettlingKind {
        case cold
        case preflight
        case expectedSet
    }

    private var settlingKind: SettlingKind?
    /// Persisted bundle identifiers explicitly placed in hidden section.
    private var pinnedHiddenBundleIDs = Set<String>()
    /// Persisted bundle identifiers explicitly placed in always-hidden section.
    private var pinnedAlwaysHiddenBundleIDs = Set<String>()

    /// Cached layout parameters from the last profile apply, used to re-sort
    /// when profile-listed items appear after the initial apply. Read access
    /// is internal so tests can verify the re-arm path refreshes it; writes
    /// remain confined to this file (armProfileState and rearmActiveProfileLayout).
    private(set) var activeProfileLayout: (
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    )?

    /// Flattened set of item identifiers from the active profile's itemOrder,
    /// for O(1) lookup when detecting late-arriving profile items.
    private(set) var activeProfileItemIdentifiers = Set<String>()

    /// Set of item identifiers that were present when the profile layout was
    /// last applied (or re-applied). Used to detect genuinely new arrivals.
    private var profileSortedItemIdentifiers = Set<String>()

    /// Handle for the debounced profile re-sort task. Cancelled and re-created
    /// each time a new late-arriving profile item is detected.
    private var profileResortTask: Task<Void, Never>?

    /// True while `applyProfileLayout` is executing. Suppresses the
    /// late-arrival detection in `cacheItemsRegardless` to prevent
    /// false re-sort triggers during an in-flight sort.
    private(set) var isApplyingProfileLayout = false

    /// Monotonically increasing token identifying the most recent
    /// profile-state arm. Each `.profile` armProfileState call takes a
    /// new token; a cancelled apply may only roll back state it still
    /// owns (its token is still current), so a late-arriving
    /// cancellation cannot clobber the state armed by the newer apply
    /// that displaced it.
    private var profileApplyToken = 0

    /// Pre-arm snapshot of the in-memory profile state, tagged with the
    /// token of the apply that captured it. Restored when that apply is
    /// cancelled mid-flight so memory reverts to what disk still holds
    /// (persistence is deferred to persistProfileStateOnSuccess) and the
    /// late-arrival re-sort path stops targeting a profile that never
    /// committed.
    private struct ProfileApplySnapshot {
        var token: Int
        var pinnedHidden: Set<String>
        var pinnedAlwaysHidden: Set<String>
        var sectionOrder: [String: [String]]
        var profileLayout: (
            pinnedHidden: Set<String>,
            pinnedAlwaysHidden: Set<String>,
            sectionOrder: [String: [String]],
            itemSectionMap: [String: String],
            itemOrder: [String: [String]]
        )?
        var profileItemIdentifiers: Set<String>
    }

    /// The snapshot captured by the most recent `.profile` arm, if that
    /// apply has neither committed nor rolled back yet.
    private var priorProfileApplySnapshot: ProfileApplySnapshot?

    /// True while `applyProfileLayout` is actively issuing the move
    /// sequence (Phase 6). Lets `postMoveEvents` skip redundant
    /// per-item cursor hide/show churn — the cursor is already held
    /// hidden for the whole sequence, and is restored once at Phase 7.
    private var isBulkApplyInProgress = false

    /// Timestamp of the first observation of a diverged layout that has
    /// not yet been confirmed by a second consecutive observation. `nil`
    /// when no divergence is currently pending confirmation. See
    /// `confirmedDivergence(divergedNow:pendingSince:now:staleness:)`.
    private var pendingDivergenceObservedAt: ContinuousClock.Instant?

    /// When the most recent bulk apply finished with moves it had planned
    /// but never enacted. `nil` when the last apply enacted everything it
    /// planned, which is the state in which the live bar is an order of
    /// record. See `unfinishedMoveBatchBlocksSave(observedAt:now:)`.
    private var unfinishedMoveBatchObservedAt: ContinuousClock.Instant?

    /// How many bulk applies in a row ended with planned moves unenacted.
    ///
    /// Feeds `automaticBulkApplyPermitted`. On a bar where drags fail
    /// systemically (#900), every retry apply ends unfinished, re-arms the
    /// save withhold, and so keeps the divergence it would need to clear —
    /// an unbounded loop in which the cursor is hidden for the length of a
    /// batch on every pass (#899). The streak is what lets the dispatch
    /// gate tell "one batch had a bad day" from "batches on this bar do
    /// not complete".
    private var consecutiveUnfinishedBulkApplies = 0

    /// Records how a bulk apply ended, for the saveSectionOrder gate.
    ///
    /// A clean batch clears the arm rather than leaving it to expire: the
    /// bar now matches what the apply set out to produce, and there is no
    /// reason to keep withholding it from the saved order.
    func recordBulkApplyOutcome(unenactedMoveCount: Int) {
        guard unenactedMoveCount > 0 else {
            unfinishedMoveBatchObservedAt = nil
            consecutiveUnfinishedBulkApplies = 0
            return
        }
        unfinishedMoveBatchObservedAt = .now
        consecutiveUnfinishedBulkApplies += 1
        MenuBarItemManager.diagLog.warning(
            "Profile layout: \(unenactedMoveCount) planned move(s) left unenacted; withholding the current arrangement from the saved order (streak: \(consecutiveUnfinishedBulkApplies))"
        )
    }

    /// Whether the latest bulk apply left a partial arrangement that must not
    /// replace the saved order.
    var hasUnfinishedMoveBatch: Bool {
        Self.unfinishedMoveBatchBlocksSave(observedAt: unfinishedMoveBatchObservedAt)
    }

    /// The instance reading of the bulk-apply circuit breaker: feeds the
    /// session streak and latch into the pure gate and logs a refusal
    /// under the caller's name.
    ///
    /// - Parameter quietly: `true` logs the refusal at debug instead of
    ///   warning, for a caller that retries on every cache tick and would
    ///   otherwise flood the log with an expected refusal.
    private func isAutomaticBulkApplyPermitted(caller: String, quietly: Bool = false) -> Bool {
        if Self.automaticBulkApplyPermitted(
            consecutiveUnfinishedBatches: consecutiveUnfinishedBulkApplies,
            lastUnfinishedBatchAt: unfinishedMoveBatchObservedAt,
            now: .now
        ) {
            return true
        }
        let message = "\(caller): skipping, \(consecutiveUnfinishedBulkApplies) consecutive bulk applies " +
            "ended with unenacted moves; cooling down before another attempt"
        if quietly {
            MenuBarItemManager.diagLog.debug(message)
        } else {
            MenuBarItemManager.diagLog.warning(message)
        }
        return false
    }

    /// How long a failed item stays excluded from bulk-apply moves.
    ///
    /// Kept as a forwarding shim so callers and tests do not have to reach
    /// through to the ledger for a value that reads as a property of the
    /// manager's retry policy.
    static nonisolated func moveFailureBackoffInterval(failureCount: Int) -> Duration {
        MenuBarItemFailureLedger.backoffInterval(failureCount: failureCount)
    }

    /// How the failure ledger should file an arbitrary error thrown by a
    /// move. Only `EventError` carries enough detail to blame the owner.
    static nonisolated func failureKind(of error: any Error) -> MenuBarItemFailureLedger.FailureKind {
        (error as? EventError)?.failureKind ?? .other
    }

    /// The move-operation budget the next attempt should use, given how the
    /// attempt that just finished turned out.
    ///
    /// The budget shrinks only as a reward for an attempt that actually
    /// placed the item, grows when the owner stopped responding, and holds
    /// steady when the attempt displaced the item without landing it.
    ///
    /// That last case is the one that matters. `waitForMoveEventResponse`
    /// returns on any origin change, and an attempt that misses still nudges
    /// the item a pixel or two as the owner registers the click. Decaying on
    /// those responses let a run of misses starve the budget until the item
    /// could no longer answer inside it — the `itemResponseTimeout` cascade
    /// in #881. Misses must be neutral, not rewarded.
    static nonisolated func nextMoveOperationTimeout(
        after current: Duration,
        outcome: MoveAttemptOutcome
    ) -> Duration {
        switch outcome {
        case .landed: current - current / 4
        case .displacedWithoutLanding: current
        case .ownerDidNotRespond: current + current / 2
        }
    }

    /// Whether the destination's target travelled far enough during a drag
    /// that the plan no longer describes the bar.
    ///
    /// Landing beside the target legitimately nudges it by roughly the moved
    /// item's own width, so the threshold has to sit well above an item width
    /// while still catching the real failure. The display's width is that
    /// line: a target that moves further than the whole display has not been
    /// reflowed locally, it has crossed into another section or into the
    /// offscreen parking space, and the plan built against its old position is
    /// describing an arrangement that no longer exists.
    ///
    /// In the #881 log the target's measured `minX` went from -4222 to 794 on
    /// a 1512 pt display between two attempts of a single move, and all eight
    /// attempts were spent re-dragging against it (#900).
    static nonisolated func destinationIsStale(
        plannedTargetMinX: CGFloat,
        currentTargetMinX: CGFloat,
        displayWidth: CGFloat
    ) -> Bool {
        abs(currentTargetMinX - plannedTargetMinX) > displayWidth
    }

    /// Whether the destination's target has been retreating in one direction
    /// across attempts of a single move.
    ///
    /// ``destinationIsStale(plannedTargetMinX:currentTargetMinX:displayWidth:)``
    /// measures one attempt against a display-width threshold, which catches
    /// a target that jumped sections but nothing smaller. A move can fail a
    /// different way: the item inserts on the wrong side of its anchor, the
    /// ordinal landing check quite correctly refuses it, and — because the
    /// menu bar lays out right to left — the insertion shoves the anchor
    /// further left. The next attempt re-plans against the anchor's new
    /// position and shoves it again. Each step is far too small to be stale,
    /// and the item never lands, so the whole attempt budget is spent walking
    /// the anchor across the bar.
    ///
    /// Observed on a live bar: an anchor at minX 1682 driven to 1650 over
    /// five attempts (−5, −13, −11, −3) while the moved item sat at 1683
    /// throughout. When the anchor is one of Thaw's own dividers, repeating
    /// that across cycles walks it offscreen until the hidden section reads
    /// as zero width, at which point saves and applies are both refused and
    /// the layout stops persisting entirely (#924, #927).
    ///
    /// A single legitimate nudge is expected — landing beside a target moves
    /// it by roughly the moved item's width — so one step proves nothing.
    /// A run of them in the same direction, with no landing in between, is
    /// not reflow: it is the move pushing its own anchor.
    ///
    /// Pure over its inputs.
    static nonisolated func targetIsRetreating(
        recentTargetMinX: [CGFloat],
        runLength: Int = 3
    ) -> Bool {
        guard runLength >= 1, recentTargetMinX.count > runLength else {
            return false
        }
        let deltas = recentTargetMinX.adjacentPairs().map { $1 - $0 }
        let run = deltas.suffix(runLength)
        guard run.count == runLength else {
            return false
        }
        return run.allSatisfy { $0 > 0 } || run.allSatisfy { $0 < 0 }
    }

    /// A launch-stable digest of an identifier list.
    ///
    /// FNV-1a rather than `hashValue`: Swift seeds its hasher per process,
    /// so `hashValue` cannot be compared across relaunches, which is exactly
    /// the comparison a field log needs to support.
    ///
    /// Order-sensitive by construction — that is the entire point. The saved
    /// section order is logged by count today, and a permutation that keeps
    /// membership intact is invisible in a count (#885).
    static nonisolated func orderDigest(_ identifiers: [String]) -> String {
        let prime: UInt64 = 0x100_0000_01B3
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for identifier in identifiers {
            for byte in identifier.utf8 {
                hash ^= UInt64(byte)
                hash &*= prime
            }
            // Separator, so ["ab", "c"] and ["a", "bc"] differ.
            hash ^= 0x1F
            hash &*= prime
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    /// A one-line, per-section description of how a saved order changed.
    ///
    /// Calls out the case where a section's membership is unchanged but its
    /// sequence is not. That combination is #885's signature and nothing in
    /// the logs surfaces it: counts match, the zero-width gate reads healthy,
    /// and identity resolution is clean, while every item sits at a new
    /// index. Naming it here means the next occurrence is attributable from
    /// the log alone instead of needing a plist captured before the fact.
    static nonisolated func sectionOrderChangeSummary(
        from old: [String: [String]],
        to new: [String: [String]]
    ) -> String {
        let keys = Set(old.keys).union(new.keys).sorted()
        let parts = keys.map { key -> String in
            let before = old[key] ?? []
            let after = new[key] ?? []
            if before == after {
                return "\(key)=\(after.count) unchanged"
            }
            let digests = "\(orderDigest(before))→\(orderDigest(after))"
            guard Set(before) == Set(after) else {
                return "\(key)=\(before.count)→\(after.count) \(digests)"
            }
            let displaced = zip(before, after).count { $0 != $1 }
            return "\(key)=\(after.count) REORDERED-ONLY \(digests) \(displaced)/\(after.count) displaced"
        }
        return parts.joined(separator: ", ")
    }

    /// How a single `postMoveEvents` attempt turned out, for the purpose of
    /// sizing the next attempt's budget.
    enum MoveAttemptOutcome {
        /// The item reached its destination.
        case landed
        /// The item moved but did not reach its destination.
        case displacedWithoutLanding
        /// The owner never answered the posted events.
        case ownerDidNotRespond
    }

    /// Persisted mapping of item tag identifiers to their original section name for
    /// temporarily shown items whose apps quit before they could be rehidden. When
    /// the app relaunches, this allows us to move the item back to its original section.
    private var pendingRelocations = [String: String]()

    /// Persisted mapping of item tag identifiers to their return destination for
    /// temporarily shown items. Stores the neighbor tag and position to restore
    /// the original ordering when the app relaunches.
    private var pendingReturnDestinations = [String: [String: String]]() // [tagIdentifier: ["neighbor": tag, "position": "left"|"right"]]

    /// Persisted per-section item order. Maps section key to an ordered list of
    /// `uniqueIdentifier` strings (right-to-left, matching cache array order).
    private var savedSectionOrder = [String: [String]]()

    /// Identifiers most recently moved from visible to hidden by the
    /// notch-overflow rebalance (Phase 4 of the layout apply). The ejection
    /// is a transient, per-display accommodation — these items must not be
    /// persisted as hidden (the user never moved them), and their divergence
    /// from the saved layout is intentional while the notched display is
    /// active. Cleared when overflow no longer applies, when a non-notched
    /// apply restores them, or when the user moves them to another section.
    private var notchOverflowEjectedUIDs = Set<String>()

    /// Whether notch overflow currently has items ejected into hidden.
    ///
    /// Callers use this to decide how to *reveal* those items: the visible row
    /// had no room left beside the notch when they were ejected, so expanding
    /// the hidden section inline cannot show them.
    var hasNotchOverflowEjectedItems: Bool {
        !notchOverflowEjectedUIDs.isEmpty
    }

    /// When the last continuous notch-overflow rebalance ejected items. Used
    /// only for the cooldown in rebalanceNotchOverflowIfNeeded(items:controlItems:).
    private var lastNotchRebalanceTimestamp: Date?
    /// Placement preference for newly detected menu bar items.
    private(set) var newItemsPlacement = NewItemsPlacement.defaultValue

    /// One home for the defaults keys holding the manager's persisted
    /// layout state, shared with ProfileManager's capture path and the
    /// `--reset-layout` escape hatch so the three can never drift apart.
    nonisolated enum LayoutStateKey {
        static let savedSectionOrder = "MenuBarItemManager.savedSectionOrder"
        static let knownItemIdentifiers = "MenuBarItemManager.knownItemIdentifiers"
        static let pinnedHiddenBundleIDs = "MenuBarItemManager.pinnedHiddenBundleIDs"
        static let pinnedAlwaysHiddenBundleIDs = "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs"
        static let pendingRelocations = "MenuBarItemManager.pendingRelocations"
        static let pendingReturnDestinations = "MenuBarItemManager.pendingReturnDestinations"

        /// Every key above, in declaration order.
        static let all = [
            savedSectionOrder,
            knownItemIdentifiers,
            pinnedHiddenBundleIDs,
            pinnedAlwaysHiddenBundleIDs,
            pendingRelocations,
            pendingReturnDestinations,
        ]
    }

    /// Loads persisted known item identifiers.
    private func loadKnownItemIdentifiers() {
        let key = LayoutStateKey.knownItemIdentifiers
        let defaults = Defaults.store
        if let stored = defaults.array(forKey: key) as? [String] {
            knownItemIdentifiers = Set(stored)
        }
    }

    /// Persists known item identifiers.
    private func persistKnownItemIdentifiers() {
        let key = LayoutStateKey.knownItemIdentifiers
        let defaults = Defaults.store
        defaults.set(Array(knownItemIdentifiers), forKey: key)
    }

    /// Loads persisted pinned bundle identifiers.
    private func loadPinnedBundleIDs() {
        let defaults = Defaults.store
        if let hidden = defaults.array(forKey: LayoutStateKey.pinnedHiddenBundleIDs) as? [String] {
            pinnedHiddenBundleIDs = Set(hidden)
        }
        if let alwaysHidden = defaults.array(forKey: LayoutStateKey.pinnedAlwaysHiddenBundleIDs) as? [String] {
            pinnedAlwaysHiddenBundleIDs = Set(alwaysHidden)
        }
    }

    /// Persists pinned bundle identifiers.
    private func persistPinnedBundleIDs() {
        let defaults = Defaults.store
        defaults.set(Array(pinnedHiddenBundleIDs), forKey: LayoutStateKey.pinnedHiddenBundleIDs)
        defaults.set(Array(pinnedAlwaysHiddenBundleIDs), forKey: LayoutStateKey.pinnedAlwaysHiddenBundleIDs)
    }

    /// Loads persisted pending relocations for temporarily shown items
    /// whose apps quit before they could be rehidden.
    private func loadPendingRelocations() {
        let key = LayoutStateKey.pendingRelocations
        if let stored = Defaults.store.dictionary(forKey: key) as? [String: String] {
            pendingRelocations = stored
        }
        let destKey = LayoutStateKey.pendingReturnDestinations
        if let stored = Defaults.store.dictionary(forKey: destKey) as? [String: [String: String]] {
            pendingReturnDestinations = stored
        }
    }

    /// Persists pending relocations.
    private func persistPendingRelocations() {
        let key = LayoutStateKey.pendingRelocations
        Defaults.store.set(pendingRelocations, forKey: key)
        let destKey = LayoutStateKey.pendingReturnDestinations
        Defaults.store.set(pendingReturnDestinations, forKey: destKey)
    }

    /// Loads persisted section order.
    private func loadSavedSectionOrder() {
        let key = LayoutStateKey.savedSectionOrder
        if let stored = Defaults.store.dictionary(forKey: key) as? [String: [String]] {
            // Repair entries that can never match a live item again before
            // anything plans against them. Earlier fixes stopped these from
            // being written but left what was already on disk (#788, #815).
            // Migrate helper-hosted namespaces before pruning, so an entry
            // that is only unmatchable because the item was renamed after
            // its app (Little Snitch) is rewritten rather than discarded.
            let migrated = LayoutSolver.canonicalizedSectionOrder(stored)
            let pruned = LayoutSolver.prunedSectionOrder(migrated)
            savedSectionOrder = pruned
            if pruned != stored {
                let removed = stored.reduce(into: 0) { total, entry in
                    total += entry.value.count - (pruned[entry.key]?.count ?? 0)
                }
                MenuBarItemManager.diagLog.info(
                    "Pruned \(removed) unmatchable entr(y/ies) from the saved section order"
                )
                persistSavedSectionOrder()
            }
            // Baseline digest, so a log that opens mid-session can still be
            // compared against a later save (#885).
            let baseline = pruned.keys.sorted()
                .map { "\($0)=\(pruned[$0]?.count ?? 0) \(Self.orderDigest(pruned[$0] ?? []))" }
                .joined(separator: ", ")
            MenuBarItemManager.diagLog.info("Loaded saved section order: \(baseline)")
        }
    }

    nonisolated struct NewItemsPlacement: Codable, Equatable {
        enum Relation: String, Codable {
            case leftOfAnchor
            case rightOfAnchor
            case sectionDefault
        }

        let sectionKey: String
        let anchorIdentifier: String?
        let relation: Relation

        static let defaultValue = NewItemsPlacement(
            sectionKey: Defaults.DefaultValue.newItemsSection,
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

    /// Loads the persisted placement preference for newly detected menu bar items.
    private func loadNewItemsPlacementPreference() {
        if let data = Defaults.data(forKey: .newItemsPlacementData),
           let stored = try? JSONDecoder().decode(NewItemsPlacement.self, from: data)
        {
            newItemsPlacement = stored
            return
        }

        let storedSection = Defaults.string(forKey: .newItemsSection) ?? Defaults.DefaultValue.newItemsSection
        let resolvedSection = sectionName(for: storedSection) ?? .hidden
        newItemsPlacement = NewItemsPlacement(
            sectionKey: sectionKey(for: resolvedSection),
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

    /// Persists the placement preference for newly detected menu bar items.
    private func persistNewItemsPlacementPreference() {
        Defaults.set(newItemsPlacement.sectionKey, forKey: .newItemsSection)
        if let data = try? JSONEncoder().encode(newItemsPlacement) {
            Defaults.set(data, forKey: .newItemsPlacementData)
        } else {
            Defaults.removeObject(forKey: .newItemsPlacementData)
        }
    }

    /// Persists the current saved section order.
    private func persistSavedSectionOrder() {
        Defaults.store.set(savedSectionOrder, forKey: LayoutStateKey.savedSectionOrder)
    }

    /// Extracts the current per-section item order from the given cache and
    /// persists it. Skips the write when the order has not changed.
    /// For items currently in the cache, uses their current section.
    /// For items from apps that are closed (not in cache), preserves their saved section.
    /// Computes the per-section item order dict from the given cache
    /// using the same filter and closed-app preservation logic that
    /// saveSectionOrder applies before persisting. Returns the dict
    /// without writing it anywhere.
    ///
    /// Exposed (rather than inlined inside saveSectionOrder) so the
    /// profile-capture path in ProfileManager.captureCurrentLayout can
    /// build its itemOrder field through the same pipeline. Without a
    /// shared helper, itemOrder was a raw itemCache snapshot that
    /// drifted from savedSectionOrder: it excluded closed-app entries
    /// that savedSectionOrder preserves through planSectionOrder's
    /// merge, and it included transient Control Center items
    /// (Live Activities, iPhone Mirroring) that savedSectionOrder
    /// filters out. On profile re-apply that drift caused
    /// closed-but-saved apps (e.g. jetbrains while the app is quit) to
    /// be treated as unmanaged and routed through planUnmanagedPlacement
    /// instead of landing at their saved section.
    ///
    /// Filter and merge:
    ///   - control items are excluded except the visibleControlItem
    ///     (Thaw chevron); its position within the visible section is
    ///     persisted so the LCS planner can detect when macOS placed
    ///     an app item on the wrong side of the chevron;
    ///   - non-control items without a resolved sourcePID are
    ///     excluded (their UIDs are unstable and would churn entries
    ///     every cycle);
    ///   - transient Control Center items (Live Activities, iPhone
    ///     Mirroring, generic Apple Item-0 placeholders) are excluded
    ///     so their ephemeral identifiers never enter the dict;
    ///   - items whose true section is recorded in
    ///     pendingReturnDestinations / pendingRelocations are treated
    ///     as closed-apps (preserves their pre-temporarilyShow section
    ///     instead of capturing the live visible position);
    ///   - LayoutSolver.planSectionOrder merges currentInSection with
    ///     closed-app entries from the previous savedSectionOrder so an
    ///     app's slot survives a quit / restart cycle.
    func computeSectionOrder(from cache: ItemCache) -> [String: [String]] {
        var newOrder = [String: [String]]()

        let pendingRehideTagIDs = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: pendingReturnDestinations,
            pendingRelocations: pendingRelocations,
            waitForRelaunchPrefix: Self.waitForRelaunchPrefix
        )

        // Predicate: items eligible for persistence in savedSectionOrder.
        // Profile-tracked app items (non-control with resolved sourcePID)
        // are the typical case. The visibleControlItem (Thaw chevron) is
        // also persisted so its user-chosen position within the visible
        // section survives Thaw restarts: without it, savedSectionOrder
        // describes profile-item order but not where the chevron sits
        // relative to them, and on restart the LCS planner can't detect
        // when macOS placed an app item on the wrong side of the chevron.
        // The hidden / alwaysHidden control items stay excluded; they
        // are section dividers whose position is implicit (always at the
        // section boundary) and they get inserted into desiredFlat at
        // the boundary regardless of saved order.
        func isPersistable(_ item: MenuBarItem) -> Bool {
            if item.tag == .visibleControlItem {
                return true
            }
            return !item.isControlItem && item.sourcePID != nil
        }

        // Items the notch-overflow rebalance ejected that are still sitting
        // in hidden are treated as absent from the current layout: they then
        // ride planSectionOrder's closed-app position-preserving merge and
        // keep their saved visible positions instead of being persisted as
        // hidden. An ejected item found in any OTHER section was moved by
        // the user — drop it from the tracked set and persist it normally.
        let ejectedStillInHidden = notchOverflowEjectedUIDs.intersection(
            Set(cache[.hidden].map(\.uniqueIdentifier))
        )
        notchOverflowEjectedUIDs = ejectedStillInHidden

        var allCurrentIdentifiers = Set<String>()
        var allCurrentBaseIdentifiers = Set<String>()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where isPersistable(item) {
                guard !pendingRehideTagIDs.contains(item.tag.tagIdentifier) else { continue }
                guard !ejectedStillInHidden.contains(item.uniqueIdentifier) else { continue }
                // Always track base identifier so stale saved entries for
                // transient items (Live Activities) get pruned by the
                // isStaleInstanceIndex guard below and not re-injected.
                let baseID = "\(item.tag.namespace):\(item.tag.title)"
                allCurrentBaseIdentifiers.insert(baseID)
                // Exclude transient Control Center items (Live Activities,
                // iPhone Mirroring icons) from the identifier set so their
                // ephemeral UIDs are never written to savedSectionOrder.
                // isTransientControlCenterItem requires a resolved sourcePID,
                // so also exclude CC-generic (`Item-N`) items whose sourcePID
                // is nil: those are either the same transient windows caught
                // before resolution, or third-party items degraded to
                // ambiguous CC identifiers by an XPC resolution failure
                // (#784) — neither is a stable identity worth persisting.
                guard !item.isTransientControlCenterItem,
                      !item.hasProvisionalIdentity
                else { continue }
                allCurrentIdentifiers.insert(item.uniqueIdentifier)
            }
        }

        for section in MenuBarSection.Name.allCases {
            // Current identifiers for this section, in cache iteration
            // order (which approximates left-to-right X order).
            let currentInSection = cache[section]
                .filter {
                    isPersistable($0) &&
                        !$0.isTransientControlCenterItem &&
                        !$0.hasProvisionalIdentity &&
                        !pendingRehideTagIDs.contains($0.tag.tagIdentifier) &&
                        !ejectedStillInHidden.contains($0.uniqueIdentifier)
                }
                .map(\.uniqueIdentifier)

            let oldSavedForSection = savedSectionOrder[sectionKey(for: section)] ?? []

            // Delegate to planSectionOrder for the position-preserving
            // merge of current items with closed-app entries. This
            // replaces the old "append closed apps to the end" logic
            // that destroyed user-intended positions on every quit.
            let identifiers = LayoutSolver.planSectionOrder(
                currentInSection: currentInSection,
                oldSavedForSection: oldSavedForSection,
                allCurrentIdentifiers: allCurrentIdentifiers,
                allCurrentBaseIdentifiers: allCurrentBaseIdentifiers
            )

            if !identifiers.isEmpty {
                newOrder[sectionKey(for: section)] = identifiers
            }
        }

        return newOrder
    }

    /// Extracts the current per-section item order from the given cache
    /// and persists it to savedSectionOrder. Skips the write when the
    /// order has not changed. Delegates the dict construction to
    /// computeSectionOrder so the "what does the curated section order
    /// look like?" question has a single answer used by both periodic
    /// save and profile capture.
    private func saveSectionOrder(from cache: ItemCache) {
        // Never persist an order computed from a degraded snapshot: when
        // XPC sourcePID resolution fails, third-party items collapse into
        // ambiguous Control-Center identifiers, and writing that snapshot
        // would poison the saved layout every apply matches against (#784).
        let managedItems = cache.managedItems
        let unresolvedCount = managedItems.count { $0.sourcePID == nil }
        if Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedCount, itemCount: managedItems.count) {
            MenuBarItemManager.diagLog.info(
                "saveSectionOrder: skipping, \(unresolvedCount)/\(managedItems.count) items have unresolved sourcePIDs"
            )
            return
        }
        let newOrder = computeSectionOrder(from: cache)
        guard newOrder != savedSectionOrder else { return }
        let previousOrder = savedSectionOrder
        savedSectionOrder = newOrder
        persistSavedSectionOrder()
        MenuBarItemManager.diagLog.debug("Saved section order: \(newOrder.mapValues(\.count))")
        // Logged at info, and separately from the counts above, because the
        // counts are what made #885 unattributable: they were correct while
        // the order underneath them was not.
        MenuBarItemManager.diagLog.info(
            "Saved section order changed: \(Self.sectionOrderChangeSummary(from: previousOrder, to: newOrder))"
        )
    }

    /// Returns a persistable string key for the given section name.
    private func sectionKey(for section: MenuBarSection.Name) -> String {
        switch section {
        case .visible: "visible"
        case .hidden: "hidden"
        case .alwaysHidden: "alwaysHidden"
        }
    }

    /// Returns the section name for the given persisted key, if valid.
    private static nonisolated func persistedSectionName(for key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }

    /// Returns the section name for the given persisted key, if valid.
    private func sectionName(for key: String) -> MenuBarSection.Name? {
        Self.persistedSectionName(for: key)
    }

    /// Prefix used in `pendingRelocations` values to mark items whose rehide
    /// failed terminally in the current session. The suffix is the item's
    /// `windowID` at the time of failure, used to detect app relaunches.
    private static let waitForRelaunchPrefix = "waitForRelaunch:"

    /// Returns a `pendingRelocations` sentinel value that suppresses same-session
    /// move attempts. Encodes `windowID` so that a relaunch (new windowID) clears
    /// the suppression automatically.
    private func waitForRelaunchValue(windowID: CGWindowID, section: MenuBarSection.Name) -> String {
        "\(Self.waitForRelaunchPrefix)\(windowID):\(sectionKey(for: section))"
    }

    /// Parses a `pendingRelocations` sentinel value.
    /// Returns `(windowID, section)` if the value is a wait-for-relaunch entry,
    /// or `nil` if it is a plain section key.
    private func parseWaitForRelaunch(_ value: String) -> (windowID: CGWindowID, section: MenuBarSection.Name)? {
        guard value.hasPrefix(Self.waitForRelaunchPrefix) else { return nil }
        let payload = value.dropFirst(Self.waitForRelaunchPrefix.count)
        // Format: "<windowID>:<sectionKey>"
        guard let colonIndex = payload.firstIndex(of: ":") else { return nil }
        let widString = String(payload[payload.startIndex ..< colonIndex])
        let secString = String(payload[payload.index(after: colonIndex)...])
        guard let wid = CGWindowID(widString),
              let section = sectionName(for: secString)
        else { return nil }
        return (wid, section)
    }

    /// Returns the effective section for newly detected menu bar items, falling back
    /// to hidden when the always-hidden section is currently disabled.
    var effectiveNewItemsSection: MenuBarSection.Name {
        let preferredSection = sectionName(for: newItemsPlacement.sectionKey) ?? .hidden
        if preferredSection == .alwaysHidden, appState?.settings.advanced.enableAlwaysHiddenSection != true {
            return .hidden
        }
        return preferredSection
    }

    /// Returns the insertion index for the New Items badge within the given section.
    func newItemsBadgeIndex(in section: MenuBarSection.Name, itemIdentifiers: [String]) -> Int? {
        guard effectiveNewItemsSection == section else {
            return nil
        }

        if sectionName(for: newItemsPlacement.sectionKey) == section,
           let anchorIdentifier = newItemsPlacement.anchorIdentifier,
           let anchorIndex = resolvedNewItemsAnchorIndex(
               for: anchorIdentifier,
               in: itemIdentifiers
           )
        {
            switch newItemsPlacement.relation {
            case .leftOfAnchor:
                return anchorIndex
            case .rightOfAnchor:
                return anchorIndex + 1
            case .sectionDefault:
                break
            }
        }

        // Anchor missing from this section (e.g. the notch-overflow
        // relocated the anchor item to hidden). Walk the active
        // profile's saved order outward from the missing anchor's
        // saved position to find its nearest sibling that IS still
        // present in this section, and place the badge against that
        // sibling. This preserves the badge's saved relative position
        // when its primary anchor is unavailable, instead of dropping
        // it to the section's default index.
        if let nearestIndex = badgeIndexFromNearestProfileSibling(
            in: section,
            itemIdentifiers: itemIdentifiers
        ) {
            return nearestIndex
        }

        return defaultNewItemsBadgeIndex(in: section, itemCount: itemIdentifiers.count)
    }

    /// Walks the active profile's saved item order outward from the
    /// badge's missing anchor and returns an insertion index against
    /// the first sibling that's still present in `itemIdentifiers`.
    /// Walks in the direction implied by the saved relation first
    /// (leftOfAnchor → walk left toward earlier siblings; rightOfAnchor
    /// → walk right toward later siblings), then the opposite direction
    /// if the first walk doesn't find a survivor. Returns nil when no
    /// active profile is loaded, no profile order exists for this
    /// section, or no sibling survives.
    private func badgeIndexFromNearestProfileSibling(
        in section: MenuBarSection.Name,
        itemIdentifiers: [String]
    ) -> Int? {
        guard let anchorIdentifier = newItemsPlacement.anchorIdentifier,
              newItemsPlacement.relation != .sectionDefault,
              sectionName(for: newItemsPlacement.sectionKey) == section,
              let profileOrder = activeProfileLayout?.itemOrder[sectionKey(for: section)],
              let anchorPos = profileOrder.firstIndex(of: anchorIdentifier)
        else {
            return nil
        }
        let walkLeftFirst = newItemsPlacement.relation == .leftOfAnchor
        // First pass: walk in the direction the badge was relative to
        // the anchor. If badge was leftOfAnchor, the badge sat between
        // some left-side sibling and the anchor; finding that left
        // sibling and placing rightOfThatSibling reproduces the saved
        // position. Symmetric for rightOfAnchor.
        return Self.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: anchorPos,
            itemIdentifiers: itemIdentifiers,
            walkLeftFirst: walkLeftFirst
        )
    }

    /// Returns the badge index reproducing a saved position, by finding the
    /// nearest profile sibling that is still present.
    ///
    /// Both directions are searched; the caller's preferred direction wins when
    /// each finds a sibling. A left-side match places the badge after that
    /// sibling, a right-side match places it before.
    ///
    /// - Parameters:
    ///   - profileOrder: The saved identifier order for the section.
    ///   - anchorPos: The anchor's position within `profileOrder`.
    ///   - itemIdentifiers: The identifiers currently in the section.
    ///   - walkLeftFirst: Whether the badge sat left of the anchor.
    ///
    /// - Returns: An index into `itemIdentifiers`, or `nil` when no sibling
    ///   from the saved order is still present.
    static nonisolated func badgeIndex(
        profileOrder: [String],
        anchorPos: Int,
        itemIdentifiers: [String],
        walkLeftFirst: Bool
    ) -> Int? {
        func leftward() -> Int? {
            profileOrder[..<anchorPos]
                .reversed()
                .firstNonNil { itemIdentifiers.firstIndex(of: $0) }
                .map { $0 + 1 }
        }
        func rightward() -> Int? {
            profileOrder[(anchorPos + 1)...]
                .firstNonNil { itemIdentifiers.firstIndex(of: $0) }
        }

        return walkLeftFirst
            ? leftward() ?? rightward()
            : rightward() ?? leftward()
    }

    /// Updates the preferred destination for newly detected menu bar items using the
    /// badge position from the layout editor.
    func updateNewItemsPlacement(
        section: MenuBarSection.Name,
        arrangedViews: [LayoutBarArrangedView]
    ) {
        let resolvedSection: MenuBarSection.Name = if section == .alwaysHidden, appState?.settings.advanced.enableAlwaysHiddenSection != true {
            .hidden
        } else {
            section
        }

        let updatedPlacement: NewItemsPlacement
        if let badgeIndex = arrangedViews.firstIndex(where: { $0.isNewItemsBadge }) {
            let rightNeighbor = arrangedViews[(badgeIndex + 1) ..< arrangedViews.count]
                .compactMap { view -> MenuBarItem? in
                    if case let .item(item) = view.kind {
                        return item
                    }
                    return nil
                }
                .first

            let leftNeighbor = arrangedViews[..<badgeIndex]
                .reversed()
                .compactMap { view -> MenuBarItem? in
                    if case let .item(item) = view.kind {
                        return item
                    }
                    return nil
                }
                .first

            if let rightNeighbor {
                updatedPlacement = NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: persistedNewItemsAnchorIdentifier(for: rightNeighbor),
                    relation: .leftOfAnchor
                )
            } else if let leftNeighbor {
                updatedPlacement = NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: persistedNewItemsAnchorIdentifier(for: leftNeighbor),
                    relation: .rightOfAnchor
                )
            } else {
                updatedPlacement = NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: nil,
                    relation: .sectionDefault
                )
            }
        } else {
            updatedPlacement = NewItemsPlacement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: nil,
                relation: .sectionDefault
            )
        }

        guard newItemsPlacement != updatedPlacement else {
            return
        }

        newItemsPlacement = updatedPlacement
        persistNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("Updated new item destination to \(resolvedSection.logString) at relation \(updatedPlacement.relation.rawValue)")
    }

    /// Applies a previously captured ``NewItemsPlacement`` (from a profile),
    /// clamping to the hidden section when the always-hidden section is
    /// disabled. Persists the updated preference.
    ///
    /// When clamping from `alwaysHidden` to `hidden`, the original anchor
    /// references an alwaysHidden item that won't resolve in the hidden
    /// section. Rather than letting the badge fall through to the
    /// `.hidden`/always-hidden-disabled default (which is the leftmost
    /// slot, farthest from the clock), we re-anchor to the rightmost
    /// existing hidden item with `.leftOfAnchor` so the badge lands on
    /// the clock-side edge of the section; the spot users reach first
    /// when they expand the hidden section.
    func applyNewItemsPlacement(_ placement: NewItemsPlacement) {
        let preferredSection = sectionName(for: placement.sectionKey) ?? .hidden
        let alwaysHiddenDisabled = appState?.settings.advanced.enableAlwaysHiddenSection != true
        let clampedToHidden = preferredSection == .alwaysHidden && alwaysHiddenDisabled
        let resolvedSection: MenuBarSection.Name = clampedToHidden ? .hidden : preferredSection

        let adjusted = if clampedToHidden {
            if let rightmostHiddenItem = itemCache[.hidden].first(
                where: { !$0.isControlItem && $0.tag.instanceIndex == 0 }
            ) {
                NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: persistedNewItemsAnchorIdentifier(for: rightmostHiddenItem),
                    relation: .leftOfAnchor
                )
            } else {
                // Clamping, but the hidden section is empty. Drop the
                // stale alwaysHidden anchor and fall back to the section
                // default so a later re-save doesn't resurface it.
                NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: nil,
                    relation: .sectionDefault
                )
            }
        } else {
            NewItemsPlacement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: placement.anchorIdentifier,
                relation: placement.relation
            )
        }

        guard newItemsPlacement != adjusted else { return }

        newItemsPlacement = adjusted
        persistNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("Applied profile new item destination to \(resolvedSection.logString) at relation \(adjusted.relation.rawValue)")
    }

    /// Returns the move destination that inserts a new item into the preferred section.
    private func newItemsMoveDestination(
        for controlItems: ControlItemPair,
        among items: [MenuBarItem]
    ) -> MoveDestination {
        let targetSection = effectiveNewItemsSection
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        let activelyShownTags = Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))
        let liveSectionItems = items.filter { item in
            guard !item.isControlItem else { return false }
            guard !activelyShownTags.contains(item.tag.tagIdentifier) else { return false }
            return context.findSection(for: item) == targetSection
        }

        if sectionName(for: newItemsPlacement.sectionKey) == targetSection,
           let anchorIdentifier = newItemsPlacement.anchorIdentifier,
           let anchorItem = resolvedNewItemsAnchorItem(
               for: anchorIdentifier,
               in: liveSectionItems
           )
        {
            switch newItemsPlacement.relation {
            case .leftOfAnchor:
                return .leftOfItem(anchorItem)
            case .rightOfAnchor:
                return .rightOfItem(anchorItem)
            case .sectionDefault:
                break
            }
        }

        switch targetSection {
        case .visible:
            return .rightOfItem(controlItems.hidden)
        case .hidden:
            if appState?.settings.advanced.enableAlwaysHiddenSection == true {
                if let alwaysHidden = controlItems.alwaysHidden {
                    return .rightOfItem(alwaysHidden)
                } else {
                    return .leftOfItem(controlItems.hidden)
                }
            } else {
                return .leftOfItem(controlItems.hidden)
            }
        case .alwaysHidden:
            if let alwaysHidden = controlItems.alwaysHidden {
                return .leftOfItem(alwaysHidden)
            } else {
                return .leftOfItem(controlItems.hidden)
            }
        }
    }

    private func persistedNewItemsAnchorIdentifier(for item: MenuBarItem) -> String {
        item.uniqueIdentifier
    }

    private func resolvedNewItemsAnchorIndex(
        for anchorIdentifier: String,
        in itemIdentifiers: [String]
    ) -> Int? {
        if let exactMatch = itemIdentifiers.firstIndex(of: anchorIdentifier) {
            return exactMatch
        }

        let stableIdentifier = stableNewItemsAnchorIdentifier(from: anchorIdentifier)

        return itemIdentifiers.firstIndex { identifier in
            stableNewItemsAnchorIdentifier(from: identifier) == stableIdentifier
        }
    }

    private func resolvedNewItemsAnchorItem(
        for anchorIdentifier: String,
        in items: [MenuBarItem]
    ) -> MenuBarItem? {
        if let exactMatch = items.first(where: { $0.uniqueIdentifier == anchorIdentifier }) {
            return exactMatch
        }

        let stableIdentifier = stableNewItemsAnchorIdentifier(from: anchorIdentifier)

        return items.first { item in
            persistedNewItemsAnchorIdentifier(for: item) == stableIdentifier
        }
    }

    private func stableNewItemsAnchorIdentifier(from identifier: String) -> String {
        identifier
    }

    private func defaultNewItemsBadgeIndex(in section: MenuBarSection.Name, itemCount: Int) -> Int {
        switch section {
        case .visible:
            return 0
        case .hidden:
            if appState?.settings.advanced.enableAlwaysHiddenSection == true {
                return 0
            }
            return itemCount
        case .alwaysHidden:
            return itemCount
        }
    }

    private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        MenuBarItemManager.diagLog.debug("performSetup: starting MenuBarItemManager setup")
        self.appState = appState
        loadKnownItemIdentifiers()
        loadPinnedBundleIDs()
        loadPendingRelocations()
        loadSavedSectionOrder()
        loadNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("performSetup: loaded \(knownItemIdentifiers.count) known identifiers, \(pinnedHiddenBundleIDs.count) pinned hidden, \(pinnedAlwaysHiddenBundleIDs.count) pinned always-hidden, \(savedSectionOrder.values.map(\.count)) saved order entries")
        // On first launch (no known identifiers), avoid auto-relocating the leftmost item
        // so everything remains in the hidden section until the user interacts.
        suppressNextNewLeftmostItemRelocation = knownItemIdentifiers.isEmpty
        configureCancellables(with: appState)
        initialCacheTask?.cancel()
        MenuBarItemManager.diagLog.debug("performSetup: scheduling initial cacheItemsRegardless off the startup critical path")
        self.initialCacheTask = Task { @MainActor [weak self] in
            guard let self else { return }
            MenuBarItemManager.diagLog.debug(
                "performSetup: initial cacheItemsRegardless started (fast path without sourcePID resolution)"
            )
            for attempt in 1 ... 10 {
                if Task.isCancelled {
                    return
                }
                await cacheItemsRegardless(resolveSourcePID: false)
                if itemCache.displayID != nil {
                    if attempt > 1 {
                        MenuBarItemManager.diagLog.debug(
                            "performSetup: fast initial cache succeeded on retry \(attempt)"
                        )
                    }
                    // Fast path succeeded; kick off authoritative PID resolution
                    // concurrently so we don't block restore logic.
                    Task { @MainActor [weak self] in
                        await self?.cacheItemsRegardless(resolveSourcePID: true)
                    }
                    break
                }

                MenuBarItemManager.diagLog.debug(
                    "performSetup: fast initial cache missing control items on attempt \(attempt), retrying shortly"
                )
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
            MenuBarItemManager.diagLog.debug("performSetup: initial cache complete, items in cache: visible=\(itemCache[.visible].count), hidden=\(itemCache[.hidden].count), alwaysHidden=\(itemCache[.alwaysHidden].count), managedItems=\(itemCache.managedItems.count)")
        }
        // Suppress restore and section-order saves for a settling period after launch.
        // During login (system uptime < 60 s) many apps load over ~30 s, each triggering
        // a cache cycle; without this guard every launch notification causes a restore
        // that conflicts with the next, producing the "icon parade" effect.
        // After the settling period ends, one final cacheItemsRegardless() enforces the
        // user's saved layout against whatever macOS placed items.
        startSettlingPeriod(reason: "performSetup")
        MenuBarItemManager.diagLog.debug("performSetup: MenuBarItemManager setup complete")
    }

    /// Starts a settling period during which restore and section-order saves
    /// are suppressed. The settling task polls cacheItemsRegardless until
    /// the menu bar has stabilized; then runs two final cache passes that
    /// trigger the saved-layout restore.
    ///
    /// Exit conditions, in priority order:
    /// 1. If expectedBundleIDs is non-empty: exit when all expected bundle
    ///    IDs are present in the cache AND sourcePIDs have resolved (≤1 nil).
    ///    This is the post-relaunch-wave case where we know exactly which
    ///    apps we're waiting on.
    /// 2. Otherwise: exit when the managed-item count has been stable for
    ///    stableTarget consecutive polls AND sourcePIDs have resolved.
    ///    This is the cold-start case where we don't know the expected set.
    /// 3. Hard upper bound is maxDuration from now. Sized generously
    ///    because some apps can take tens of seconds between process
    ///    respawn and menu bar item reattachment; the early-exit in (1)
    ///    or (2) ends settling immediately once the cache has caught up,
    ///    so the cap only matters when an app is genuinely slow or dead.
    ///
    /// On re-entry (e.g. a permission re-grant during login, or a relaunch
    /// wave fired by MenuBarItemSpacingManager): take the MAX of the
    /// previous deadline and the newly computed one so a second call does
    /// not silently truncate an in-flight window.
    func startSettlingPeriod(
        reason: String,
        expectedBundleIDs: Set<String> = [],
        maxDuration: Duration = .seconds(60)
    ) {
        // Classify the incoming call so we can refuse to demote a more
        // authoritative settling that's already in flight.
        let mergedExpected = settlingExpectedBundleIDs.union(expectedBundleIDs)
        let incomingKind: SettlingKind = if !mergedExpected.isEmpty {
            .expectedSet
        } else if reason == "performSetup" {
            .cold
        } else {
            .preflight
        }

        // Boot race: a cold (performSetup) or expected-set settling must
        // not be torn down by a transient preflight that the boot path
        // also kicks off (DisplaySettingsManager.applyActiveDisplaySpacing,
        // ProfileManager.layoutTask). Preserve the merged expected set so
        // a later non-preflight call still has it; otherwise return.
        if let existing = settlingKind,
           incomingKind == .preflight,
           existing == .cold || existing == .expectedSet
        {
            settlingExpectedBundleIDs = mergedExpected
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling start ignored; \(existing) settling already in flight"
            )
            return
        }

        let newMaxDeadline = ContinuousClock.now.advanced(by: maxDuration)
        let maxDeadline = max(settlingDeadline ?? newMaxDeadline, newMaxDeadline)
        settlingDeadline = maxDeadline
        settlingExpectedBundleIDs = mergedExpected
        settlingKind = incomingKind
        // Cancel any in-flight settling task before starting a new one.
        // The cancelled task exits without touching shared state; this call
        // manages isInStartupSettling for the new period.
        startupSettlingTask?.cancel()
        isInStartupSettling = true
        didAttemptEarlySavedLayoutApply = false
        MenuBarItemManager.diagLog.debug("\(reason): settling period started (max duration: \(maxDuration))")
        // @MainActor ensures the flag flip and final cache call are never
        // interleaved with notification-triggered cache cycles between them.
        startupSettlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // No-op when initialCacheTask is nil (i.e. settling started
            // outside performSetup, e.g. after a relaunch wave).
            await self.initialCacheTask?.value

            // --- Hybrid signal + timer settling ---
            // Two exit modes (besides the deadline backstop):
            // - "expected-set" mode (post-relaunch-wave): we know exactly
            //   which bundle IDs we just relaunched, so we wait for all of
            //   them to appear in the cache before declaring settled. Much
            //   tighter than the count-stability heuristic; once slow
            //   apps have all reattached, we exit immediately regardless
            //   of timer.
            // - "count-stability" mode (cold start, no expected set): poll
            //   until the managed-item count has been stable for several
            //   consecutive polls AND sourcePIDs have resolved.
            // Hard upper bound is maxDeadline (computed above), so an
            // app that never reattaches (process truly dead) doesn't
            // strand the layout pass.
            let stableTarget = 3
            var lastSeenCount = -1
            var stablePolls = 0
            let waitingFor = mergedExpected
            let useExpectedSet = !waitingFor.isEmpty
            if useExpectedSet {
                MenuBarItemManager.diagLog.debug(
                    "\(reason): waiting for \(waitingFor.count) expected bundle ID(s) to reattach"
                )
            }

            while !Task.isCancelled {
                if ContinuousClock.now > maxDeadline {
                    MenuBarItemManager.diagLog.debug(
                        "\(reason): settling hit max deadline (\(maxDeadline)), ending with fallback"
                    )
                    break
                }

                await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)
                let managedCount = itemCache.managedItems.count
                let unresolved = itemCache.managedItems.count(where: { $0.sourcePID == nil })
                let pidsOK = managedCount > 0 && unresolved <= 1

                if useExpectedSet {
                    let presentBundleIDs: Set<String> = Set(
                        itemCache.managedItems.compactMap { item in
                            if case let .string(bid) = item.tag.namespace {
                                return bid
                            }
                            return nil
                        }
                    )
                    let stillMissing = waitingFor.subtracting(presentBundleIDs)
                    if stillMissing.isEmpty, pidsOK {
                        MenuBarItemManager.diagLog.debug(
                            "\(reason): all \(waitingFor.count) expected bundle ID(s) reattached, ending early"
                        )
                        break
                    }
                    MenuBarItemManager.diagLog.debug(
                        "\(reason): \(stillMissing.count) bundle ID(s) still missing: \(stillMissing.sorted().joined(separator: ", "))"
                    )
                } else {
                    if pidsOK, managedCount == lastSeenCount {
                        stablePolls += 1
                        if stablePolls >= stableTarget {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): settled (count=\(managedCount) stable for \(stableTarget) polls, \(unresolved) nil PIDs), ending early"
                            )
                            break
                        }
                    } else {
                        if managedCount != lastSeenCount {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): count changed \(lastSeenCount) -> \(managedCount) (\(unresolved) nil PIDs), resetting stability"
                            )
                        }
                        stablePolls = 0
                        lastSeenCount = managedCount
                    }
                }

                // Short sleep before next poll; exit immediately if cancelled.
                do {
                    try await Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(100))
                } catch is CancellationError {
                    MenuBarItemManager.diagLog.debug("\(reason): settling task cancelled")
                    return
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else {
                return
            }

            isInStartupSettling = false
            settlingDeadline = nil
            settlingExpectedBundleIDs.removeAll()
            settlingKind = nil
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling period ended"
            )

            // Launch-time profile apply: when a profile is bound to
            // the active display, the profile (not the live
            // savedSectionOrder) is the source of truth for the
            // layout. Without this, the cache cycle below would fire
            // applySavedLayout which restores whatever the live
            // savedSectionOrder happens to be, which can diverge
            // from the profile spec across restarts (manual drags,
            // unmanaged items inserted by NewItemsPlacement, etc.).
            // Awaiting layoutTask ensures the profile apply runs to
            // completion (including arming isApplyingProfileLayout)
            // before the cache cycles below trigger applySavedLayout;
            // that gate then keeps savedOrder from racing the
            // profile apply on launch.
            if let appState = self.appState,
               appState.profileManager.activeProfileID != nil
            {
                MenuBarItemManager.diagLog.info(
                    "\(reason): applying active display profile after settling"
                )
                appState.profileManager.reapplyActiveProfile()
                await appState.profileManager.layoutTask?.value
            }

            MenuBarItemManager.diagLog.debug(
                "\(reason): running fast restore without sourcePID resolution"
            )
            // skipRecentMoveCheck: true; relocateNewLeftmostItems/relocatePendingItems
            // may have stamped lastMoveOperationTimestamp during settling; without this
            // flag the final restore would be silently skipped by the 5 s cooldown.
            //
            // skipRecentMoveCheck only clears cacheItemsRegardless's own 1 s gate.
            // applySavedLayout keeps a separate 5 s gate, and this pass reaches it
            // through the recache relocateNewLeftmostItems schedules — so the bypass
            // has to be requested explicitly and carried across that hand-off.
            await cacheItemsRegardless(
                skipRecentMoveCheck: true,
                resolveSourcePID: false,
                bypassSavedLayoutCooldown: true
            )
            // Final authoritative recache that resolves source PIDs so items used later
            // (which read item.sourcePID ?? item.ownerPID) reflect the true source PID.
            // skipRecentMoveCheck: true ensures this pass is never suppressed by the
            // 1-second recent-move cooldown stamped by the fast restore above.
            await cacheItemsRegardless(
                skipRecentMoveCheck: true,
                resolveSourcePID: true,
                bypassSavedLayoutCooldown: true
            )
        }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with _: AppState) {
        var c = Set<AnyCancellable>()

        // When any app launches, refresh the cache to detect new menu bar items
        // (e.g., apps with "unremembered" icons that need restoration) and restore
        // any items that moved to incorrect sections after their app restarted.
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )
        .debounce(for: 1, scheduler: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self else { return }
            let launchedBundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MenuBarItemManager.diagLog.debug(
                "App launched\(launchedBundleID.map { " (\($0))" } ?? ""), refreshing cache for potential new items"
            )

            // If the launched app is one we already track a menu bar item for,
            // it just relaunched (e.g. an in-app update): its status item is
            // about to disappear and re-register, churning the bar for a few
            // seconds. Start a settling period keyed on its bundle ID so the
            // move pass (applyProfileLayout waits on waitForStartupSettlingToEnd)
            // holds off until the item has re-paired. Without this the bulk apply ran
            // on the transient layout and swept hidden items into the visible
            // section. The period exits the instant the bundle ID reappears
            // with a resolved PID (median ~3s in field logs); maxDuration is
            // only a backstop. Apps with no tracked menu bar item arm nothing,
            // so there is no deferral for ordinary launches.
            if let launchedBundleID,
               MenuBarItemManager.tracksMenuBarItem(bundleID: launchedBundleID, in: self.knownItemIdentifiers)
            {
                self.startSettlingPeriod(
                    reason: "appLaunch",
                    expectedBundleIDs: [launchedBundleID],
                    maxDuration: .seconds(8)
                )
            }
            Task { [weak self] in
                await self?.cacheItemsRegardless()
                // Many apps register their NSStatusItem more than 1s after
                // didLaunch fires, so the initial cache pass above sees no
                // new window IDs and relocateNewLeftmostItems no-ops. Re-check
                // at +2.5s and +5s to catch late arrivals; cacheItemsIfNeeded
                // bails when window IDs are unchanged, so this is cheap when
                // the item already showed up on the first pass. A cancelled
                // sleep skips the remaining re-checks.
                guard await (try? Task.sleep(for: .seconds(2.5))) != nil else { return }
                await self?.cacheItemsIfNeeded()
                guard await (try? Task.sleep(for: .seconds(2.5))) != nil else { return }
                await self?.cacheItemsIfNeeded()
            }
        }
        .store(in: &c)

        // When any app terminates, refresh the cache (items may have disappeared).
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )
        .debounce(for: 1, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            MenuBarItemManager.diagLog.debug("App terminated, refreshing cache")
            Task {
                await self.cacheItemsIfNeeded()
            }
        }
        .store(in: &c)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        )
        .debounce(for: 0.5, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                await self.cacheItemsIfNeeded()
            }
        }
        .store(in: &c)

        // `navigationState` (AppNavigationState) is @Observable (wave 3), so
        // its old `$settingsNavigationIdentifier`/`$isSettingsPresented`
        // Combine projections are gone. Both old subscribers wanted the same
        // outcome (refresh the image cache once Menu Bar Layout becomes the
        // presented settings pane), just triggered from two different edges
        // (identifier changing while already presented, vs. presented
        // becoming true while identifier is already .menuBarLayout), so they
        // are combined into a single Observations-Task tracking both.
        navigationStateObservationTask = Task { [weak self] in
            guard let appState = self?.appState else { return }
            let changes = Observations { [weak navigationState = appState.navigationState] in
                (navigationState?.settingsNavigationIdentifier, navigationState?.isSettingsPresented)
            }
            for await (identifier, isPresented) in changes {
                guard isPresented == true, identifier == .menuBarLayout else { continue }
                guard let self else { return }
                await self.appState?.imageCache.updateCache(sections: MenuBarSection.Name.allCases)
            }
        }

        // Rescan on menu bar window-list changes. cacheItemsIfNeeded compares
        // the current items-only window IDs against the cached set and recaches
        // only when they differ, so this catches both late-registering items
        // (background-only apps like OneDrive) and the transient bundle-ID
        // marker windows that source-PID marker-pair resolution depends on,
        // which can appear and disappear between sparser app-event triggers. A
        // short interval keeps marker-pair latency low; the windowID comparison
        // bails fast and triggers no recache when nothing changed.
        cacheTickCancellable = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.cacheItemsIfNeeded()
                }
            }

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether the most recent
    /// menu bar item move operation occurred within the given duration.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        guard let timestamp = lastMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }

    /// Records an explicit user move, either a direct Cmd-drag or a completed
    /// drag in the Layout editor.
    ///
    /// A user-chosen arrangement is authoritative, so it clears both the
    /// failed-batch save latch and any pending automatic-divergence reading.
    func recordExternalMoveOperation() {
        lastMoveOperationTimestamp = .now
        pendingDivergenceObservedAt = nil
        recordBulkApplyOutcome(unenactedMoveCount: 0)
    }
}

// MARK: - Cache Gate

extension MenuBarItemManager {
    enum LayoutResetTarget: Sendable {
        case visible
        case hidden
        case alwaysHidden

        nonisolated func contains(
            itemBounds: CGRect,
            hiddenBounds: CGRect,
            alwaysHiddenBounds: CGRect?
        ) -> Bool {
            switch self {
            case .visible:
                return itemBounds.minX >= hiddenBounds.maxX
            case .hidden:
                guard itemBounds.maxX <= hiddenBounds.minX else { return false }
                guard let alwaysHiddenBounds else { return true }
                return itemBounds.minX >= alwaysHiddenBounds.maxX
            case .alwaysHidden:
                guard let alwaysHiddenBounds else { return false }
                return itemBounds.maxX <= alwaysHiddenBounds.minX
            }
        }

        var logString: String {
            switch self {
            case .visible: "visible"
            case .hidden: "hidden"
            case .alwaysHidden: "always-hidden"
            }
        }

        nonisolated var movesAllCandidatesInFirstPass: Bool {
            switch self {
            case .hidden: true
            case .visible, .alwaysHidden: false
            }
        }

        nonisolated var requiresAlwaysHiddenDivider: Bool {
            switch self {
            case .alwaysHidden: true
            case .visible, .hidden: false
            }
        }
    }

    /// Serializes cache operations to prevent races between concurrent
    /// `cacheItemsRegardless` calls. When a relocation move is in flight,
    /// a concurrent call could snapshot item positions before the move
    /// completes, caching them in the wrong section.
    ///
    /// Concurrent calls are dropped; the next trigger (space change,
    /// periodic refresh, app launch notification) will pick up changes.
    private actor CacheGate {
        private var isInProgress = false

        func begin() -> Bool {
            guard !isInProgress else { return false }
            isInProgress = true
            return true
        }

        func end() {
            isInProgress = false
        }
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final class CacheActor {
        /// Stored task for the current cache operation.
        private var cacheTask: Task<Void, Never>?

        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// A mapping from window identifiers to their resolved source process
        /// identifiers from the previous cache cycle. Used to detect and correct
        /// transient sourcePID resolution errors (e.g. stale AX data after moves).
        private(set) var cachedItemPIDs = [CGWindowID: pid_t]()

        /// Window identifiers of the system clone windows seen in the most
        /// recent cache cycle. cacheItemsIfNeeded filters these out of its
        /// change comparison so a transient clone appearing or vanishing
        /// doesn't read as a layout change and trigger a recache.
        private(set) var cachedCloneWindowIDs = Set<CGWindowID>()

        /// Window identifiers of Control-Center-generic (`Item-N`) items seen
        /// in the most recent cache cycle. These windows churn — Live
        /// Activities and other transient Control Center widgets appear,
        /// vanish, and get new windowIDs while the visible item count stays
        /// stable — so applySavedLayout's windowID-change gate ignores their
        /// disappearance instead of dispatching a full bulk apply (#736).
        private(set) var cachedControlCenterGenericWindowIDs = Set<CGWindowID>()

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(_ operation: @escaping () async -> Void) async {
            cacheTask?.cancel()
            _ = await cacheTask?.value
            cacheTask = nil
            await operation()
        }

        /// Updates the list of cached menu bar item window identifiers.
        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        /// Updates the set of cached system clone window identifiers.
        func updateCachedCloneWindowIDs(_ ids: Set<CGWindowID>) {
            cachedCloneWindowIDs = ids
        }

        /// Updates the set of cached Control-Center-generic window identifiers.
        func updateCachedControlCenterGenericWindowIDs(_ ids: Set<CGWindowID>) {
            cachedControlCenterGenericWindowIDs = ids
        }

        /// Updates the mapping from window identifiers to source process identifiers.
        func updateCachedItemPIDs(_ pids: [CGWindowID: pid_t]) {
            cachedItemPIDs = pids
        }

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
            cachedItemPIDs.removeAll()
            // Clear clone IDs alongside the main set so the two don't drift.
            // Leaving stale clone IDs here would let cacheItemsIfNeeded filter
            // a recycled windowID out of its comparison before the recache
            // that follows this reset repopulates the set.
            cachedCloneWindowIDs.removeAll()
            cachedControlCenterGenericWindowIDs.removeAll()
        }
    }

    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// Storage for cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        /// Creates a cache with the given display identifier.
        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        /// Returns the managed menu bar items for the given section.
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section]
        }

        /// Returns the address for the menu bar item with the given tag,
        /// if it exists in the cache.
        func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(matching: tag) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        /// Inserts the given menu bar item into the cache at the specified
        /// destination.
        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination) {
            let targetTag = destination.targetItem.tag

            if targetTag == .hiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.hidden].append(item)
                case .rightOfItem:
                    self[.visible].insert(item, at: 0)
                }
                return
            }

            if targetTag == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.alwaysHidden].append(item)
                case .rightOfItem:
                    self[.hidden].insert(item, at: 0)
                }
                return
            }

            guard case (let section, var index)? = address(for: targetTag) else {
                return
            }

            if case .rightOfItem = destination {
                let range = self[section].startIndex ... self[section].endIndex
                index = (index + 1).clamped(to: range)
            }

            self[section].insert(item, at: index)
        }

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    struct ControlItemPair {
        nonisolated enum Resolution: Equatable, Sendable {
            case identity
            case axFrameCorrelation
        }

        nonisolated let hidden: MenuBarItem
        nonisolated let alwaysHidden: MenuBarItem?
        nonisolated let resolution: Resolution

        /// AX-frame correlation identifies likely controls geometrically, but
        /// that evidence is not strong enough to reposition section dividers.
        nonisolated var canRepositionControlItems: Bool {
            resolution != .axFrameCorrelation
        }

        /// Creates a control item pair from already-known control items.
        ///
        /// Used by test fixtures and by callers that have already resolved the
        /// hidden and always-hidden items themselves. Production discovery from
        /// a live menu bar uses the failable initializer below.
        ///
        /// Marked `nonisolated` so test fixtures (compiled without the app
        /// target's MainActor default) and other non-MainActor callers can
        /// construct a pair from already-resolved items without a hop; the
        /// failable `init?` below stays implicitly `@MainActor` since it
        /// performs AX-frame correlation.
        nonisolated init(
            hidden: MenuBarItem,
            alwaysHidden: MenuBarItem?,
            resolution: Resolution = .identity
        ) {
            self.hidden = hidden
            self.alwaysHidden = alwaysHidden
            self.resolution = resolution
        }

        /// Creates a control item pair from a list of menu bar items.
        ///
        /// Window IDs from this process's `NSStatusItem` windows are the
        /// authoritative lookup when available. Tag and title lookup remain
        /// fallbacks for startup, when those window IDs may not exist yet.
        ///
        /// On macOS 26 (Tahoe), all menu bar item windows are owned by Control
        /// Center and the item title reported by `kCGWindowName` may differ from
        /// the `NSStatusItem` autosaveName used to build the expected tag, so the
        /// primary lookup can fail.
        init?(
            items: inout [MenuBarItem],
            hiddenControlItemWindowID: CGWindowID? = nil,
            alwaysHiddenControlItemWindowID: CGWindowID? = nil
        ) {
            // Primary lookup: match the windows this process created. Duplicate
            // Thaw instances can produce identical titles; tag assignment then
            // favors the lowest window ID, which may belong to another process.
            if let hiddenWID = hiddenControlItemWindowID,
               let hiddenIndex = items.firstIndex(where: { $0.windowID == hiddenWID })
            {
                self.hidden = items.remove(at: hiddenIndex)
                if let alwaysHiddenWID = alwaysHiddenControlItemWindowID {
                    // Do not adopt a duplicate control window when the
                    // authoritative always-hidden ID is known but absent.
                    if let alwaysHiddenIndex = items.firstIndex(where: { $0.windowID == alwaysHiddenWID }) {
                        self.alwaysHidden = items.remove(at: alwaysHiddenIndex)
                    } else {
                        self.alwaysHidden = nil
                    }
                } else {
                    self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
                }
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via window ID")
                return
            }

            // Authoritative recovery: ask the window server about the windows
            // this process created, instead of searching the enumerated list
            // for them.
            //
            // The primary lookup above can only match a control item that is
            // *in* `items`, and it drops out whenever the window is parked
            // far offscreen or filtered off the active space. The two
            // fallbacks below then need identity channels — namespace, or a
            // resolved sourcePID — that fail together exactly when the item
            // service's PID resolution degrades, which is the same failure
            // that stranded the window in the first place. That left frame
            // correlation guessing at Thaw's own dividers (#923, #924, #927).
            //
            // Thaw holds these windows, so it does not have to guess. Only
            // attempted when the caller supplied an authoritative ID, and
            // only for a window the window server still knows.
            if let hiddenWID = hiddenControlItemWindowID,
               Self.shouldRecoverOwnControlItem(
                   authoritativeWindowID: hiddenWID,
                   itemWindowIDs: Set(items.map(\.windowID))
               ),
               let hidden = MenuBarItem.ownControlItem(windowID: hiddenWID)
            {
                self.hidden = hidden
                if let alwaysHiddenWID = alwaysHiddenControlItemWindowID {
                    if let alwaysHiddenIndex = items.firstIndex(where: { $0.windowID == alwaysHiddenWID }) {
                        self.alwaysHidden = items.remove(at: alwaysHiddenIndex)
                    } else {
                        // Same reasoning for the partner; a nil always-hidden
                        // is a legitimate state (the section can be disabled),
                        // so failure here is not fatal to the pair.
                        self.alwaysHidden = MenuBarItem.ownControlItem(windowID: alwaysHiddenWID)
                    }
                } else {
                    self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
                }
                self.resolution = .identity
                MenuBarItemManager.diagLog.info(
                    "ControlItemPair: recovered hidden control item \(hiddenWID) from its own window; it was absent from the \(items.count)-item list"
                )
                return
            }

            // Fallback 1: match by tag (namespace + title).
            if let hidden = items.removeFirst(matching: .hiddenControlItem) {
                self.hidden = hidden
                self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via tag")
                return
            }

            // Fallback 2: match by sourcePID (our own process) + known title.
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let hiddenTitle = ControlItem.Identifier.hidden.rawValue
            let alwaysHiddenTitle = ControlItem.Identifier.alwaysHidden.rawValue

            if let idx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == hiddenTitle }) {
                self.hidden = items.remove(at: idx)
                if let ahIdx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == alwaysHiddenTitle }) {
                    self.alwaysHidden = items.remove(at: ahIdx)
                } else {
                    self.alwaysHidden = nil
                }
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via sourcePID and title")
                return
            }

            // Fallback 3 (strategy 4, #754): AX-frame correlation against
            // Thaw's own AX elements. Thaw's control items are its own
            // NSStatusItems, so their AX elements (reached via Thaw's own
            // process, not any third party) carry frames that can be
            // correlated against the candidate items' CG window bounds even
            // when tag, title, and window ID all fail to match — this is
            // the only strategy that lets Thaw identify its OWN control
            // items when every CG-side identity channel has degraded.
            if let pair = Self.matchViaAXFrame(items: &items) {
                self.hidden = pair.hidden
                self.alwaysHidden = pair.alwaysHidden
                self.resolution = .axFrameCorrelation
                return
            }

            MenuBarItemManager.diagLog.warning(
                "ControlItemPair: unresolved; no strategy identified the hidden control item among \(items.count) item(s)"
            )
            return nil
        }

        /// Whether to rebuild one of Thaw's own control items directly from
        /// its window rather than continuing down the identity fallbacks.
        ///
        /// Only when the caller supplied an authoritative window ID *and*
        /// that window is missing from the enumerated list. Present means the
        /// primary lookup already claimed it; absent with an ID in hand is
        /// precisely the case the fallbacks handle badly, because the
        /// channels they depend on — namespace, resolved sourcePID — fail in
        /// the same conditions that strand the window.
        ///
        /// Pure over its inputs.
        static nonisolated func shouldRecoverOwnControlItem(
            authoritativeWindowID: CGWindowID?,
            itemWindowIDs: Set<CGWindowID>
        ) -> Bool {
            guard let authoritativeWindowID else {
                return false
            }
            return !itemWindowIDs.contains(authoritativeWindowID)
        }

        /// Strategy 4: correlates Thaw's own AX element frames (from its own
        /// `extrasMenuBar`, via `NSRunningApplication.current`) against the
        /// candidate items' CG window bounds, using
        /// `AXIdentityCatalog.identity(for:in:)`'s pure correlation. Confident
        /// matches (>50% overlap of the smaller rect's area, no ties) select
        /// the hidden and always-hidden control items exactly as strategies
        /// 1–3 would.
        private static func matchViaAXFrame(
            items: inout [MenuBarItem]
        ) -> (hidden: MenuBarItem, alwaysHidden: MenuBarItem?)? {
            guard
                let app = AXHelpers.application(for: .current),
                let extrasMenuBar = AXHelpers.extrasMenuBar(for: app)
            else {
                MenuBarItemManager.diagLog.debug(
                    "ControlItemPair: strategy 4 (AX frame) unavailable — could not resolve Thaw's own extrasMenuBar"
                )
                return nil
            }
            try? app.setMessagingTimeout(0.25)
            try? extrasMenuBar.setMessagingTimeout(0.25)

            let children = AXHelpers.children(for: extrasMenuBar)
            let snapshot: [AXIdentityCatalog.AXItemIdentity] = children.compactMap { child in
                try? child.setMessagingTimeout(0.25)
                guard let frame = AXHelpers.frame(for: child) else { return nil }
                return AXIdentityCatalog.AXItemIdentity(
                    identifier: AXHelpers.identifier(for: child),
                    title: AXHelpers.title(for: child),
                    help: AXHelpers.help(for: child),
                    frame: frame
                )
            }

            guard !snapshot.isEmpty else {
                MenuBarItemManager.diagLog.debug(
                    "ControlItemPair: strategy 4 (AX frame) unavailable — Thaw's extrasMenuBar has no children with frames"
                )
                return nil
            }

            let ourPID = ProcessInfo.processInfo.processIdentifier
            let visibleTitle = ControlItem.Identifier.visible.rawValue
            let candidates = items.indexed().map { index, item in
                CandidateFrame(
                    index: index,
                    bounds: item.bounds,
                    isOwnProcess: item.sourcePID == ourPID,
                    // The visible control item is own-process, so it is an
                    // eligible candidate on frame alone. When the hidden
                    // divider is absent from `items` — parked far offscreen,
                    // or dropped by the active-space filter — it can be the
                    // only own-process candidate left, and the hidden AX
                    // frame correlates onto it. It is then returned AS the
                    // hidden divider, and every section boundary downstream
                    // is measured from the wrong window (#923, #924, #927).
                    //
                    // The filter on `axFrames` below excludes the visible
                    // item from the frames being matched *against*; this
                    // excludes it from the windows that can be *selected*.
                    // Matched by title rather than window ID because title
                    // survives the identity degradation that got us here:
                    // it comes off the CG window, not from sourcePID.
                    isVisibleControlItem: item.title == visibleTitle
                )
            }
            // Exclude the visible control item's AX child before correlation
            // so its frame can never confidently match a candidate and be
            // returned as the hidden or always-hidden control item.
            let axFrames = snapshot
                .filter { identity in
                    identity.identifier != ControlItem.Identifier.visible.rawValue
                        && identity.title != ControlItem.Identifier.visible.rawValue
                }
                .map(\.frame)

            guard let matchedIndices = Self.selectViaAXFrame(candidates: candidates, axFrames: axFrames),
                  let hiddenIdx = matchedIndices.first
            else {
                MenuBarItemManager.diagLog.debug(
                    "ControlItemPair: strategy 4 (AX frame) found no confident correlation among \(items.count) candidate item(s)"
                )
                return nil
            }

            // Remove higher index first so the lower index stays valid.
            let sortedIndices = matchedIndices.sorted(by: >)
            var removed = [Int: MenuBarItem]()
            for idx in sortedIndices {
                removed[idx] = items.remove(at: idx)
            }
            guard let hidden = removed[hiddenIdx] else {
                return nil
            }
            let alwaysHidden = matchedIndices.count > 1 ? removed[matchedIndices[1]] : nil

            MenuBarItemManager.diagLog.info(
                "ControlItemPair: strategy 4 (AX frame) matched hidden control item via AX-frame correlation (windowID=\(hidden.windowID))\(alwaysHidden.map { ", alwaysHidden windowID=\($0.windowID)" } ?? "")"
            )

            return (hidden, alwaysHidden)
        }

        /// A candidate item's bounds and own-process ownership, stripped
        /// down to what ``selectViaAXFrame(candidates:axFrames:)`` needs so
        /// it can be exercised with synthetic fixtures.
        struct CandidateFrame {
            let index: Int
            let bounds: CGRect
            let isOwnProcess: Bool
            /// Whether this candidate is Thaw's *visible* control item, which
            /// must never be selected as the hidden or always-hidden divider
            /// however well its frame correlates.
            var isVisibleControlItem = false
        }

        /// Pure selection helper: correlates each of our own control items
        /// (`candidates` where `isOwnProcess` is true) against `axFrames` in
        /// AX order (left-to-right in the extras menu bar, matching the
        /// order Thaw's own status items are enumerated in), so the first
        /// confidently-correlated own-item becomes the hidden control item
        /// and the second becomes the always-hidden one — the same relative
        /// ordering the tag/title strategies assume, but derived from AX
        /// position instead of a title that may no longer be trustworthy.
        ///
        /// Returns the matched candidate indices (1 or 2 of them, in
        /// hidden/always-hidden order), or `nil` when no own-process
        /// candidate correlates confidently with any AX frame.
        static nonisolated func selectViaAXFrame(
            candidates: [CandidateFrame],
            axFrames: [CGRect]
        ) -> [Int]? {
            var matchedIndices = [Int]()
            for frame in axFrames {
                let identity = [AXIdentityCatalog.AXItemIdentity(identifier: nil, title: nil, help: nil, frame: frame)]
                guard
                    let candidate = candidates.first(where: { candidate in
                        !matchedIndices.contains(candidate.index)
                            && candidate.isOwnProcess
                            && !candidate.isVisibleControlItem
                            && AXIdentityCatalog.identity(for: candidate.bounds, in: identity) != nil
                    })
                else { continue }
                matchedIndices.append(candidate.index)
                if matchedIndices.count == 2 {
                    break
                }
            }
            return matchedIndices.isEmpty ? nil : matchedIndices
        }
    }

    /// Returns duplicate windows that claim this instance's control-item
    /// title while its authoritative window is present in the same list.
    /// Requiring the authoritative window makes the filter self-validating:
    /// if a window number is stale or absent, nothing is discarded.
    static nonisolated func ghostControlItemWindowIDs(
        in items: [MenuBarItem],
        ownWindowIDsByTitle: [String: CGWindowID]
    ) -> Set<CGWindowID> {
        var ghostIDs = Set<CGWindowID>()
        for (title, ownWindowID) in ownWindowIDsByTitle {
            guard items.contains(where: { $0.windowID == ownWindowID }) else { continue }
            for item in items where item.title == title && item.windowID != ownWindowID {
                ghostIDs.insert(item.windowID)
            }
        }
        return ghostIDs
    }

    private func ownControlItemWindowIDsByTitle() -> [String: CGWindowID] {
        guard let menuBarManager = appState?.menuBarManager else { return [:] }
        return MenuBarSection.Name.allCases.reduce(into: [:]) { result, name in
            guard let controlItem = menuBarManager.controlItem(withName: name),
                  let window = controlItem.window,
                  window.windowNumber > 0,
                  let windowID = CGWindowID(exactly: window.windowNumber)
            else { return }
            result[controlItem.identifier.rawValue] = windowID
        }
    }

    @discardableResult
    private func dropGhostControlItemWindows(from items: inout [MenuBarItem]) -> Set<CGWindowID> {
        let ghostIDs = Self.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: ownControlItemWindowIDsByTitle()
        )
        guard !ghostIDs.isEmpty else { return [] }
        MenuBarItemManager.diagLog.warning(
            "cacheItemsRegardless: dropping \(ghostIDs.count) duplicate control item window(s)"
        )
        items.removeAll { ghostIDs.contains($0.windowID) }
        return ghostIDs
    }

    /// Context maintained during a menu bar item cache operation.
    private struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
        var relocatedItems = [MenuBarItem]()
        let hiddenControlItemBounds: CGRect
        let alwaysHiddenControlItemBounds: [CGRect]

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
            self.hiddenControlItemBounds = Self.bestBounds(for: controlItems.hidden)
            self.alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map { [Self.bestBounds(for: $0)] } ?? []
        }

        private static func bestBounds(for item: MenuBarItem) -> CGRect {
            Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if item.tag == .visibleControlItem {
                return true
            }
            if !item.canBeHidden {
                return false
            }
            if item.isSystemClone {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }

        mutating func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            let itemBounds = Self.bestBounds(for: item)

            // Strict-inequality fast path for items that lie entirely on
            // one side of every boundary. Identical to the original
            // semantics so well-behaved items keep their existing
            // classification.
            if itemBounds.minX >= hiddenControlItemBounds.maxX {
                return .visible
            }
            if itemBounds.maxX <= hiddenControlItemBounds.minX {
                if let alwaysHiddenBounds = alwaysHiddenControlItemBounds.first {
                    if itemBounds.minX >= alwaysHiddenBounds.maxX {
                        return .hidden
                    }
                    if itemBounds.maxX <= alwaysHiddenBounds.minX {
                        return .alwaysHidden
                    }
                } else {
                    return .hidden
                }
            }

            // Fall-through: the item straddles at least one boundary.
            // Control items are zero-width markers; any item whose
            // physical bounds cross the marker's single X coordinate
            // fails the strict inequalities above. This happens when a
            // profile collapses a section by moving its control item
            // into the items' physical range, or transiently while
            // sections expand/collapse during section.show()/hide().
            // Returning nil drops the item from the cache and from
            // Phase 1's section sets, which causes the layout to skip
            // the divider move it would otherwise prefer. Resolve every
            // straddle case via midpoint: assign the item to whichever
            // section its physical centre predominantly occupies.
            let itemMid = (itemBounds.minX + itemBounds.maxX) / 2
            let hiddenMid = (hiddenControlItemBounds.minX + hiddenControlItemBounds.maxX) / 2
            if itemMid >= hiddenMid {
                return .visible
            }
            if let alwaysHiddenBounds = alwaysHiddenControlItemBounds.first {
                let ahMid = (alwaysHiddenBounds.minX + alwaysHiddenBounds.maxX) / 2
                return itemMid >= ahMid ? .hidden : .alwaysHidden
            }
            return .hidden
        }
    }

    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?
    ) async {
        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: processing \(items.count) items for caching")
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        var validCount = 0
        var invalidCount = 0
        var noSectionCount = 0

        // Track which tags have already been cached to avoid duplicates.
        // macOS can briefly report two windows for the same item during
        // or shortly after a move operation (e.g. layout reset). We keep
        // the first occurrence, which is the rightmost (items are reversed
        // from the Window Server order).
        var seenTags = Set<MenuBarItemTag>()

        for item in items where context.isValidForCaching(item) {
            guard seenTags.insert(item.tag).inserted else {
                MenuBarItemManager.diagLog.debug("uncheckedCacheItems: skipping duplicate tag \(item.logString)")
                continue
            }

            validCount += 1
            if item.sourcePID == nil {
                // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
                // Changing this string breaks log-replay regression tests.
                MenuBarItemManager.diagLog.warning("Missing sourcePID for \(item.logString)")
            }

            let matchingContext: TemporarilyShownItemContext? = {
                // 1. Try exact tag match (includes windowID for non-system items).
                if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                    return temp
                }
                // 2. Fallback: tag and PID match, but ONLY if the item is physically in the visible section
                //    (identifying it as the 'shown' instance) and it originally belonged elsewhere.
                if let temp = temporarilyShownItemContexts.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        $0.sourcePID == (item.sourcePID ?? item.ownerPID)
                }),
                    context.findSection(for: item) == .visible,
                    temp.originalSection != .visible
                {
                    return temp
                }
                return nil
            }()

            if let matchingContext {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.temporarilyShownItems.append((item, matchingContext.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            noSectionCount += 1
            let currentBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
            if currentBounds.origin.x == -1 {
                MenuBarItemManager.diagLog.warning(
                    "Skipping \(item.logString); blocked (x=-1), will retry on next cache tick"
                )
            } else {
                MenuBarItemManager.diagLog.warning(
                    "Couldn't find section for caching \(item.logString) bounds=\(NSStringFromRect(item.bounds)), assigning to hidden"
                )
                context.cache[.hidden].append(item)
            }
        }

        // Count invalid items
        for item in items where !context.isValidForCaching(item) {
            invalidCount += 1
        }

        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: \(validCount) valid, \(invalidCount) invalid (filtered), \(noSectionCount) couldn't find section, \(context.temporarilyShownItems.count) temporarily shown")

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        let cacheChanged = itemCache != context.cache

        // Discard a pass whose divider geometry disagrees with the section's
        // logical state. Keeping the previous cache costs one cycle; accepting
        // the mixture reclassifies a whole section (#851).
        if cacheChanged,
           !itemCache.managedItems.isEmpty,
           let section = await midTransitionSection(in: context)
        {
            MenuBarItemManager.diagLog.debug(
                "Not updating menu bar item cache: \(section.logString) is mid expand/collapse, keeping last-known-good cache"
            )
            return
        }

        // The always-hidden divider is what tells always-hidden items apart
        // from hidden ones. If this cycle resolved the hidden divider but
        // not the always-hidden one, findSection has already collapsed the
        // always-hidden section into hidden; persisting that reading is what
        // made #849 permanent.
        let alwaysHiddenSectionResolved = LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: context.controlItems.alwaysHidden != nil,
            isAlwaysHiddenSectionEnabled: appState?.menuBarManager
                .section(withName: .alwaysHidden)?.isEnabled ?? false
        )

        // Item bounds come from the window server in CoreGraphics space, so
        // the frames they are tested against have to be CGDisplayBounds and
        // not NSScreen.frame — the two disagree by a vertical flip.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }

        // The hidden section is the span between the two dividers. When it
        // closes to zero, findSection can no longer classify anything as
        // .hidden by the strict test and the midpoint tie-break resolves
        // on-screen items as .visible instead (#795, docked topology).
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
            alwaysHiddenControlItemMaxX: context.alwaysHiddenControlItemBounds.first?.maxX,
            savedHiddenItemCount: savedSectionOrder[sectionKey(for: .hidden)]?.count ?? 0,
            // The cache's own reading, because the cache's own reading is what
            // this path is deciding whether to persist.
            liveHiddenItemCount: context.cache[.hidden].count,
            hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                itemBounds: MenuBarSection.Name.allCases.flatMap { section in
                    context.cache[section].map(\.bounds)
                },
                hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
                screenFrames: screenFrames
            )
        )

        if recoverCollapsedHiddenSectionIfNeeded(
            hiddenSectionHasRoom: hiddenSectionHasRoom,
            controlItems: context.controlItems
        ) {
            return
        }

        guard cacheChanged else {
            MenuBarItemManager.diagLog.debug("Not updating menu bar item cache, as items haven't changed")
            return
        }

        itemCache = context.cache

        // Reset isRestoringItemOrder if it's been stuck for too long (10 seconds).
        // This prevents stale flags from blocking saves after user manual moves.
        if isRestoringItemOrder, let timestamp = isRestoringItemOrderTimestamp, Date().timeIntervalSince(timestamp) > 10 {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        let hasPendingDivergence = pendingDivergenceObservedAt != nil

        // The bar after a batch that gave up partway is the batch's own
        // wreckage, not a layout anyone chose. Recording it hands the next
        // pass a target it just moved, which is how a failed apply turns
        // into a bar that drifts a little further on every retry (#900).
        if context.controlItems.canRepositionControlItems,
           LayoutSolver.shouldPersistSavedOrder(
               LayoutSolver.SavedOrderGate(
                   isRestoringItemOrder: isRestoringItemOrder,
                   isResettingLayout: isResettingLayout,
                   isInStartupSettling: isInStartupSettling,
                   isApplyingProfileLayout: isApplyingProfileLayout,
                   temporarilyShownItemContextsIsEmpty: temporarilyShownItemContexts.isEmpty,
                   alwaysHiddenSectionResolved: alwaysHiddenSectionResolved,
                   hiddenSectionHasRoom: hiddenSectionHasRoom,
                   hasPendingDivergence: hasPendingDivergence,
                   hasUnfinishedMoveBatch: hasUnfinishedMoveBatch
               )
           )
        {
            // Don't persist if any items are in a transient blocked state (x=-1).
            // Wait for the next cache cycle when bounds are reliable.
            let hasBlockedItems = MenuBarSection.Name.allCases.contains { section in
                context.cache[section].contains { item in
                    let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                    return bounds.origin.x == -1
                }
            }
            // Don't persist while the items straddle two displays. A cross-display
            // cache is a menu bar relocation caught mid-flight, not a settled
            // layout: macOS un-hides items as it moves them to the new screen, so
            // capturing the section order now would bake those un-hidden items
            // into the saved layout as if the user wanted them visible. Wait for
            // the items to collapse back onto a single display.
            //
            // Only the visible section feeds the gate. Hidden and always-hidden
            // items are parked left of the menu bar at arbitrary negative x, and
            // a display positioned to the left of the main one owns that
            // coordinate range, so parked items read as a second screen on a
            // settled layout and this branch never stops firing. The visible
            // section is never parked, and a genuine relocation splits it across
            // screens just the same, so narrowing the input keeps the protection.
            let itemCenters = context.cache[.visible].map {
                CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)
            }
            let spansDisplays = LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: itemCenters,
                screenFrames: screenFrames
            )
            if hasBlockedItems {
                MenuBarItemManager.diagLog.warning(
                    "Skipping saveSectionOrder; blocked items detected (x=-1), will retry on next cache tick"
                )
            } else if spansDisplays {
                MenuBarItemManager.diagLog.warning(
                    "Skipping saveSectionOrder; menu bar items span multiple displays (relocation in progress)"
                )
            } else {
                saveSectionOrder(from: context.cache)
            }
        } else if !context.controlItems.canRepositionControlItems {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; control items resolved only by provisional AX-frame correlation"
            )
        } else if !alwaysHiddenSectionResolved {
            // Logged at warning level, and separately from the gate's other
            // inputs, because this is the one that silently rewrites the
            // user's layout when it goes wrong (#849). A run of these means
            // the always-hidden divider keeps failing to resolve.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; always-hidden divider unresolved while its section is enabled"
            )
        } else if !hiddenSectionHasRoom {
            // Same reasoning as above: this one is a geometry fault rather
            // than a resolution fault, and it is worth being able to grep
            // the two apart. A run of these means the dividers have
            // collapsed and the menu bar is visibly wrong to the user, not
            // merely at risk of a bad save.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; hidden section has zero width between the dividers (hidden.minX=\(context.hiddenControlItemBounds.minX) windowID=\(context.controlItems.hidden.windowID), alwaysHidden.maxX=\(context.alwaysHiddenControlItemBounds.first?.maxX.description ?? "nil") windowID=\(context.controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
        } else if hasPendingDivergence {
            // applySavedLayout observed a layout divergence on this cycle
            // but is waiting for a second consecutive observation before
            // correcting it. The current cache reflects a transient state
            // (e.g. macOS rebuilding the bar after a space switch and
            // re-exposing hidden items as visible); persisting it now
            // would bake that transient state into the saved layout (#736).
            // The arm clears once applySavedLayout confirms and runs its
            // correction, after which the next cycle sees a settled layout.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; layout divergence pending confirmation (applySavedLayout has not yet restored the cached layout)"
            )
        } else if hasUnfinishedMoveBatch {
            // Warning level, like the two above, because a run of these is
            // the signature of a bar that cannot be restored at all: the
            // apply keeps failing, so the saved order keeps being withheld,
            // and the user sees their layout never take (#900).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; the last bulk apply left planned moves unenacted, so the current arrangement is partial"
            )
        }
        MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")
    }

    /// Recreates the hidden divider at its seeded position after repeated,
    /// authoritative evidence that stale geometry closed the hidden span.
    /// The saved order remains untouched, so the next cache pass can restore
    /// section membership through the normal saved-layout apply.
    private func recoverCollapsedHiddenSectionIfNeeded(
        hiddenSectionHasRoom: Bool,
        controlItems: ControlItemPair
    ) -> Bool {
        // A provisional reading must not advance, reset, or re-arm the
        // recovery episode. Only authoritative observations may mutate it.
        guard controlItems.canRepositionControlItems else {
            return false
        }

        guard !hiddenSectionHasRoom else {
            hiddenSectionCollapseStreak = 0
            didRecoverHiddenSectionForCurrentCollapse = false
            return false
        }

        hiddenSectionCollapseStreak += 1
        guard Self.shouldRecoverCollapsedHiddenSection(
            consecutiveCollapsedReadings: hiddenSectionCollapseStreak,
            alreadyRecovered: didRecoverHiddenSectionForCurrentCollapse
        ),
            let hiddenControlItem = appState?.menuBarManager.controlItem(withName: .hidden)
        else {
            return false
        }

        didRecoverHiddenSectionForCurrentCollapse = true
        MenuBarItemManager.diagLog.warning(
            "Hidden section remained collapsed for \(hiddenSectionCollapseStreak) authoritative cache passes; recreating H_ctrl at its seeded position"
        )
        hiddenControlItem.recreateStatusItem(preferredPosition: 1)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
        return true
    }

    /// Recreates an authoritatively identified hidden divider after it remains
    /// parked through repeated layout applies that need it on the bar.
    private func recoverParkedHiddenDividerIfNeeded(
        hiddenBoundaryMismatch: Int,
        hiddenControlItem: MenuBarItem,
        screenFrames: [CGRect]
    ) -> Bool {
        guard hiddenBoundaryMismatch > 0,
              !LayoutSolver.isOnScreen(bounds: hiddenControlItem.bounds, screenFrames: screenFrames)
        else {
            parkedHiddenDividerMismatchStreak = 0
            didRecoverParkedHiddenDividerForCurrentMismatch = false
            return false
        }

        parkedHiddenDividerMismatchStreak += 1
        guard Self.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: parkedHiddenDividerMismatchStreak,
            alreadyRecovered: didRecoverParkedHiddenDividerForCurrentMismatch
        ),
            let hiddenControl = appState?.menuBarManager.controlItem(withName: .hidden)
        else {
            return false
        }

        didRecoverParkedHiddenDividerForCurrentMismatch = true
        MenuBarItemManager.diagLog.warning(
            "H_ctrl remained parked through \(parkedHiddenDividerMismatchStreak) authoritative mismatch applies; recreating it at its seeded position"
        )
        hiddenControl.recreateStatusItem(preferredPosition: 1)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            // The unfinished batch that exposed the parked divider may have
            // stamped the move cooldown. This recovery owns its retry, so let
            // the fresh divider reach applySavedLayout instead of committing
            // its new window ID without verifying the saved boundary.
            await self?.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                bypassSavedLayoutCooldown: true
            )
        }
        return true
    }

    /// Whether bundleID owns a menu bar item Thaw already tracks: an entry
    /// in identifiers (each formatted "namespace:title") whose namespace is
    /// exactly bundleID. The trailing ":" anchors the match so one bundle ID
    /// can't be a loose prefix of another (org.x.fdm6 must not match
    /// org.x.fdm6x:Item-0). Used to arm relaunch settling only for apps whose
    /// status item actually churns the bar when they relaunch.
    static nonisolated func tracksMenuBarItem(bundleID: String, in identifiers: Set<String>) -> Bool {
        identifiers.contains { $0.hasPrefix(bundleID + ":") }
    }

    /// A Boolean value indicating whether `item`'s CG-side identity is
    /// degraded: either a Control-Center generic `Item-N` placeholder title,
    /// or a bundle-id-shaped title (reverse-DNS, three-plus dot-separated
    /// components — the same shape `86f2514e`'s title-identity fallback
    /// matches on the service side).
    private static func isDegradedIdentity(_ item: MenuBarItem) -> Bool {
        if item.tag.isControlCenterGenericItem {
            return true
        }
        guard let title = item.title else { return false }
        return title.split(separator: ".").count >= 3
    }

    /// Populates `degradedItemAXIdentities` for `items` whose CG-side
    /// identity is degraded, at most once per `cacheItemsRegardless` pass
    /// and only when at least one degraded item is present. Takes an
    /// on-demand AX snapshot of Control Center and SystemUIServer (the hosts
    /// responsible for the degraded cases this targets) and records the
    /// confident correlation for each degraded item's window bounds.
    ///
    /// This map is additive and display-only — see its declaration.
    private func enrichDegradedItemIdentities(in items: [MenuBarItem]) {
        let degradedItems = items.filter(Self.isDegradedIdentity)
        guard !degradedItems.isEmpty else {
            degradedItemAXIdentities = [:]
            return
        }

        let hostBundleIDs = ["com.apple.controlcenter", "com.apple.systemuiserver"]
        let hosts = hostBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard !hosts.isEmpty else {
            MenuBarItemManager.diagLog.debug(
                "enrichDegradedItemIdentities: \(degradedItems.count) degraded item(s) present but no Control Center/SystemUIServer host is running"
            )
            degradedItemAXIdentities = [:]
            return
        }

        let snapshot = AXIdentityCatalog.snapshot(hosts: hosts)
        var enrichment = [CGWindowID: AXIdentityCatalog.AXItemIdentity]()
        for item in degradedItems {
            let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
            guard let identity = AXIdentityCatalog.identity(for: bounds, in: snapshot) else { continue }
            enrichment[item.windowID] = identity
        }

        MenuBarItemManager.diagLog.debug(
            "enrichDegradedItemIdentities: \(degradedItems.count) degraded item(s), \(enrichment.count) resolved via AX-frame correlation"
        )
        degradedItemAXIdentities = enrichment
    }

    /// Returns the hideable section whose divider geometry contradicts its
    /// logical state, or `nil` when both sections agree.
    ///
    /// See ``isMidSectionTransition(dividerWidth:isSectionCollapsed:)`` for why
    /// the two can disagree.
    private func midTransitionSection(in context: CacheContext) async -> MenuBarSection.Name? {
        var widths: [(MenuBarSection.Name, CGFloat)] = [
            (.hidden, context.hiddenControlItemBounds.width),
        ]
        if let alwaysHiddenBounds = context.alwaysHiddenControlItemBounds.first {
            widths.append((.alwaysHidden, alwaysHiddenBounds.width))
        }

        let mismatch = await MainActor.run { [weak self] () -> MenuBarSection.Name? in
            guard let menuBarManager = self?.appState?.menuBarManager else {
                return nil
            }
            return widths.first { name, width in
                guard
                    let section = menuBarManager.section(withName: name),
                    section.isEnabled
                else {
                    return false
                }
                return MenuBarItemManager.isMidSectionTransition(
                    dividerWidth: width,
                    isSectionCollapsed: section.isHidden
                )
            }?.0
        }

        guard let mismatch else {
            midTransitionSkipStreak = 0
            return nil
        }

        midTransitionSkipStreak += 1
        guard midTransitionSkipStreak <= MenuBarItemManager.maxMidTransitionSkips else {
            MenuBarItemManager.diagLog.warning(
                "midTransitionSection: \(mismatch.logString) still mid expand/collapse after \(midTransitionSkipStreak) passes, accepting this one"
            )
            midTransitionSkipStreak = 0
            return nil
        }

        return mismatch
    }

    /// Records this enumeration's windowIDs and returns the set that counts as
    /// recently seen.
    ///
    /// See ``recentItemWindowIDCycles`` for why continuity is judged over
    /// several cycles rather than only the preceding one.
    ///
    /// - Parameter items: The items enumerated this cycle, after clones and
    ///   ghost control windows have been dropped.
    ///
    /// - Returns: Every windowID enumerated within the last
    ///   ``recentWindowIDCycleWindow`` cycles, including this one.
    private func recordRecentItemWindowIDs(_ items: [MenuBarItem]) -> Set<CGWindowID> {
        recentItemWindowIDCycles.append(Set(items.lazy.map(\.windowID)))
        while recentItemWindowIDCycles.count > MenuBarItemManager.recentWindowIDCycleWindow {
            recentItemWindowIDCycles.removeFirst()
        }
        return recentItemWindowIDCycles.reduce(into: Set()) { $0.formUnion($1) }
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        skipRecentMoveCheck: Bool = false,
        resolveSourcePID: Bool = true,
        skipSavedLayoutApply: Bool = false,
        bypassSavedLayoutCooldown: Bool = false,
        waiterToken: Int? = nil
    ) async {
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil), resolveSourcePID=\(resolveSourcePID), skipSavedLayoutApply=\(skipSavedLayoutApply), bypassSavedLayoutCooldown=\(bypassSavedLayoutCooldown))"
        )

        guard skipRecentMoveCheck || !lastMoveOperationOccurred(within: .seconds(1)) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache due to recent item movement")
            return
        }

        guard !(appState?.isDraggingMenuBarItem ?? false) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: user is cmd-dragging")
            return
        }

        // Serialization gate: drop concurrent calls while a previous cache
        // cycle is in flight. Without this, a call that starts during a
        // relocation move by another call may snapshot pre-move positions.
        guard await cacheGate.begin() else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, skipping")
            return
        }
        defer { Task { await cacheGate.end() } }

        // Ownership of the waiter (if any) defaults to this call. Some
        // paths below (relocation hand-offs) hand ownership to a nested
        // recache below. Resuming from `defer` means every exit path from
        // here on — including early returns that cached nothing — releases
        // the waiter rather than stranding it. A caller that bailed before
        // the gate above never took ownership, so it cannot resume a waiter
        // that isn't its to resume.
        var ownsWaiter = true
        defer {
            if ownsWaiter, let waiterToken {
                resumeBackgroundCacheWaiter(waiterToken)
            }
        }

        let previousWindowIDs = cacheActor.cachedItemWindowIDs
        let previousCCGenericWindowIDs = cacheActor.cachedControlCenterGenericWindowIDs
        let displayID = Bridging.getActiveMenuBarDisplayID()
        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: displayID=\(displayID.map { "\($0)" } ?? "nil"), previousWindowIDs count=\(previousWindowIDs.count)")

        var items = await MenuBarItem.getMenuBarItems(
            option: .activeSpace,
            resolveSourcePID: resolveSourcePID
        )

        if items.isEmpty {
            // Retry once after a small delay if we got zero items. This can happen
            // due to transient WindowServer glitches or during display reconfigurations.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
            try? await Task.sleep(for: .milliseconds(250))
            items = await MenuBarItem.getMenuBarItems(
                option: .activeSpace,
                resolveSourcePID: resolveSourcePID
            )

            // Still nothing, but the cache holds items. The menu bar does not
            // empty itself, so this is the `.activeSpace` filter resolving a
            // space ID that no longer matches the windows (a Space switch, a
            // display reconfiguration). Replacing a populated cache with the
            // empty reading is what blanks the layout editor mid-session
            // (#851); hold the last known good cache and let the next cycle
            // read the menu bar again.
            if items.isEmpty, !itemCache.managedItems.isEmpty {
                MenuBarItemManager.diagLog.warning(
                    "cacheItemsRegardless: getMenuBarItems returned ZERO items twice, keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
                )
                return
            }
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: getMenuBarItems returned \(items.count) items")

        // Drop System Status Item Clone windows before any downstream
        // processing. These are transient duplicates the WindowServer
        // spawns during screen capture and menu bar animations. Each one
        // carries a fresh windowID and a nil source PID, and resolves to
        // an unstable namespace, so they must never be cached, assigned to
        // a section, placed via planUnmanagedPlacement, or moved. Removing
        // them here also keeps their windowIDs out of the stored set
        // below, so a clone appearing or vanishing can't trip the
        // windowID-change trigger that dispatches a bulk re-layout.
        let cloneWindowIDs = Set(items.filter(\.isSystemClone).map(\.windowID))
        if !cloneWindowIDs.isEmpty {
            let cloneDescriptions = items.filter(\.isSystemClone).map(\.tag.description)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: dropping \(cloneWindowIDs.count) system clone window(s): \(cloneDescriptions)")
            items.removeAll(where: \.isSystemClone)
        }

        // A duplicate Thaw process (or windows left by one that crashed) can
        // expose control-item titles under foreign window IDs. Exclude those
        // windows from every cache decision so they cannot be treated as new
        // unmanaged items or make the normal window-ID comparison churn.
        let ghostControlWindowIDs = dropGhostControlItemWindows(from: &items)

        // A reading whose items are titled after their own owners identifies
        // nothing, and caching it rewrites the whole bar under a second set of
        // identifiers that no later reading will match (#881, #927). Same
        // treatment as the empty reading above: this is a failed observation,
        // not the bar changing, so hold the last known good cache and read
        // again next cycle. Only once there is a cache to hold — on a first
        // launch there is nothing better to fall back to.
        if !itemCache.managedItems.isEmpty,
           LayoutSolver.liveIdentitiesAreDegraded(items.map { ($0.tag.namespace.description, $0.tag.title) })
        {
            MenuBarItemManager.diagLog.warning(
                "cacheItemsRegardless: reading titles items after their own owners (\(items.count) item(s)); keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
            )
            return
        }

        // Recorded only after clones and ghost windows are dropped, so their
        // throwaway windowIDs never enter the continuity history.
        let recentWindowIDs = recordRecentItemWindowIDs(items)

        // Reconcile resolved sourcePIDs against previously known values to
        // prevent transient resolution errors (e.g. stale AX data after item
        // moves) from corrupting item identities. SourcePIDCache does spatial
        // matching between CG windows and AX extras menu bar children, which
        // can produce wrong matches when AX positions lag behind CG updates.
        // A cached PID from a previous stable cycle is more trustworthy.
        if resolveSourcePID {
            let previousPIDs = cacheActor.cachedItemPIDs
            for i in items.indices {
                let item = items[i]
                guard !item.isControlItem else { continue }
                if let prevPID = previousPIDs[item.windowID],
                   let currentPID = item.sourcePID,
                   currentPID != prevPID
                {
                    // Only a live previous PID is more trustworthy than a
                    // fresh resolution. When the app behind it has exited —
                    // an item's owner relaunching, or Control Center itself
                    // respawning and recreating every status item, both seen
                    // in the #854 logs — reverting pins the item to a dead
                    // process, and every event addressed to it goes nowhere.
                    // Take the new PID in that case; there is nothing left to
                    // protect.
                    guard Self.previousPIDIsLive(prevPID) else {
                        MenuBarItemManager.diagLog.info(
                            "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID); previous PID is dead, accepting the new one"
                        )
                        continue
                    }
                    MenuBarItemManager.diagLog.warning(
                        "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID), reverting to previous PID"
                    )
                    // Rebuild the namespace from the previous PID. If the bundle
                    // ID is not available (app no longer running), keep the
                    // original tag namespace as a safe fallback.
                    let prevBundleID = NSRunningApplication(processIdentifier: prevPID)?.bundleIdentifier
                    let correctedNamespace: MenuBarItemTag.Namespace = if let prevBundleID {
                        .string(prevBundleID)
                    } else {
                        item.tag.namespace
                    }
                    let correctedTag = MenuBarItemTag(
                        namespace: correctedNamespace,
                        title: item.tag.title,
                        windowID: item.windowID,
                        instanceIndex: item.tag.instanceIndex
                    )
                    items[i] = MenuBarItem(
                        tag: correctedTag,
                        windowID: item.windowID,
                        ownerPID: item.ownerPID,
                        sourcePID: prevPID,
                        bounds: item.bounds,
                        title: item.title,
                        isOnScreen: item.isOnScreen
                    )
                }
            }
        }

        // When sourcePID resolution changes an item's identifier (e.g. from
        // com.apple.controlcenter:Item-0:4 to pl.maketheweb.cleanshotx:Item-0),
        // the new identifier won't be in knownItemIdentifiers. Seed it now so
        // the item isn't treated as a "new" item by relocateNewLeftmostItems.
        // Skip items with unresolved sourcePID so the placeholder
        // "com.apple.controlcenter" namespace never enters the persisted set.
        if !previousWindowIDs.isEmpty {
            for item in items where previousWindowIDs.contains(item.windowID) && item.sourcePID != nil {
                let identifier = "\(item.tag.namespace):\(item.tag.title)"
                if !knownItemIdentifiers.contains(identifier) {
                    knownItemIdentifiers.insert(identifier)
                }
            }
            persistKnownItemIdentifiers()
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after getMenuBarItems")
            return
        }

        if items.isEmpty {
            MenuBarItemManager.diagLog.error("cacheItemsRegardless: getMenuBarItems returned ZERO items even after retry; this is the root cause of 'Loading menu bar items' being stuck")
        }

        // currentItemWindowIDs comes straight from the bridging window list
        // and may still contain clone or ghost IDs. Keep the stored set in
        // sync with the managed item set and ignore those transient IDs in
        // the next raw-list comparison.
        let itemWindowIDs = (currentItemWindowIDs ?? items.reversed().map(\.windowID))
            .filter { !cloneWindowIDs.contains($0) && !ghostControlWindowIDs.contains($0) }
        // NOTE: cacheActor.updateCachedItemWindowIDs/updateCachedCloneWindowIDs
        // are deliberately NOT called here. Committing them this early, before
        // the ControlItemPair guard below is known to succeed, would make
        // cacheItemsIfNeeded's change detector see cachedIDs == itemWindowIDs
        // on the very next poll even though this cycle failed to find the
        // control items. That desensitizes the detector right when recovery
        // depends on it, since a failed cacheItemsRegardless call otherwise
        // looks identical to a successful one from the detector's point of
        // view. The commit happens only after the guard succeeds, below.

        await MainActor.run {
            MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
            self.pruneMoveOperationTimeouts(keeping: Set(items.map(\.tag)))
            self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
        }

        // Obtain window IDs from the actual ControlItem objects so the
        // fallback lookup in ControlItemPair can match by window ID when
        // the tag-based and title-based lookups fail (macOS 26+).
        let hiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .hidden)?.window?.windowNumber
        let alwaysHiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window?.windowNumber
        let hiddenControlItemWID = hiddenControlItemWindowNumber.flatMap { CGWindowID(exactly: $0) }
        let alwaysHiddenControlItemWID = alwaysHiddenControlItemWindowNumber.flatMap { CGWindowID(exactly: $0) }

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
        ) else {
            // Recovery path (#754): a failed lookup here used to wipe
            // itemCache and commit the just-fetched window-ID snapshot to
            // the change detector, which together made the failure
            // permanent — the cache stayed empty, and cacheItemsIfNeeded
            // saw no further change to re-drive a recache. Instead: keep
            // the last-known-good itemCache (consumers key visible UI off
            // areControlItemsMissing, not off an empty cache; see
            // MenuBarLayoutSettingsPane), leave the window-ID snapshot
            // uncommitted so the detector re-fires on the next poll, and
            // count consecutive failures. After controlItemRebuildThreshold
            // in a row, the backing NSStatusItems are rebuilt outright,
            // since a lookup that keeps failing across independently
            // triggered cache cycles means the status items themselves are
            // gone (e.g. their windowNumber no longer matches any
            // enumerated CG window ID), not that this one cycle raced a
            // transient WindowServer update.
            controlItemLookupFailureStreak += 1
            lastControlItemLookupFailureAt = .now
            let failureStreak = controlItemLookupFailureStreak
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: Missing control item for hidden section (expected tag: \(MenuBarItemTag.hiddenControlItem)), keeping last-known-good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count). hiddenWindowNumber=\(hiddenControlItemWindowNumber.map(String.init) ?? "nil"), hiddenControlItemWID=\(hiddenControlItemWID.map(String.init) ?? "nil"), alwaysHiddenWindowNumber=\(alwaysHiddenControlItemWindowNumber.map(String.init) ?? "nil"), alwaysHiddenControlItemWID=\(alwaysHiddenControlItemWID.map(String.init) ?? "nil"). consecutiveFailures=\(failureStreak)")
            await MainActor.run {
                self.areControlItemsMissing = true
            }

            if MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: failureStreak,
                alreadyRebuilt: didRebuildControlItemsForCurrentFailureEpisode
            ) {
                MenuBarItemManager.diagLog.warning("cacheItemsRegardless: \(failureStreak) consecutive control item lookup failures, rebuilding hidden/always-hidden status items")
                await MainActor.run {
                    appState?.menuBarManager.controlItem(withName: .hidden)?.recreateStatusItem()
                    appState?.menuBarManager.controlItem(withName: .alwaysHidden)?.recreateStatusItem()
                }
                didRebuildControlItemsForCurrentFailureEpisode = true
                // Schedule one immediate recache so the freshly rebuilt
                // status items are picked up right away rather than waiting
                // for the next externally triggered cache cycle. Briefly wait
                // first so the deferred cacheGate.end() from this cycle can
                // complete (otherwise the recache is dropped at the gate) and
                // the newly created NSStatusItems can register their windows.
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    await self?.cacheItemsRegardless()
                }
            }
            return
        }

        if controlItems.canRepositionControlItems {
            controlItemLookupFailureStreak = 0
            didRebuildControlItemsForCurrentFailureEpisode = false
            lastControlItemLookupFailureAt = nil
            cacheActor.updateCachedItemWindowIDs(itemWindowIDs)
            cacheActor.updateCachedCloneWindowIDs(cloneWindowIDs.union(ghostControlWindowIDs))
            cacheActor.updateCachedControlCenterGenericWindowIDs(
                Set(items.filter(\.tag.isControlCenterGenericItem).map(\.windowID))
            )
        }

        await MainActor.run {
            self.areControlItemsMissing = false
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

        if Self.isDegradedIdentityEnrichmentEnabled {
            enrichDegradedItemIdentities(in: items)
        } else if !degradedItemAXIdentities.isEmpty {
            degradedItemAXIdentities = [:]
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after control item discovery")
            return
        }

        await enforceControlItemOrder(controlItems: controlItems)

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled before relocateNewLeftmostItems")
            return
        }

        // App-relaunch detection: uniqueIdentifier is namespace:title
        // (windowID-independent and stable across restarts), so a
        // relaunched app keeps the same identifier and would be filtered
        // out of newProfileItems by profileSortedItemIdentifiers in the
        // late-arrival check below. A windowID not in previousWindowIDs
        // for a profile-tracked item means the app re-registered its
        // NSStatusItem at whatever position macOS chose, which is
        // usually not the saved profile position. Drop such identifiers
        // from the sorted snapshot so the late-arrival path picks them
        // up. Run this BEFORE the relocate/restore early returns: those
        // paths schedule a recache after which previousWindowIDs already
        // contains the freshly registered windowID, and the signal would
        // be lost.
        //
        // Position-check refinement: a fresh windowID does not always
        // mean the item is at the wrong position. Idle wake, AX
        // rebinding, and some app lifecycle events recreate the
        // underlying NSStatusItem while macOS retains the original
        // visual position. The earlier unconditional drop fired a
        // full re-sort (which can replan many moves across the bar)
        // on every such event, even when the item was already at its
        // profile-expected section. Gate the drop on a section
        // mismatch: keep items whose current section matches the
        // profile spec, drop only items that genuinely landed in the
        // wrong section. Items whose current section can't be
        // determined (transient bounds during in-flight moves) fall
        // through to the drop path, preserving the original
        // conservative behaviour for ambiguous cases.
        if let activeLayout = activeProfileLayout,
           !activeProfileItemIdentifiers.isEmpty,
           !previousWindowIDs.isEmpty
        {
            let previousWindowIDSet = Set(previousWindowIDs)
            let hiddenMinX = controlItems.hidden.bounds.minX
            let hiddenMaxX = controlItems.hidden.bounds.maxX
            let ahBounds = controlItems.alwaysHidden?.bounds

            // Build per-identifier expected-section lookup from the
            // active profile spec. itemOrder is keyed by section
            // string ("visible" / "hidden" / "alwaysHidden") with
            // identifier arrays for each section.
            var expectedSectionByID = [String: String]()
            for (sectionKey, ids) in activeLayout.itemOrder {
                for id in ids {
                    expectedSectionByID[id] = sectionKey
                }
            }

            /// Spatial classification mirrors currentLayoutDivergesFromSaved:
            /// visible is right of hiddenCtrl; alwaysHidden is left of
            /// ahCtrl when present; hidden is between the two control
            /// items (or anything left of hiddenCtrl when ahCtrl is
            /// disabled). Items straddling a divider return nil to
            /// avoid false positives during transient section
            /// show/hide animations.
            func sectionKey(for item: MenuBarItem) -> String? {
                if item.bounds.minX >= hiddenMaxX {
                    return "visible"
                } else if let ahBounds, item.bounds.maxX <= ahBounds.minX {
                    return "alwaysHidden"
                } else if let ahBounds, item.bounds.minX >= ahBounds.maxX, item.bounds.maxX <= hiddenMinX {
                    return "hidden"
                } else if ahBounds == nil, item.bounds.maxX <= hiddenMinX {
                    return "hidden"
                }
                return nil
            }

            let relaunchedIdentifiers = Set(
                items
                    .filter { item in
                        guard !item.isControlItem,
                              !previousWindowIDSet.contains(item.windowID),
                              activeProfileItemIdentifiers.contains(item.uniqueIdentifier)
                        else { return false }
                        // If the item is already at its profile-
                        // expected section, the windowID change was
                        // benign; no re-sort needed. Items whose
                        // current section can't be determined fall
                        // through to the drop path.
                        if let expected = expectedSectionByID[item.uniqueIdentifier],
                           let current = sectionKey(for: item),
                           expected == current
                        {
                            return false
                        }
                        return true
                    }
                    .map(\.uniqueIdentifier)
            )
            let staleSorted = relaunchedIdentifiers.intersection(profileSortedItemIdentifiers)
            if !staleSorted.isEmpty {
                MenuBarItemManager.diagLog.info("Profile re-sort: detected \(staleSorted.count) relaunched profile item(s) with fresh windowID at wrong section: \(staleSorted.sorted())")
                profileSortedItemIdentifiers.subtract(staleSorted)
            }
        }

        if await relocateNewLeftmostItems(
            items,
            controlItems: controlItems,
            previousWindowIDs: previousWindowIDs,
            recentWindowIDs: recentWindowIDs
        ) {
            MenuBarItemManager.diagLog.debug("Relocated new leftmost items; scheduling recache")
            // Ownership transfers to the nested recache: the waiter must not
            // be told the cache is settled until the second cycle finishes.
            ownsWaiter = false
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                // Carry the bypass across the hand-off: this recache is where the
                // launch restore actually runs, and the move it is retrying behind
                // was stamped by the relocation just above.
                await self?.cacheItemsRegardless(
                    skipRecentMoveCheck: true,
                    bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                    waiterToken: waiterToken
                )
            }
            return
        }

        if await relocatePendingItems(items, controlItems: controlItems) {
            MenuBarItemManager.diagLog.debug("Relocated pending temporarily-shown items; scheduling recache")
            // Ownership transfers to the nested recache: the waiter must not
            // be told the cache is settled until the second cycle finishes.
            ownsWaiter = false
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                await self?.cacheItemsRegardless(
                    skipRecentMoveCheck: true,
                    bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                    waiterToken: waiterToken
                )
            }
            return
        }

        // Skip all restore logic during the startup settling period.
        // The settling period prevents cascading icon moves when many apps
        // load at login or restart in quick succession (app update checks).
        // A final cacheItemsRegardless() after the period ends handles restore.
        guard !isInStartupSettling else {
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)
            // Absorb items that appear during settling into the profile
            // snapshot so they aren't treated as late arrivals afterwards.
            if activeProfileLayout != nil {
                for item in items where !item.isControlItem {
                    profileSortedItemIdentifiers.insert(item.uniqueIdentifier)
                }
            }

            // One early apply restricted to items we can already identify,
            // rather than leaving the bar in macOS's arrangement for the
            // whole settling period. Waiting for every sourcePID means the
            // user watches an unsaved layout for as long as resolution takes
            // — ~8 s on a dense bar (#881). Restricted so the items still
            // being resolved are not move targets; the settling-end pass
            // runs unrestricted and LCS leaves whatever this placed alone.
            // The cooldown is bypassed rather than inherited from the caller.
            // relocateThawIcon moves our own control item within the first
            // ~100 ms of launch, so every settling poll that reaches here is
            // inside the 5 s window that same launch just stamped, and no
            // settling-period call site sets bypassSavedLayoutCooldown. In the
            // #881 log the early apply was rejected at 19.457 for a cooldown
            // stamped at 16.375 by relocateThawIcon, which left the reporter
            // watching macOS's arrangement for the whole settling period and
            // then the entire reorder as a visible sequence. Cascading
            // re-applies, which is what the cooldown guards against, cannot
            // happen here: this runs once per settling period.
            if !skipSavedLayoutApply, !didAttemptEarlySavedLayoutApply {
                let didApply = await applySavedLayout(
                    items: items,
                    previousWindowIDs: previousWindowIDs,
                    controlItems: controlItems,
                    previousDisplayID: itemCache.displayID,
                    currentDisplayID: displayID,
                    previousCCGenericWindowIDs: previousCCGenericWindowIDs,
                    bypassMoveCooldown: true,
                    resolvedIdentitiesOnly: true
                )
                // Spend the one attempt only on a dispatch that happened. The
                // flag used to be set before the call, so an apply rejected by
                // a guard consumed it and no later poll retried.
                if didApply {
                    didAttemptEarlySavedLayoutApply = true
                    MenuBarItemManager.diagLog.debug(
                        "cacheItemsRegardless: early saved-layout apply dispatched during settling"
                    )
                    return
                }
            }

            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: startup settling active, skipping restore")
            return
        }

        // Unified saved-layout restore: dispatch the bulk apply path
        // when window IDs have changed (app relaunch). applySavedLayout
        // owns its own cooldown and guard checks; applyProfileLayout's
        // body arms isRestoringItemOrder around the moves and drives
        // its own follow-up recache. On rejection the flag is left
        // false so saveSectionOrder can persist the current cache.
        //
        // The skipSavedLayoutApply gate exists so the post-apply
        // refresh scheduled by scheduleDeferredCacheRefresh does NOT
        // re-enter applySavedLayout. Without the gate the deferred
        // refresh runs cacheItemsRegardless → applySavedLayout →
        // dispatch → schedule another refresh, and because consecutive
        // getMenuBarItems calls can return slightly different windowID
        // sets (transient Apple Control Center widgets churn windowIDs
        // even when the visible item count is stable),
        // windowIDsChanged fires on every iteration and the bar enters
        // an infinite no-op apply loop.
        if !skipSavedLayoutApply {
            let didApplySavedLayout = await applySavedLayout(
                items: items,
                previousWindowIDs: previousWindowIDs,
                controlItems: controlItems,
                previousDisplayID: itemCache.displayID,
                currentDisplayID: displayID,
                previousCCGenericWindowIDs: previousCCGenericWindowIDs,
                bypassMoveCooldown: bypassSavedLayoutCooldown
            )
            if didApplySavedLayout {
                return
            }
        }

        await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)

        // Persist the resolved (possibly corrected) sourcePIDs for the next
        // cache cycle so transient resolution errors can be detected.
        // Only update when sourcePIDs were actually resolved; the settle-end
        // fast restore (resolveSourcePID=false) must not overwrite the baseline.
        if resolveSourcePID {
            let newPIDs = Dictionary(
                uniqueKeysWithValues: items.compactMap { item in
                    item.sourcePID.map { (item.windowID, $0) }
                }
            )
            cacheActor.updateCachedItemPIDs(newPIDs)
        }

        // Detect late-arriving items that belong to the active profile.
        if activeProfileLayout != nil,
           !activeProfileItemIdentifiers.isEmpty
        {
            await MainActor.run {
                guard profileResortTask == nil,
                      !isApplyingProfileLayout
                else { return }
                let newProfileItems = Self.lateArrivingProfileIdentifiers(
                    items: items,
                    profileIdentifiers: activeProfileItemIdentifiers,
                    alreadySortedIdentifiers: profileSortedItemIdentifiers
                )
                if !newProfileItems.isEmpty {
                    let unidentifiable = items.count { !$0.isControlItem && $0.sourcePID == nil }
                    if unidentifiable > 0 {
                        MenuBarItemManager.diagLog.debug(
                            "Profile re-sort: ignoring \(unidentifiable) item(s) with an unresolved sourcePID when detecting arrivals"
                        )
                    }
                    MenuBarItemManager.diagLog.info("Profile re-sort: detected \(newProfileItems.count) late-arriving profile item(s): \(newProfileItems.sorted())")
                    scheduleProfileResort()
                }
            }
        }

        await MainActor.run {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: finished, cache now has \(self.itemCache.managedItems.count) managed items")
        }

        // Keep the visible row inside the beside-notch budget regardless of
        // whether a profile is active. Runs last so it sees the settled cache,
        // and self-gates on every in-flight mover.
        await rebalanceNotchOverflowIfNeeded(items: items, controlItems: controlItems)
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        let rawWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        // Exclude windowIDs already known to be system clones so their
        // churn doesn't read as a layout change. A brand-new clone whose
        // windowID hasn't been learned yet still triggers one recache,
        // which resolves it, records it, and drops it; from then on its
        // presence and removal are ignored.
        let cloneIDs = cacheActor.cachedCloneWindowIDs
        let itemWindowIDs = cloneIDs.isEmpty
            ? rawWindowIDs
            : rawWindowIDs.filter { !cloneIDs.contains($0) }
        let cachedIDs = cacheActor.cachedItemWindowIDs

        // An empty reading against a populated cache is a failed observation,
        // not the menu bar emptying out. The `.activeSpace` filter resolves
        // the space ID separately from the window list, so during a Space
        // switch it matches the outgoing space and nothing passes the filter
        // — the next reading, milliseconds later, returns the full set again.
        // Treating the zero as real is what makes the layout editor blink its
        // items away and back while it sits open (#851).
        if itemWindowIDs.isEmpty, !cachedIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsIfNeeded: ignoring empty window ID reading against \(cachedIDs.count) cached, likely a Space switch"
            )
            return
        }

        if cachedIDs != itemWindowIDs {
            // While control-item lookups keep failing, the uncommitted
            // snapshot makes this branch fire on every poll; #933 measured
            // 27 hours of full recaches every 3 seconds against a failure
            // that was not going away. Skip silently inside the backoff
            // window — each attempt that does run logs its failure with the
            // streak count, so the lengthening gaps stay visible in the log.
            if let backoff = Self.controlItemLookupRetryBackoff(
                consecutiveFailures: controlItemLookupFailureStreak
            ),
                let lastFailure = lastControlItemLookupFailureAt,
                lastFailure.duration(to: .now) < backoff
            {
                return
            }
            MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: window IDs changed (\(cachedIDs.count) cached vs \(itemWindowIDs.count) current), triggering recache")
            await cacheItemsRegardless(itemWindowIDs)
            return
        }

        await recacheIfSourceProcessesResolved(itemWindowIDs)
    }

    /// Recaches when an item that had no source process last cycle has one now.
    ///
    /// The window ID comparison above asks whether the *set* of items changed.
    /// It cannot see a change in what is known *about* an item, and an item's
    /// source process is not read off its window — it is resolved by an AX scan
    /// in the XPC service that routinely misses on the first cold pass, because
    /// other apps' accessibility trees are still warming up seconds after login.
    ///
    /// A miss is not cosmetic. ``MenuBarItem/hasProvisionalIdentity`` spells out
    /// what an item is without its source: the namespace falls back to the owner
    /// of the window, which on macOS 26 is Control Center for every hosted status
    /// item, and the display name falls back to "Menu Bar Item". Both are wrong,
    /// and both were permanent — the item's window never goes anywhere, so no
    /// window ID ever changed, so nothing recached it, and a relaunch was the only
    /// way to get the real name back.
    ///
    /// ``SourcePIDNegativeCachePolicy`` was built for exactly this: it shortens
    /// the first retry deadlines so a warmer scan can land, and its own reasoning
    /// names the failure it cannot fix from that side — "the app stops requesting
    /// once settled". This is the app not stopping. The probe costs one XPC round
    /// trip per tick while anything is still unresolved and nothing at all once
    /// everything has resolved; the ladder is what bounds how often a request
    /// behind it becomes a real scan.
    private func recacheIfSourceProcessesResolved(_ itemWindowIDs: [CGWindowID]) async {
        let probeWindowIDs = Self.windowIDsNeedingSourceResolution(
            cachedItems: itemCache.managedItems,
            currentWindowIDs: itemWindowIDs
        )
        guard !probeWindowIDs.isEmpty else {
            return
        }

        // Second guard on the same rule as the filter above, against a title
        // this side can see and a cached item cannot: a duplicate Thaw process
        // can leave control-item windows behind under foreign window IDs.
        let windows = WindowInfo.createWindows(from: probeWindowIDs)
            .filter { !($0.title?.hasPrefix("Thaw.ControlItem.") ?? false) }
        guard !windows.isEmpty else {
            return
        }

        let resolved = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows).count { $0 != nil }
        guard resolved > 0 else {
            return
        }

        MenuBarItemManager.diagLog.info(
            """
            cacheItemsIfNeeded: \(resolved) of \(windows.count) item(s) cached without a \
            source process can now be resolved; recaching to give them their real identity
            """
        )
        await cacheItemsRegardless(itemWindowIDs)
    }

    /// The item windows worth asking the service about: the ones the cache is
    /// holding without a source process.
    ///
    /// Read from the cache rather than by differencing window IDs against the
    /// resolved-PID map, because these are the items actually on display under a
    /// provisional identity, and because the set can only shrink as they resolve
    /// — a probe can never talk the cache into recaching what it just cached.
    ///
    /// Control items are excluded for the reason
    /// ``MenuBarItem/getMenuBarItems(on:option:resolveSourcePID:)`` excludes them
    /// from resolution in the first place: their AX children are disabled
    /// dividers, so a request for one is a guaranteed miss that can start a full
    /// scan of every running app, and their PID is known locally anyway.
    ///
    /// Restricted to `currentWindowIDs` so an item the cache is still holding
    /// after its window is gone cannot keep the probe alive on its own.
    static nonisolated func windowIDsNeedingSourceResolution(
        cachedItems: [MenuBarItem],
        currentWindowIDs: [CGWindowID]
    ) -> [CGWindowID] {
        let current = Set(currentWindowIDs)
        return Array(
            cachedItems.lazy
                .filter { $0.sourcePID == nil && !$0.isControlItem && current.contains($0.windowID) }
                .map(\.windowID)
                .uniqued()
        )
    }
}

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    enum EventError: CustomStringConvertible, LocalizedError {
        /// A generic indication of a failure.
        case cannotComplete
        /// An event source cannot be created or is otherwise invalid.
        case invalidEventSource
        /// The location of the mouse cannot be found.
        case missingMouseLocation
        /// A failure during the creation of an event.
        case eventCreationFailure(MenuBarItem)
        /// A timeout during an event operation.
        case eventOperationTimeout(MenuBarItem)
        /// A menu bar item is not movable.
        case itemNotMovable(MenuBarItem)
        /// A timeout waiting for a menu bar item to respond to an event.
        case itemResponseTimeout(MenuBarItem)
        /// A menu bar item's bounds cannot be found.
        case missingItemBounds(MenuBarItem)
        /// A menu bar item's menu is tracking (e.g. the Wi-Fi picker or an
        /// input method panel is open) and the move was deferred.
        case menuTrackingActive(MenuBarItem)
        /// A menu bar item's owning process is alive but not pumping its
        /// event loop, so it cannot acknowledge synthetic move events.
        case ownerUnresponsive(MenuBarItem)
        /// A synthetic event came back through the session tap carrying a
        /// different window than the one it was addressed to, meaning the
        /// window server re-resolved it against whatever sits under the
        /// clamped cursor position.
        case eventWindowMismatch(MenuBarItem)
        /// The destination's target item moved so far during the drag that
        /// the plan describes an arrangement the bar no longer has. Retrying
        /// would drag the item against geometry that has already changed,
        /// which is how a failed batch walks the bar (#900).
        case staleDestination(MenuBarItem)

        var description: String {
            switch self {
            case .cannotComplete:
                "\(Self.self).cannotComplete"
            case .invalidEventSource:
                "\(Self.self).invalidEventSource"
            case .missingMouseLocation:
                "\(Self.self).missingMouseLocation"
            case let .eventCreationFailure(item):
                "\(Self.self).eventCreationFailure(item: \(item.tag))"
            case let .eventOperationTimeout(item):
                "\(Self.self).eventOperationTimeout(item: \(item.tag))"
            case let .itemNotMovable(item):
                "\(Self.self).itemNotMovable(item: \(item.tag))"
            case let .itemResponseTimeout(item):
                "\(Self.self).itemResponseTimeout(item: \(item.tag))"
            case let .missingItemBounds(item):
                "\(Self.self).missingItemBounds(item: \(item.tag))"
            case let .menuTrackingActive(item):
                "\(Self.self).menuTrackingActive(item: \(item.tag))"
            case let .ownerUnresponsive(item):
                "\(Self.self).ownerUnresponsive(item: \(item.tag))"
            case let .eventWindowMismatch(item):
                "\(Self.self).eventWindowMismatch(item: \(item.tag))"
            case let .staleDestination(item):
                "\(Self.self).staleDestination(item: \(item.tag))"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                "Operation could not be completed"
            case .invalidEventSource:
                "Invalid event source"
            case .missingMouseLocation:
                "Missing mouse location"
            case let .eventCreationFailure(item):
                "Could not create event for \"\(item.displayName)\""
            case let .eventOperationTimeout(item):
                "Event operation timed out for \"\(item.displayName)\""
            case let .itemNotMovable(item):
                "\"\(item.displayName)\" is not movable"
            case let .itemResponseTimeout(item):
                "\"\(item.displayName)\" took too long to respond"
            case let .missingItemBounds(item):
                "Missing bounds rectangle for \"\(item.displayName)\""
            case let .menuTrackingActive(item):
                "A menu bar item's menu was open while moving \"\(item.displayName)\""
            case let .ownerUnresponsive(item):
                "\"\(item.displayName)\" is not responding and cannot be moved"
            case let .eventWindowMismatch(item):
                "A move event for \"\(item.displayName)\" was delivered to the wrong window"
            case let .staleDestination(item):
                "The menu bar rearranged while moving \"\(item.displayName)\""
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self {
                return nil
            }
            return "Please try again. If the error persists, please file a bug report."
        }

        /// How the failure ledger should file this error.
        var failureKind: MenuBarItemFailureLedger.FailureKind {
            indicatesUnresponsiveOwner ? .unresponsiveOwner : .other
        }

        /// Whether this failure means the item's owner never acknowledged
        /// the events we posted.
        ///
        /// Only failures that are specifically about the owner staying
        /// silent count. `cannotComplete` is deliberately excluded: it is
        /// the catch-all, and attributing it to the owner would mark items
        /// over failures that had nothing to do with them.
        var indicatesUnresponsiveOwner: Bool {
            switch self {
            case .ownerUnresponsive, .eventOperationTimeout, .itemResponseTimeout:
                true
            case .cannotComplete, .invalidEventSource, .missingMouseLocation, .eventCreationFailure,
                 .itemNotMovable, .missingItemBounds, .menuTrackingActive, .eventWindowMismatch,
                 .staleDestination:
                false
            }
        }
    }

    /// Returns a Boolean value that indicates whether the user has
    /// paused input for at least the given duration.
    ///
    /// - Parameter duration: The duration that certain types of input
    ///   events must not have occurred within in order to return `true`.
    private nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
            !MouseHelpers.isButtonPressed()
    }

    /// Waits asynchronously for the user to pause input.
    private nonisolated func waitForUserToPauseInput() async throws {
        // The pre-move input-pause window is configurable so users hit by repeated cursor
        // "kidnapping" during menu-bar reordering can widen it. Reordering warps the real cursor,
        // and a very short window lets warps slip through the micro-gaps between a user's own mouse
        // moves when a churny app keeps changing its menu-bar items (see #750, #723, #736). The
        // default preserves the previous 50 ms behaviour; override with:
        //   defaults write com.stonerl.Thaw inputPauseThresholdMs -int <milliseconds>
        let pauseMs = max(
            0,
            (Defaults.object(forKey: .inputPauseThresholdMs) as? Int) ?? Defaults.DefaultValue.inputPauseThresholdMs
        )
        let waitTask = Task {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: .milliseconds(pauseMs)) {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        do {
            try await waitTask.value
        } catch {
            // Only cancellation reaches here. Named so a log full of bare
            // `cannotComplete` failures (#900) can tell this stage apart.
            MenuBarItemManager.diagLog.debug("waitForUserInputPause: wait interrupted: \(error)")
            throw EventError.cannotComplete
        }
    }

    /// Waits for a lull in user input before an automatic bulk apply
    /// begins issuing its move sequence.
    ///
    /// `waitForUserToPauseInput` gates each move; this gates the batch. The
    /// distinction matters because a batch hides the cursor for its entire
    /// length: dispatched the moment a late arrival is noticed, it can take
    /// the pointer away mid-interaction and then contest it move by move
    /// for the length of the sequence (#899, #723). Waiting for one real
    /// lull up front costs nothing on an idle bar — the common case, where
    /// the first poll already passes — and sidesteps the collision when the
    /// bar is not idle.
    ///
    /// Deferring only. The cap guarantees the batch still runs, and
    /// cancellation exits promptly so a newer apply can replace this one;
    /// the caller re-checks `Task.isCancelled` immediately afterwards.
    ///
    /// Off by default; enable with:
    ///   defaults write com.stonerl.Thaw bulkApplyIdleThresholdMs -int <milliseconds>
    private nonisolated func waitForBulkApplyIdleWindow() async {
        let thresholdMs = (Defaults.object(forKey: .bulkApplyIdleThresholdMs) as? Int)
            ?? Defaults.DefaultValue.bulkApplyIdleThresholdMs
        let capMs = (Defaults.object(forKey: .bulkApplyIdleWaitCapMs) as? Int)
            ?? Defaults.DefaultValue.bulkApplyIdleWaitCapMs
        guard let window = MenuBarItemManager.bulkApplyIdleWindow(
            thresholdMs: thresholdMs,
            capMs: capMs
        ) else {
            return
        }

        let start = ContinuousClock.now
        while !Task.isCancelled {
            let elapsed = ContinuousClock.now - start
            if MenuBarItemManager.bulkApplyIdleWaitConcluded(
                userHasPausedInput: hasUserPausedInput(for: window.threshold),
                elapsed: elapsed,
                cap: window.cap
            ) {
                if elapsed >= window.cap {
                    MenuBarItemManager.diagLog.debug(
                        "Bulk apply idle gate: cap reached after \(elapsed.milliseconds) ms without a lull; proceeding anyway"
                    )
                } else if elapsed > .zero {
                    MenuBarItemManager.diagLog.debug(
                        "Bulk apply idle gate: waited \(elapsed.milliseconds) ms for input to settle"
                    )
                }
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return // Cancelled; the caller's Task.isCancelled check handles it.
            }
        }
    }

    /// Waits between move operations for a dynamic amount of time,
    /// based on the timestamp of the last move operation.
    private nonisolated func waitForMoveOperationBuffer() async throws {
        if let timestamp = await lastMoveOperationTimestamp {
            let buffer = max(.milliseconds(25) - timestamp.duration(to: .now), .zero)
            MenuBarItemManager.diagLog.debug("Move operation buffer: \(buffer)")
            do {
                try await Task.sleep(for: buffer)
            } catch {
                MenuBarItemManager.diagLog.debug("waitForMoveOperationBuffer: wait interrupted: \(error)")
                throw EventError.cannotComplete
            }
        }
    }

    /// Waits for the given duration between event operations.
    ///
    /// Since most event operations must perform cleanup or otherwise
    /// run to completion, this method ignores task cancellation.
    private nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    /// Returns the current bounds for the given item, with a refresh fallback if the window is missing.
    private nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        // First attempt: current windowID.
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            return bounds
        }

        // Fallback: refresh on-screen items and pick the matching tag (prefer same windowID, then non-clone).
        let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
        if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        {
            return refreshedItem.bounds
        }

        throw EventError.missingItemBounds(item)
    }

    /// Returns the current mouse location.
    private nonisolated func getMouseLocation() throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw EventError.missingMouseLocation
        }
        return location
    }

    /// Returns the process identifier that can be used to create
    /// and post a menu bar item event.
    private nonisolated func getEventPID(for item: MenuBarItem) -> pid_t {
        Self.eventTargetPID(
            sourcePID: item.sourcePID,
            ownerPID: item.ownerPID,
            preferWindowOwner: MenuBarItem.postsMoveEventsToWindowOwner
        )
    }

    /// Whether a previously cached source PID still belongs to a live
    /// process.
    ///
    /// `kill(pid, 0)` is the same liveness probe `postMoveEvents` already
    /// makes before addressing a target, kept in one named place so the
    /// reconciliation guard and the event path agree about what "alive"
    /// means. `ESRCH` is the only answer that means gone; `EPERM` says the
    /// process exists but is not ours to signal, which still counts as
    /// alive.
    static nonisolated func previousPIDIsLive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    /// The process a synthetic move event should be posted to.
    ///
    /// `ownerPID` is the CG owner of the window being dragged. `sourcePID`
    /// is the app whose status item it logically is. Before macOS 26 these
    /// were the same process; on 26 Control Center hosts every status item
    /// window, so preferring `sourcePID` posts to a process that does not
    /// own the window under the cursor.
    ///
    /// Pure over its inputs.
    static nonisolated func eventTargetPID(
        sourcePID: pid_t?,
        ownerPID: pid_t,
        preferWindowOwner: Bool
    ) -> pid_t {
        if preferWindowOwner {
            return ownerPID
        }
        return sourcePID ?? ownerPID
    }

    /// Returns an event source for a menu bar item event operation.
    private nonisolated func getEventSource(
        with stateID: CGEventSourceStateID = .hidSystemState
    ) throws -> CGEventSource {
        enum Context {
            static let cache = OSAllocatedUnfairLock(initialState: [CGEventSourceStateID: CGEventSource]())
        }
        if let source = Context.cache.withLock({ $0[stateID] }) {
            return source
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError.invalidEventSource
        }
        Context.cache.withLock { $0[stateID] = source }
        return source
    }

    /// Prevents local events from being suppressed.
    private nonisolated func permitLocalEvents() throws {
        let source = try getEventSource(with: .combinedSessionState)
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }

    private nonisolated func storeContinuation(
        _ continuation: CheckedContinuation<Void, any Error>,
        in holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) {
        holder.withLock { $0 = continuation }
    }

    private nonisolated func storeInnerTask(
        _ task: Task<Void, Never>,
        in holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) {
        holder.withLock { $0 = task }
    }

    private nonisolated func currentContinuation(
        from holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) -> CheckedContinuation<Void, any Error>? {
        holder.withLock { $0 }
    }

    private nonisolated func currentInnerTask(
        from holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) -> Task<Void, Never>? {
        holder.withLock { $0 }
    }

    private nonisolated struct EventContinuationContext {
        let event: CGEvent
        let item: MenuBarItem
        let pid: pid_t
        let entryEvent: CGEvent
        let exitEvent: CGEvent
        let firstLocation: EventTap.Location
        let secondLocation: EventTap.Location
    }

    private nonisolated struct EventContinuationState {
        let countHolder: OSAllocatedUnfairLock<Int>
        let didResume: OSAllocatedUnfairLock<Bool>
        let continuationHolder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
        let innerTaskHolder: OSAllocatedUnfairLock<Task<Void, Never>?>
    }

    private nonisolated enum EventContinuationKind {
        case postEventBarrier
        case scromble
    }

    private nonisolated func decrementCount(
        in holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock {
            $0 -= 1
            return $0
        }
    }

    private nonisolated func currentCount(
        from holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock { $0 }
    }

    private nonisolated func disableEventTaps(_ eventTaps: [EventTap]) {
        for eventTap in eventTaps {
            eventTap.disable()
        }
    }

    private nonisolated func resumeCancellationIfNeeded(
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        if state.didResume.tryClaimOnce() {
            continuation.resume(throwing: CancellationError())
        }
    }

    /// Resumes the stored continuation by throwing `error`, if no other
    /// path has resumed it yet. Used to fail an in-flight event operation
    /// early instead of waiting out its timeout.
    private nonisolated func resumeFailureIfNeeded(
        state: EventContinuationState,
        error: any Error
    ) {
        let continuation = currentContinuation(from: state.continuationHolder)
        if let continuation, state.didResume.tryClaimOnce() {
            continuation.resume(throwing: error)
        }
    }

    /// Returns whether `rEvent` is a stray echo of this operation's own
    /// event: it carries the same `eventSourceUserData` — unique per posted
    /// event, so a positive identification — but its window fields no longer
    /// match the ones it was posted with.
    ///
    /// The window server re-resolves
    /// `mouseEventWindowUnderMousePointer*` against whatever actually sits
    /// under the cursor. For an item parked off the left edge, the posted
    /// coordinates get clamped to the display's leftmost edge — under the
    /// Apple menu — and the event comes back bound to that window instead.
    /// Left in the stream it is delivered there, which is what surfaces as a
    /// stray click at the top-left of the screen.
    private nonisolated func isStrayEcho(
        of rEvent: CGEvent,
        context: EventContinuationContext
    ) -> Bool {
        guard rEvent.matches(context.event, byIntegerFields: [.eventSourceUserData]) else {
            return false
        }
        return !rEvent.matches(context.event, byIntegerFields: CGEventField.menuBarItemEventFields)
    }

    /// Whether stray echoes of our own move events are dropped from the
    /// session stream before they can be delivered against the wrong window.
    ///
    /// On by default; this only ever discards events that are already
    /// misdirected — an echo whose window fields still match is passed
    /// through untouched, so the scromble handshake is unaffected. Kill
    /// switch, should it ever misfire:
    ///   defaults write com.stonerl.Thaw discardStrayMoveEvents -bool NO
    private nonisolated var discardsStrayMoveEvents: Bool {
        (Defaults.object(forKey: .discardStrayMoveEvents) as? Bool) ?? Defaults.DefaultValue.discardStrayMoveEvents
    }

    /// Whether a synthetic event that comes back addressed to a different
    /// window than it was posted with should fail its operation immediately
    /// rather than let it run to timeout.
    ///
    /// The mismatch is always logged; only the early failure is gated. The
    /// window server re-resolves the `mouseEventWindowUnderMousePointer*`
    /// fields against whatever actually sits under the cursor, so a mismatch
    /// is the signature of a move whose coordinates were clamped — the
    /// top-left/Apple-menu case for items parked off the left edge. Whether
    /// that is *always* unrecoverable is unverified on real hardware, hence
    /// the opt-in. Enable with:
    ///   defaults write com.stonerl.Thaw failFastOnEventWindowMismatch -bool YES
    private nonisolated var failsFastOnEventWindowMismatch: Bool {
        Defaults.bool(forKey: .failFastOnEventWindowMismatch)
    }

    private nonisolated func makeContinuationTask(
        eventTaps: [EventTap],
        state _: EventContinuationState,
        continuation _: CheckedContinuation<Void, any Error>,
        entryEvent: CGEvent,
        firstLocation: EventTap.Location
    ) -> Task<Void, Never> {
        Task {
            for eventTap in eventTaps {
                eventTap.enable()
            }
            entryEvent.post(to: firstLocation)
        }
    }

    private nonisolated func makeEventTap(
        label: String,
        type: CGEventType,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        handler: @escaping (EventTap, CGEvent) -> CGEvent?
    ) -> EventTap {
        EventTap(
            label: label,
            type: type,
            location: location,
            placement: placement,
            option: option,
            callback: handler
        )
    }

    private nonisolated func makeMenuBarItemEventTap(
        label: String,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        context: EventContinuationContext,
        onMismatch: ((CGEvent) -> Void)? = nil,
        onMatch: @escaping (EventTap) -> Void
    ) -> EventTap {
        makeEventTap(
            label: label,
            type: context.event.type,
            location: location,
            placement: placement,
            option: .listenOnly
        ) { tap, rEvent in
            guard rEvent.matches(context.event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                // `eventSourceUserData` is unique per posted event (see
                // `setUserData`), so matching on it alone positively
                // identifies this operation's own event. Getting here with
                // that field equal means the event came back with the window
                // fields rewritten — it was delivered against a different
                // window than the one it addressed.
                if rEvent.matches(context.event, byIntegerFields: [.eventSourceUserData]) {
                    onMismatch?(rEvent)
                }
                return rEvent
            }
            onMatch(tap)
            // Defensive: Since this EventTap is created with option: .listenOnly,
            // mutating rEvent via setTargetPID is for parity only and will not
            // affect the system event stream.
            rEvent.setTargetPID(context.pid)
            return rEvent
        }
    }

    private nonisolated func makeEntryEventTap(
        context: EventContinuationContext,
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) -> EventTap {
        makeEventTap(
            label: "EventTap 1",
            type: .null,
            location: context.firstLocation,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { tap, rEvent in
            if rEvent.matches(context.entryEvent, byIntegerFields: [.eventSourceUserData]) {
                _ = self.decrementCount(in: state.countHolder)
                context.event.post(to: context.secondLocation)
                return nil
            }
            if rEvent.matches(context.exitEvent, byIntegerFields: [.eventSourceUserData]) {
                tap.disable()
                if state.didResume.tryClaimOnce() {
                    continuation.resume()
                }
                return nil
            }
            return rEvent
        }
    }

    private nonisolated func makeSecondLocationEventTap(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 2",
            location: context.secondLocation,
            placement: .tailAppendEventTap,
            context: context,
            onMismatch: { [weak self] rEvent in
                guard let self else { return }
                let expected = context.event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
                let got = rEvent.getIntegerValueField(.mouseEventWindowUnderMousePointer)
                MenuBarItemManager.diagLog.warning(
                    """
                    Event for \(context.item.logString) came back on the wrong window \
                    (got \(got), expected \(expected)) at \(String(describing: rEvent.location))
                    """
                )
                if failsFastOnEventWindowMismatch {
                    resumeFailureIfNeeded(
                        state: state,
                        error: EventError.eventWindowMismatch(context.item)
                    )
                }
            },
            onMatch: { tap in
                switch kind {
                case .postEventBarrier:
                    if self.currentCount(from: state.countHolder) <= 0 {
                        tap.disable()
                        context.exitEvent.post(to: context.firstLocation)
                    } else {
                        context.entryEvent.post(to: context.firstLocation)
                    }
                case .scromble:
                    if self.currentCount(from: state.countHolder) <= 0 {
                        tap.disable()
                    }
                    context.event.post(to: context.firstLocation)
                }
            }
        )
    }

    private nonisolated func makeFirstLocationRelayEventTap(
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 3",
            location: context.firstLocation,
            placement: .headInsertEventTap,
            context: context
        ) { tap in
            if self.currentCount(from: state.countHolder) <= 0 {
                tap.disable()
                context.exitEvent.post(to: context.firstLocation)
            } else {
                context.entryEvent.post(to: context.firstLocation)
            }
        }
    }

    /// Creates a tap that removes stray echoes of this operation's own event
    /// from the session stream, so they cannot be delivered against the
    /// window the window server re-bound them to.
    ///
    /// Head-inserted and non-listen-only, so it runs before the tail-appended
    /// handshake taps and can actually drop the event. This is safe with
    /// respect to that handshake: those taps only act on echoes whose window
    /// fields still match, and such echoes are passed through here untouched.
    private nonisolated func makeStrayEventDiscardTap(
        context: EventContinuationContext
    ) -> EventTap {
        makeEventTap(
            label: "Stray move event discard",
            type: context.event.type,
            location: context.secondLocation,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { _, rEvent in
            guard self.isStrayEcho(of: rEvent, context: context) else {
                return rEvent
            }
            MenuBarItemManager.diagLog.debug(
                """
                Discarding stray echo of \(context.item.logString) move event \
                at \(String(describing: rEvent.location))
                """
            )
            return nil
        }
    }

    private nonisolated func makeContinuationEventTaps(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) -> [EventTap] {
        var eventTaps = [EventTap]()
        if discardsStrayMoveEvents {
            let strayEventDiscardTap = makeStrayEventDiscardTap(context: context)
            if strayEventDiscardTap.isValid {
                eventTaps.append(strayEventDiscardTap)
            } else {
                MenuBarItemManager.diagLog.error(
                    """
                    Failed to create stray move event discard tap for \
                    \(context.item.logString); continuing without stray echo \
                    protection for this operation
                    """
                )
            }
        }
        eventTaps.append(
            contentsOf: [
                makeEntryEventTap(
                    context: context,
                    state: state,
                    continuation: continuation
                ),
                makeSecondLocationEventTap(
                    kind: kind,
                    context: context,
                    state: state
                ),
            ]
        )
        if kind == EventContinuationKind.scromble {
            eventTaps.append(
                makeFirstLocationRelayEventTap(
                    context: context,
                    state: state
                )
            )
        }
        return eventTaps
    }

    private nonisolated func awaitEventContinuation(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState,
        eventTaps: inout [EventTap]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            storeContinuation(continuation, in: state.continuationHolder)

            let continuationEventTaps = makeContinuationEventTaps(
                kind: kind,
                context: context,
                state: state,
                continuation: continuation
            )
            eventTaps.append(contentsOf: continuationEventTaps)

            let innerTask = makeContinuationTask(
                eventTaps: continuationEventTaps,
                state: state,
                continuation: continuation,
                entryEvent: context.entryEvent,
                firstLocation: context.firstLocation
            )
            storeInnerTask(innerTask, in: state.innerTaskHolder)
            if Task.isCancelled {
                innerTask.cancel()
            }
        }
    }

    private nonisolated func performEventContinuationOperation(
        _ kind: EventContinuationKind,
        event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        let countHolder = OSAllocatedUnfairLock(initialState: count)

        let didResume = OSAllocatedUnfairLock(initialState: false)
        let continuationHolder = OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>(initialState: nil)
        let innerTaskHolder = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        let continuationContext = EventContinuationContext(
            event: event,
            item: item,
            pid: pid,
            entryEvent: entryEvent,
            exitEvent: exitEvent,
            firstLocation: firstLocation,
            secondLocation: secondLocation
        )
        let continuationState = EventContinuationState(
            countHolder: countHolder,
            didResume: didResume,
            continuationHolder: continuationHolder,
            innerTaskHolder: innerTaskHolder
        )

        let timeoutTask = Task(timeout: timeout * count) {
            var eventTaps = [EventTap]()
            defer {
                for tap in eventTaps {
                    tap.invalidate()
                }
            }
            try await withTaskCancellationHandler {
                try await awaitEventContinuation(
                    kind: kind,
                    context: continuationContext,
                    state: continuationState,
                    eventTaps: &eventTaps
                )
            } onCancel: {
                currentInnerTask(from: innerTaskHolder)?.cancel()
                // Directly resume the continuation; handles the common case where
                // innerTask already finished before cancellation was delivered.
                let cont = currentContinuation(from: continuationHolder)
                if let cont, didResume.tryClaimOnce() {
                    cont.resume(throwing: CancellationError())
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch let error as EventError {
            // Preserve failures raised from inside the continuation (e.g. a
            // window mismatch) so callers can tell them apart from a generic
            // failure and skip pointless retries.
            throw error
        } catch {
            // Cancellation of a superseded operation lands here. The
            // underlying error used to be discarded, leaving #900's log a
            // wall of indistinguishable `cannotComplete`s.
            MenuBarItemManager.diagLog.debug("postEvent: event wait for \(item.logString) failed: \(error)")
            throw EventError.cannotComplete
        }
    }

    /// Posts an event to the given menu bar item and waits until
    /// it is received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `postEventWithBarrier`.
    private nonisolated func postEventWithBarrier(
        _ event: CGEvent,
        to item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        try await performEventContinuationOperation(
            EventContinuationKind.postEventBarrier,
            event: event,
            item: item,
            timeout: timeout,
            repeating: count
        )
    }

    /// Casts forbidden magic to make a menu bar item receive and
    /// respond to an event during a move operation.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `scrombleEvent`.
    private nonisolated func scrombleEvent(
        _ event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        try await performEventContinuationOperation(
            EventContinuationKind.scromble,
            event: event,
            item: item,
            timeout: timeout,
            repeating: count
        )
    }
}

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    nonisolated enum MoveDestination: Equatable {
        /// The destination to the left of the given target item.
        case leftOfItem(MenuBarItem)
        /// The destination to the right of the given target item.
        case rightOfItem(MenuBarItem)

        /// The destination's target item.
        var targetItem: MenuBarItem {
            switch self {
            case let .leftOfItem(item), let .rightOfItem(item): item
            }
        }

        /// Returns the drag point for placing an item relative to the target bounds.
        ///
        /// Targets parked beyond the display's left edge use their vertical
        /// midpoint so a synthetic event clamped to the edge cannot land on a
        /// top Hot Corner. On-screen targets retain the existing top-edge
        /// coordinate to avoid changing normal cursor-warp behavior.
        func targetPoint(in targetBounds: CGRect, on displayBounds: CGRect) -> CGPoint {
            let targetIsParkedOffscreen = targetBounds.maxX <= displayBounds.minX
            let targetY = targetIsParkedOffscreen ? targetBounds.midY : targetBounds.minY
            // A zero-width control-item divider (#923) gives AppKit no
            // hit-test width to disambiguate which side the drop should
            // land on. Bias one point into the requested section so the
            // synthetic event's target X is unambiguous. On a normal-width
            // divider the ±1 nudge is harmless but unnecessary; gate it to
            // zero-width to avoid shifting the drop point away from a
            // divider that already has span to resolve the side.
            let sectionBias: CGFloat = (targetItem.isControlItem && targetBounds.width == 0) ? 1 : 0
            return switch self {
            case .leftOfItem:
                CGPoint(x: targetBounds.minX - sectionBias, y: targetY)
            case .rightOfItem:
                CGPoint(x: targetBounds.maxX + sectionBias, y: targetY)
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case let .leftOfItem(item): "left of \(item.logString)"
            case let .rightOfItem(item): "right of \(item.logString)"
            }
        }
    }

    /// Returns a safe location for an off-screen move's initial mouse-down.
    ///
    /// `NSScreen` frames use AppKit coordinates, while `CGEvent` locations use
    /// Core Graphics coordinates. Their horizontal axes align, so the notch
    /// supplies only the x-coordinate; the target supplies the event's y-coordinate.
    static nonisolated func notchMouseDownPoint(
        notchFrameAppKit: CGRect,
        targetPointCoreGraphics: CGPoint
    ) -> CGPoint {
        CGPoint(x: notchFrameAppKit.midX, y: targetPointCoreGraphics.y)
    }

    /// Returns the default timeout for move operations associated
    /// with the given item.
    private func getDefaultMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if item.isBentoBox {
            // Bento Boxes (i.e. Control Center groups) generally
            // take a little longer to respond.
            return .milliseconds(200)
        }
        return .milliseconds(100)
    }

    /// Returns the cached timeout for move operations associated
    /// with the given item.
    private func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultMoveOperationTimeout(for: item)
    }

    /// Updates the cached timeout for move operations associated
    /// with the given item.
    private func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        let current = getMoveOperationTimeout(for: item)
        let average = (timeout + current) / 2
        // Minimum of 75ms: waitForMoveEventResponse polls every 10ms, so a
        // timeout below ~75ms leaves too little margin for system event latency
        // and causes itemResponseTimeout → retry cascades.
        let clamped = average.clamped(min: .milliseconds(75), max: .milliseconds(500))
        moveOperationTimeouts[item.tag] = clamped
    }

    /// Prunes the move operation timeouts cache, keeping only the entries
    /// for the given valid tags.
    private func pruneMoveOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        moveOperationTimeouts = moveOperationTimeouts.filter { validTags.contains($0.key) }
    }

    /// Returns the default timeout for click operations based on the item's namespace.
    private func getDefaultClickOperationTimeout(for item: MenuBarItem) -> Duration {
        // Known slow apps with dynamic content
        let slowAppBundleIDs = [
            "com.bitsplash.PasteNow",
            "com.charliemonroe.Downie-setapp",
            "com.if.Amphetamine",
            "com.hegenberg.BetterTouchTool",
            "net.matthewpalmer.Vanilla",
        ]

        let namespaceString = item.tag.namespace.description
        if slowAppBundleIDs.contains(where: { namespaceString.contains($0) }) {
            return .milliseconds(500) // Extra time for slow apps
        }

        return .milliseconds(350) // Default
    }

    /// Returns the cached timeout for click operations associated with the given item.
    private func getClickOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = clickOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultClickOperationTimeout(for: item)
    }

    /// Updates the cached timeout for click operations associated with the given item.
    private func updateClickOperationTimeout(_ duration: Duration, for item: MenuBarItem) {
        let current = getClickOperationTimeout(for: item)
        let average = (duration + current) / 2
        let clamped = average.clamped(min: .milliseconds(200), max: .milliseconds(1000))
        clickOperationTimeouts[item.tag] = clamped
        MenuBarItemManager.diagLog.debug("Updated click timeout for \(item.logString): \(Int(clamped.milliseconds))ms (measured: \(Int(duration.milliseconds))ms)")
    }

    /// Prunes the click operation timeouts cache, keeping only the entries
    /// for the given valid tags.
    private func pruneClickOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        clickOperationTimeouts = clickOperationTimeouts.filter { validTags.contains($0.key) }
    }

    /// Returns the target points for creating the events needed to
    /// move a menu bar item to the given destination.
    private nonisolated func getTargetPoints(
        forMoving item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async throws -> (start: CGPoint, end: CGPoint) {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)

        let start = destination.targetPoint(
            in: targetBounds,
            on: CGDisplayBounds(displayID)
        )
        let end = start

        MenuBarItemManager.diagLog.debug(
            "Move points: startX=\(start.x) endX=\(end.x) startY=\(start.y) targetMinX=\(targetBounds.minX) itemMinX=\(itemBounds.minX) targetTag=\(destination.targetItem.tag) itemTag=\(item.tag) display=\(displayID)"
        )
        return (start, end)
    }

    /// Returns a Boolean value that indicates whether the given menu bar
    /// item has the correct position, relative to the given destination.
    /// Reports whether `item` is now the immediate neighbor of the
    /// destination's target on the requested side.
    ///
    /// This asks for the ordinal relationship rather than comparing
    /// coordinates. The check used to re-read both rects independently and
    /// compare them for exact `CGFloat` equality, which cannot succeed on a
    /// bar that reflows: our own drag displaces the target too, so the item
    /// lands where the target *was* and is then compared against where the
    /// target now is. In the #881 log the target's measured `minX` swung from
    /// -4222 to 794 between attempts while the item sat still, and all eight
    /// attempts were spent re-dragging against a destination that had already
    /// moved (#900).
    ///
    /// Reading one list fixes that: both operands come from the same snapshot,
    /// so they cannot drift apart mid-check. It also sidesteps
    /// ``getCurrentBounds(for:)`` mixing coordinate spaces — its windowID path
    /// answers for parked offscreen windows while its tag-matching fallback
    /// answers from the on-screen list, and which one runs depends on timing.
    ///
    /// - Note: source PIDs are deliberately left unresolved. Only tags, window
    ///   IDs and bounds are needed here, and this runs once per attempt.
    ///
    /// Main-actor isolated rather than `nonisolated`: the enumeration and the
    /// tag comparison both are, and hopping once per attempt costs nothing
    /// next to the enumeration itself.
    private func itemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async throws -> Bool {
        // Not `.onScreen`: an item moved into a collapsed section is parked
        // offscreen, and that is a landing we still have to be able to confirm.
        let items = await MenuBarItem
            .getMenuBarItems(on: displayID, option: .activeSpace, resolveSourcePID: false)
            .sorted { $0.bounds.minX < $1.bounds.minX }

        /// Prefer the exact window, falling back to the tag, matching the
        /// preference order `getCurrentBounds(for:)` already uses.
        func index(of needle: MenuBarItem) -> Int? {
            items.firstIndex { $0.windowID == needle.windowID }
                ?? items.firstIndex(matching: needle.tag)
        }

        guard
            let itemIndex = index(of: item),
            let targetIndex = index(of: destination.targetItem)
        else {
            // One of the two no longer enumerates on this display's active
            // space, so the landing cannot be confirmed either way. Report a
            // miss and let the caller's attempt budget decide what happens.
            return false
        }

        return switch destination {
        case .leftOfItem: itemIndex == targetIndex - 1
        case .rightOfItem: itemIndex == targetIndex + 1
        }
    }

    /// Waits for a menu bar item to respond to a series of previously
    /// posted move events.
    ///
    /// - Parameters:
    ///   - item: The item to check for a response.
    ///   - initialOrigin: The origin of the item before the events were posted.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func waitForMoveEventResponse(
        from item: MenuBarItem,
        initialOrigin: CGPoint,
        timeout: Duration
    ) async throws -> CGPoint {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }
        let responseTask = Task.detached {
            while true {
                try Task.checkCancellation()
                let origin = try await self.getCurrentBounds(for: item).origin
                if origin != initialOrigin {
                    return origin
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let timeoutTask = Task(timeout: timeout) {
            try await withTaskCancellationHandler {
                try await responseTask.value
            } onCancel: {
                responseTask.cancel()
            }
        }
        do {
            let origin = try await timeoutTask.value
            MenuBarItemManager.diagLog.debug(
                """
                Item responded to events with new origin: \
                \(String(describing: origin))
                """
            )
            return origin
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError.itemResponseTimeout(item)
        } catch {
            MenuBarItemManager.diagLog.debug("waitForItemResponse: wait for \(item.logString) failed: \(error)")
            throw EventError.cannotComplete
        }
    }

    /// Creates and posts a series of events to move a menu bar item
    /// to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    private func postMoveEvents(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID,
        warpCursorAfter: Bool = true
    ) async throws -> Duration {
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postMoveEvents, retrying once")
            do {
                try await eventSemaphore.wait(timeout: .milliseconds(3500))
                acquiredSemaphore = true
            } catch is SimpleSemaphore.TimeoutError {
                MenuBarItemManager.diagLog.error("postMoveEvents: eventSemaphore retry also timed out; giving up on \(item.logString)")
                throw EventError.cannotComplete
            }
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

        // Fast-fail if the target process is dead. CGEvent.tapCreateForPid
        // silently produces an invalid Mach port for dead PIDs, causing every
        // scrombleEvent to time out and burn the full 3.5 s semaphore budget.
        let eventPID = getEventPID(for: item)
        if kill(eventPID, 0) == -1, errno == ESRCH {
            MenuBarItemManager.diagLog.error("postMoveEvents: target PID \(eventPID) for \(item.logString) is dead; skipping move")
            throw EventError.cannotComplete
        }

        // A process that is alive but not pumping its event loop never
        // acknowledges the synthetic move, so every scrombleEvent below runs
        // to its timeout and burns the full 3.5 s semaphore budget — with the
        // semaphore held, that stalls every *other* item's move behind it.
        // Little Snitch is the recurring case (it ships with GUI Scripting
        // disabled), but this catches any hung owner. Bail out immediately
        // instead; the caller's retry/backoff path picks the item up again
        // once its owner starts responding.
        if Bridging.isProcessUnresponsive(eventPID) {
            MenuBarItemManager.diagLog.warning(
                "postMoveEvents: target PID \(eventPID) for \(item.logString) is unresponsive; skipping move"
            )
            throw EventError.ownerUnresponsive(item)
        }

        let itemBounds = try await getCurrentBounds(for: item)
        var itemOrigin = itemBounds.origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination, on: displayID)

        // Press and release at the *destination* (targetPoints.start == .end
        // == the target edge) with the moved item's window ID stamped on the
        // press, relying on the owner to relocate its item to the press
        // location. Every move observed in #881 needed a warm-up attempt
        // before that took: the first press nudged the item a pixel, the
        // second teleported it. A drag-gesture geometry was trialled behind
        // a setting to remove that warm-up and did not fix it, so it was
        // withdrawn; the warm-up attempt remains an open problem.
        let pressPoint = targetPoints.start

        // Capture mouse location only when this call owns the cursor warp.
        // When called from move(), the outer move() handles the single warp
        // at the end of all attempts so the cursor doesn't oscillate per attempt.
        let mouseLocation: CGPoint? = warpCursorAfter ? try getMouseLocation() : nil
        let source = try getEventSource()

        try permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .move(.mouseDown),
                location: pressPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: destination.targetItem,
                source: source,
                type: .move(.mouseUp),
                location: targetPoints.end
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        var timeout = getMoveOperationTimeout(for: item)
        MenuBarItemManager.diagLog.debug("Move operation timeout: \(timeout)")

        lastMoveOperationTimestamp = .now
        // Skip the warp when the target is offscreen (negative-X items in
        // hidden/always-hidden on notch displays). CGWarpMouseCursorPosition
        // clamps to the display's leftmost edge, which sits under the Apple
        // menu, and the resulting tracking events then route stray clicks
        // there. The 20ms eventSleep that follows the warp is only needed
        // when slow apps have to register the tracking events before the
        // mouseDown; irrelevant offscreen.
        let warpPoint = pressPoint
        let warpIsOnScreen = NSScreen.screens.contains {
            CGDisplayBounds($0.displayID).contains(warpPoint)
        }
        if warpIsOnScreen {
            // Load-bearing for event delivery — keep unconditionally, even
            // during a bulk apply: the receiving app's tracking needs the
            // cursor at the target location regardless of its visibility.
            MouseHelpers.warpCursor(to: warpPoint)
        }
        // During a bulk apply (applyProfileLayout's move sequence) the
        // cursor is already held hidden for the whole sequence and
        // restored once at its end (Phase 7). Hiding/showing again per
        // item here is redundant churn and, if the outer hide's refcount
        // is ever force-reset by its watchdog mid-sequence, is what turns
        // into the cursor visibly "yanked" across every remaining item's
        // move (#723). Skip it and rely on the sequence-level hide.
        // Sampled once and reused by the defer below. Reading the flag a
        // second time at defer time is not safe: a bulk apply can start
        // while this move is parked on one of the awaits in between, which
        // would pair a hide here with no show at all and strand the cursor
        // hidden until the bulk apply's 30 s watchdog fires.
        let ownsCursorVisibility = !isBulkApplyInProgress
        if ownsCursorVisibility {
            MouseHelpers.hideCursor()
        }
        if warpIsOnScreen {
            await eventSleep(for: .milliseconds(20))
        }
        // For notched displays, when the target is offscreen, redirect
        // mouseDown's horizontal hit-test location into the notch itself. The
        // notch is hardware with no clickable UI, so the OS hit-test there has
        // nothing to dismiss, no menu to open, and no app window to surface a
        // click against. Keep the Core Graphics y-coordinate inside the menu
        // bar; frameOfNotch is in AppKit coordinates and its y-coordinate would
        // instead point near the bottom of the display. mouseUp keeps its
        // original location (the drop position the receiving app uses to place
        // the item). For non-notched displays the original behaviour is
        // preserved (no override).
        if !warpIsOnScreen {
            let activeScreen = NSScreen.screens.first(where: { $0.displayID == displayID })
                ?? NSScreen.main
            if let activeScreen,
               activeScreen.hasNotch,
               let notch = activeScreen.frameOfNotch
            {
                mouseDown.location = Self.notchMouseDownPoint(
                    notchFrameAppKit: notch,
                    targetPointCoreGraphics: targetPoints.start
                )
            }
        }
        defer {
            if let mouseLocation {
                MouseHelpers.restoreCursorPosition(to: mouseLocation)
            }
            // Mirrors the skipped hideCursor() above: during a bulk apply
            // the sequence-level restoration (applyProfileLayout Phase 7)
            // owns showing the cursor once, at the end.
            if ownsCursorVisibility {
                MouseHelpers.showCursor()
            }
            lastMoveOperationTimestamp = .now
        }

        do {
            try await scrombleEvent(
                mouseDown,
                item: item,
                timeout: timeout
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            try await scrombleEvent(
                mouseUp,
                item: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Move events failed, posting fallback")
                try await scrombleEvent(
                    mouseUp,
                    item: item,
                    timeout: .milliseconds(100), // Fixed timeout for fallback.
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            timeout = Self.nextMoveOperationTimeout(after: timeout, outcome: .ownerDidNotRespond)
            updateMoveOperationTimeout(timeout, for: item)
            throw error
        }
        return timeout
    }

    /// Checks if a menu bar item is in a "blocked" state (positioned at x=-1 off-screen).
    /// Items in this state are stuck and cannot be interacted with normally.
    private nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try await getCurrentBounds(for: item)
            // x=-1 is the sentinel value macOS uses for "blocked" items
            return bounds.origin.x == -1
        } catch {
            // If we can't get bounds, assume it's not blocked
            return false
        }
    }

    /// Validates that an item moved to the hidden section didn't get stuck at x=-1.
    /// If the item is blocked, attempts to restore it to the visible section.
    private func validateItemPositionAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async {
        // Only recover items that got stuck when targeting the hidden divider.
        // Items placed adjacent to any other anchor are intentionally positioned;
        // recovering them to visible would undo a correct move.
        switch destination {
        case let .leftOfItem(anchor), let .rightOfItem(anchor):
            guard anchor.tag == .alwaysHiddenControlItem else { return }
        }

        // Check if item got stuck at x=-1
        if await isItemBlocked(item) {
            MenuBarItemManager.diagLog.warning("Item \(item.logString) stuck at x=-1 after move - attempting recovery")

            // Find the control item to use as anchor for recovery
            guard let appState else { return }
            guard let hiddenControlItem = appState.menuBarManager.controlItem(withName: .hidden)?.window else {
                MenuBarItemManager.diagLog.error("Cannot recover item: missing hidden control item window")
                return
            }

            // Create a MenuBarItem representation of the control item for the destination
            // We need to find it in the current cache
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard let hiddenMenuBarItem = items.first(where: { $0.windowID == CGWindowID(hiddenControlItem.windowNumber) }) else {
                MenuBarItemManager.diagLog.error("Cannot recover item: control item not found in menu bar items")
                return
            }

            // Attempt to move the item back to the visible section
            do {
                try await move(
                    item: item,
                    to: .rightOfItem(hiddenMenuBarItem),
                    on: displayID,
                    skipInputPause: true
                )
                MenuBarItemManager.diagLog.info("Successfully recovered \(item.logString) from blocked state to visible section")
            } catch {
                MenuBarItemManager.diagLog.error("Failed to recover \(item.logString) from blocked state: \(error)")
            }
        }
    }

    /// Returns whether the given item is currently in the "blocked" state
    /// (positioned at x=-1). Exposed so drag-failure callers can classify a
    /// failed move without duplicating the sentinel check performed by
    /// `isItemBlocked`.
    func isItemCurrentlyBlocked(_ item: MenuBarItem) async -> Bool {
        await isItemBlocked(item)
    }

    /// Attempts to move a blocked (x=-1) item back to the visible section,
    /// immediately right of the hidden control item — the same safe-harbor
    /// anchor used by `restoreBlockedItemsToVisible` and
    /// `validateItemPositionAfterMove`. This does not retry the original
    /// move; callers are responsible for retrying afterward if desired.
    ///
    /// - Returns: `true` if the rescue move completed without throwing.
    func rescueBlockedItemToVisible(_ item: MenuBarItem) async -> Bool {
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let hiddenMenuBarItem = items.first(matching: .hiddenControlItem) else {
            MenuBarItemManager.diagLog.error("Cannot rescue blocked item \(item.logString): hidden control item not found")
            return false
        }
        do {
            try await move(
                item: item,
                to: .rightOfItem(hiddenMenuBarItem),
                skipInputPause: true,
                watchdogTimeout: Self.layoutWatchdogTimeout
            )
            return true
        } catch {
            MenuBarItemManager.diagLog.error("Failed to rescue blocked item \(item.logString): \(error)")
            return false
        }
    }

    /// The outcome to take when a hidden-section drag's move throws after
    /// the drag handler's resample-and-verify pass.
    nonisolated enum HiddenDragFailureAction: Equatable {
        /// The item actually reached its intended position; the throw was a
        /// false alarm from verification racing macOS's own settle. No
        /// alert needed.
        case suppress
        /// The item is stuck at the x=-1 sentinel. It can be rescued to the
        /// visible section and the original move retried once.
        case rescueAndRetry
        /// The hidden-section control item couldn't be resolved; recovery
        /// is already running in the background (see plan 004). Show a
        /// calm, specific message instead of the raw error.
        case alertControlItemsMissing
        /// None of the above; show the raw error as before.
        case alertGeneric
    }

    /// Pure classification of a failed hidden-section drag, used to decide
    /// whether to suppress, rescue-and-retry, or alert (and with which
    /// message). Precedence: reaching the position beats being blocked;
    /// being blocked beats missing control items.
    static nonisolated func classifyHiddenDragFailure(
        reachedPosition: Bool,
        isBlocked: Bool,
        controlItemsMissing: Bool
    ) -> HiddenDragFailureAction {
        if reachedPosition {
            .suppress
        } else if isBlocked {
            .rescueAndRetry
        } else if controlItemsMissing {
            .alertControlItemsMissing
        } else {
            .alertGeneric
        }
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        watchdogTimeout: Duration? = nil,
        maxMoveAttempts: Int = 8
    ) async throws {
        // System clone windows are transient WindowServer duplicates that
        // must never be moved. Refuse here as a final safety net so no
        // planning path can drag a phantom and displace real items. The
        // planners filter clones earlier; this backstops every move caller.
        // A no-op is correct: the clone has no managed position to restore
        // and will vanish on its own, so there's nothing to fail or retry.
        guard !item.isSystemClone else {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - system status item clone")
            return
        }
        guard item.isMovableAddressingWindowOwner else {
            // The refusal used to be silent (#905): name the gate and the
            // identifier the decision was made on, so a report can tell a
            // static macOS prohibition from an identity-resolution failure.
            MenuBarItemManager.diagLog.warning(
                "move: refusing \(item.logString): \(item.immovabilityReason?.logDescription ?? "isMovable false with no named gate"); uniqueIdentifier=\(item.uniqueIdentifier), sourcePID=\(item.sourcePID.map(String.init) ?? "nil")"
            )
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            MenuBarItemManager.diagLog.error("move: no appState; cannot move \(item.logString)")
            throw EventError.cannotComplete
        }

        // Never drag an item while a menu bar item menu is tracking — a synthetic
        // Cmd-drag tears down the user's interaction (Wi-Fi picker, input methods).
        // Wait briefly for the menu to close; if it stays open, give up this attempt.
        var menuWaitAttempts = 0
        while await isAnyMenuBarItemMenuOpen() {
            menuWaitAttempts += 1
            if menuWaitAttempts > 20 { // ~5s at 250ms steps
                MenuBarItemManager.diagLog.warning("move: menu still open after wait; deferring move of \(item.logString)")
                throw EventError.menuTrackingActive(item)
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        // Allow right-of-item moves to proceed even when the item is at x=-1.
        // validateItemPositionAfterMove uses exactly this path to rescue stuck
        // items. Block all other moves: dragging a stuck item deeper into a
        // hidden section could leave it in an unknown position.
        if await isItemBlocked(item) {
            guard case .rightOfItem = destination else {
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - item is blocked (x=-1)")
                throw EventError.cannotComplete
            }
            MenuBarItemManager.diagLog.debug("Proceeding with move of blocked \(item.logString); recovery to visible")
        }

        // Determine display ID early.
        let resolvedDisplayID: CGDirectDisplayID = if let displayID {
            displayID
        } else if let window = appState.hidEventManager.bestScreen(appState: appState) {
            window.displayID
        } else {
            Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        if !skipInputPause {
            try await waitForUserToPauseInput()
        }
        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        try await waitForMoveOperationBuffer()

        MenuBarItemManager.diagLog.info(
            """
            Moving \(item.logString) to \
            \(destination.logString) on display \(resolvedDisplayID)
            """
        )

        guard try await !itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) else {
            MenuBarItemManager.diagLog.debug("Item has correct position, cancelling move")
            return
        }

        // Capture the original cursor position once so the cursor is warped
        // back to it a single time after all attempts, rather than after each
        // individual attempt (which caused the cursor to oscillate many times
        // during a layout reset when items required multiple attempts).
        let mouseLocation = try getMouseLocation()
        // The default 1 s cursor-hide watchdog is too short for menu
        // bar item moves: each item can take up to ~4 s across retries
        // (8 attempts × ~500 ms timeout), and during a full layout pass
        // many items move sequentially. When the watchdog fires partway
        // through, the cursor is force-shown at the synthetic event's
        // last cursorPosition (mid-display, per the offscreen-target
        // override below in postMoveEvents) and the user sees a brief
        // cursor flash. 10 s is long enough to cover any single move
        // without giving up the safety net for genuinely stuck states.
        MouseHelpers.hideCursor(watchdogTimeout: watchdogTimeout ?? .seconds(10))
        defer {
            MouseHelpers.restoreCursorPosition(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        // Tracks whether any postMoveEvents attempt produced observable
        // displacement. Only consulted on retries when the item being
        // moved is a zero-width control item (section divider), where
        // a position match can coincide with bounds drifting onto the
        // target externally; ordinary items skip this gate.
        var anyMoveEventsSucceeded = false

        // Baseline for the stale-plan check in the retry path. The destination
        // was chosen against the bar as it looked when this move was planned;
        // if the target itself travels a long way while we are dragging, the
        // plan describes an arrangement that no longer exists.
        let plannedTargetBounds = try? await getCurrentBounds(for: destination.targetItem)

        // Where the target has sat at the end of each failed attempt. A
        // single nudge is expected; a run of them in one direction is the
        // move pushing its own anchor. See `targetIsRetreating`.
        var targetMinXHistory: [CGFloat] = plannedTargetBounds.map { [$0.minX] } ?? []

        let maxAttempts = max(1, maxMoveAttempts)
        for n in 1 ... maxAttempts {
            guard !Task.isCancelled else {
                MenuBarItemManager.diagLog.debug("move: cancelled before attempt \(n) for \(item.logString)")
                throw EventError.cannotComplete
            }
            do {
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) {
                    // On the first iteration trust the position match
                    // unconditionally. On retries, the only case where the
                    // match can be a coincidence is when the item being
                    // moved is itself a zero-width control item; gate
                    // those on observed displacement, accept all others.
                    if n == 1 || anyMoveEventsSucceeded || !item.isControlItem {
                        MenuBarItemManager.diagLog.debug("Item has correct position, finished with move")
                        return
                    }
                    MenuBarItemManager.diagLog.debug(
                        "Position match without observable displacement on attempt \(n); treating as false positive on a zero-width control item and retrying"
                    )
                }
                let attemptTimeout = try await postMoveEvents(
                    item: item,
                    destination: destination,
                    on: resolvedDisplayID,
                    warpCursorAfter: false // move() owns the single warp in its defer
                )
                // postMoveEvents only returns without throwing when both
                // waitForMoveEventResponse calls observed origin changes,
                // i.e. our drag actually displaced the item.
                anyMoveEventsSucceeded = true
                // Verify the item actually reached the correct position.
                let landedOnDestination = try await itemHasCorrectPosition(
                    item: item,
                    for: destination,
                    on: resolvedDisplayID
                )
                // `postMoveEvents` only observes displacement. Let this
                // single post-event landing check decide whether the next
                // attempt earns a shorter budget or keeps it unchanged;
                // querying Window Server in both places made misses look like
                // successful moves (#889).
                updateMoveOperationTimeout(
                    Self.nextMoveOperationTimeout(
                        after: attemptTimeout,
                        outcome: landedOnDestination ? .landed : .displacedWithoutLanding
                    ),
                    for: item
                )
                if landedOnDestination {
                    // Logged at info so the warm-up attempt cost can be read
                    // straight off a field log: grep "Move landed" and compare
                    // the attempt counts.
                    MenuBarItemManager.diagLog.info(
                        "Move landed: \(item.logString) after \(n) attempt(s)"
                    )
                    MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded and verified, finished with move")
                    failureLedger.recordSuccess(for: item)
                    // Validate that item didn't get stuck when moving to hidden section
                    await validateItemPositionAfterMove(item: item, destination: destination, on: resolvedDisplayID)
                    return
                }
                // Retrying against a target that has already moved re-plans
                // each attempt against different geometry and drags the item
                // somewhere new every time, which is what leaves a failed
                // batch with a fresh partial arrangement on every pass (#900).
                // Stop instead and let the next cache tick re-plan against a
                // settled bar.
                let currentTargetBounds = try? await getCurrentBounds(for: destination.targetItem)
                if let currentTargetBounds {
                    targetMinXHistory.append(currentTargetBounds.minX)
                }
                if let plannedTargetBounds,
                   let currentTargetBounds,
                   Self.destinationIsStale(
                       plannedTargetMinX: plannedTargetBounds.minX,
                       currentTargetMinX: currentTargetBounds.minX,
                       displayWidth: CGDisplayBounds(resolvedDisplayID).width
                   )
                {
                    MenuBarItemManager.diagLog.warning(
                        """
                        Attempt \(n): \(destination.targetItem.logString) moved from \
                        minX=\(plannedTargetBounds.minX) to minX=\(currentTargetBounds.minX) \
                        during the drag, abandoning the stale move
                        """
                    )
                    throw EventError.staleDestination(item)
                }
                // Small steps that never trip the stale threshold still walk
                // the anchor across the bar if they all go the same way, and
                // when the anchor is one of Thaw's dividers that ends in a
                // zero-width hidden section (#924, #927). Stop and let the
                // next cache tick re-plan against a settled bar.
                if Self.targetIsRetreating(recentTargetMinX: targetMinXHistory) {
                    MenuBarItemManager.diagLog.warning(
                        """
                        Attempt \(n): \(destination.targetItem.logString) has retreated on every \
                        recent attempt (minX \(targetMinXHistory.map { String(format: "%.0f", $0) }.joined(separator: " → "))) \
                        while \(item.logString) did not land; abandoning rather than pushing it further
                        """
                    )
                    throw EventError.staleDestination(item)
                }
                MenuBarItemManager.diagLog.debug("Attempt \(n) events succeeded but item not at destination, retrying")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
            } catch {
                // missingItemBounds is definitive: getCurrentBounds already
                // refreshed the on-screen items and re-matched by tag before
                // throwing, so the item's window is genuinely gone (transient
                // Control Center item vanished, owning app quit). Retrying
                // just warps the hidden cursor into the menu bar once per
                // remaining attempt for an item that cannot be moved (#736).
                if case EventError.missingItemBounds = error {
                    MenuBarItemManager.diagLog.warning(
                        "Attempt \(n): \(item.logString) no longer reports bounds, aborting move"
                    )
                    throw error
                }
                // Also definitive for the duration of this call: a hung owner
                // will not start pumping its event loop within the few hundred
                // milliseconds between attempts, so the remaining attempts
                // would only re-pay the semaphore wait. Callers retry the item
                // on a later cache tick, by which point it may have recovered.
                if case EventError.ownerUnresponsive = error {
                    MenuBarItemManager.diagLog.warning(
                        "Attempt \(n): \(item.logString) owner is unresponsive, aborting move"
                    )
                    failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    throw error
                }
                // Raised by the stale-plan check above, which has already
                // logged. Retrying is precisely what it exists to prevent, and
                // the item's owner did nothing wrong, so no failure is filed
                // against it.
                if case EventError.staleDestination = error {
                    throw error
                }
                // An owner with a standing record of ignoring synthetic events
                // gets no further attempts once it fails this way again. This
                // is deliberately narrower than capping maxAttempts up front:
                // the loop also retries when the owner *did* respond but the
                // item did not land, which is a different failure and still
                // deserves its full budget. Capping up front would strip those
                // retries too, and since the move would then fail, the item
                // could never earn the success that clears its record.
                if let error = error as? EventError,
                   error.indicatesUnresponsiveOwner,
                   failureLedger.isUnresponsive(item)
                {
                    MenuBarItemManager.diagLog.warning(
                        "Attempt \(n): \(item.logString) failed the way it always does, aborting move"
                    )
                    failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    throw error
                }
                MenuBarItemManager.diagLog.debug("Attempt \(n) failed: \(error)")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
                if let error = error as? EventError {
                    if error.indicatesUnresponsiveOwner {
                        failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    }
                    throw error
                }
                MenuBarItemManager.diagLog.warning("move: final attempt for \(item.logString) failed with non-EventError: \(error)")
                throw EventError.cannotComplete
            }
        }

        // All attempts exhausted without confirmed position. Run the stuck-item
        // validator first (recovers x=-1 blocks), then throw so callers know
        // the item did not reach the destination.
        await validateItemPositionAfterMove(item: item, destination: destination, on: resolvedDisplayID)
        MenuBarItemManager.diagLog.error("move: all \(maxAttempts) attempt(s) exhausted without verifying \(item.logString) reached \(destination.logString)")
        throw EventError.cannotComplete
    }
}

// MARK: - Clicking Items

extension MenuBarItemManager {
    /// Returns the equivalent event subtypes for clicking a menu bar
    /// item with the given mouse button.
    private nonisolated func getClickSubtypes(
        for mouseButton: CGMouseButton
    ) -> (down: MenuBarItemEventType.ClickSubtype, up: MenuBarItemEventType.ClickSubtype) {
        switch mouseButton {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }

    /// Creates and posts a series of events to click a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        // Try to acquire semaphore with timeout. 3.5 s covers legitimate slow
        // operations (adaptive click cap is 1000 ms × 2 for double mouseUp =
        // ~2 s of event work plus overhead).
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postClickEvents for \(item.logString), retrying once")
            do {
                try await eventSemaphore.wait(timeout: .milliseconds(3500))
                acquiredSemaphore = true
            } catch is SimpleSemaphore.TimeoutError {
                throw EventError.cannotComplete
            }
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

        let clickPoint = try await getCurrentBounds(for: item).center

        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        let clickTypes = getClickSubtypes(for: mouseButton)
        // Use adaptive timeout based on app performance history
        let timeout = getClickOperationTimeout(for: item)

        MenuBarItemManager.diagLog.debug("postClickEvents: using timeout \(Int(timeout.milliseconds))ms for \(item.logString)")

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.down),
                location: clickPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.up),
                location: clickPoint
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        // Warp the cursor to the click point so the Window Server's hit-test
        // matches the event coordinates rather than the cursor's current position.
        MouseHelpers.warpCursor(to: clickPoint)
        // Small delay to let the Window Server process the warp before posting
        // the event. Without this, the event can be routed using the cursor's
        // old position (e.g. the Apple menu) instead of the warped target.
        try await Task.sleep(for: .milliseconds(10))
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.restoreCursorPosition(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        let eventStartTime = Date.now
        do {
            try await postEventWithBarrier(
                mouseDown,
                to: item,
                timeout: timeout
            )
            try await postEventWithBarrier(
                mouseUp,
                to: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )

            // Update timeout cache with successful duration
            let successDuration = Duration.milliseconds(Date.now.timeIntervalSince(eventStartTime) * 1000)
            updateClickOperationTimeout(successDuration, for: item)
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(
                    mouseUp,
                    to: item,
                    timeout: timeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            throw error
        }
    }

    /// Activates a menu bar item by opening its menu, choosing the correct
    /// path based on whether the item is currently on screen.
    ///
    /// On-screen items are clicked in place. Off-screen items (in the hidden
    /// or always-hidden section) are routed through temporarilyShow, which
    /// moves, clicks, and rehides the item internally.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to activate.
    ///   - displayID: The display whose menu bar hosts a temporary reveal for
    ///     off-screen items.
    func activate(item: MenuBarItem, on displayID: CGDirectDisplayID?) async {
        if Bridging.isWindowOnScreen(item.windowID) {
            // Electron/Chromium tray items (e.g. Claude) ignore Thaw's synthetic
            // mouse click, so open those via an Accessibility press. Every other
            // app responds to the normal click, which also preserves its native
            // open/close toggle and works with popover-style menus (e.g. Cap,
            // Droppy) that a stray AX interaction would disturb.
            if isElectronItem(item), pressItemViaAccessibility(item) {
                MenuBarItemManager.diagLog.info("Activated \(item.logString) via AX press")
                return
            }
            do {
                try await click(item: item, with: .left)
            } catch {
                MenuBarItemManager.diagLog.error("Failed to activate \(item.logString): \(error)")
            }
        } else {
            await temporarilyShow(item: item, clickingWith: .left, on: displayID)
        }
    }

    /// Returns whether the item's owning app is an Electron app, detected by the
    /// presence of the bundled Electron framework. Such apps ignore synthetic
    /// mouse clicks on their tray icon and must be opened via an AX press.
    private func isElectronItem(_ item: MenuBarItem) -> Bool {
        // Fall back to ownerPID so this works during startup before sourcePID
        // has been resolved.
        let pid = item.sourcePID ?? item.ownerPID
        guard let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL else {
            return false
        }
        let electronFramework = bundleURL.appendingPathComponent(
            "Contents/Frameworks/Electron Framework.framework"
        )
        return FileManager.default.fileExists(atPath: electronFramework.path)
    }

    /// Attempts to open the item's menu by performing an Accessibility press on
    /// its status item element. Returns false (so the caller can fall back to
    /// a synthetic click) when the element cannot be resolved or the press fails.
    private func pressItemViaAccessibility(_ item: MenuBarItem) -> Bool {
        // Fall back to ownerPID so this works during startup before sourcePID
        // has been resolved.
        let pid = item.sourcePID ?? item.ownerPID
        guard
            let runningApp = NSRunningApplication(processIdentifier: pid),
            let app = AXHelpers.application(for: runningApp),
            let extrasMenuBar = AXHelpers.extrasMenuBar(for: app)
        else {
            return false
        }

        let children = AXHelpers.children(for: extrasMenuBar)
        guard !children.isEmpty else {
            return false
        }

        // A single status item is unambiguous. With several, match the one whose
        // AX frame lines up with this item's window so the right menu opens.
        let target: UIElement
        if children.count == 1 {
            target = children[0]
        } else {
            // Use the item's live window bounds so the nearest-child match is not
            // thrown off by a stale cached position (which would make an Electron
            // item fall back to the synthetic click it ignores).
            let itemCenter = (Bridging.getWindowBounds(for: item.windowID) ?? item.bounds).center
            guard
                let best = children.min(by: { lhs, rhs in
                    let lhsDistance = AXHelpers.frame(for: lhs)?.center.distance(to: itemCenter) ?? .greatestFiniteMagnitude
                    let rhsDistance = AXHelpers.frame(for: rhs)?.center.distance(to: itemCenter) ?? .greatestFiniteMagnitude
                    return lhsDistance < rhsDistance
                }),
                let bestFrame = AXHelpers.frame(for: best),
                bestFrame.center.distance(to: itemCenter) <= 10
            else {
                return false
            }
            target = best
        }

        return AXHelpers.press(target)
    }

    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    ///   - skipInputPause: Skip waiting for user input to pause.
    ///   - maxAttempts: Maximum number of click attempts (default 3).
    ///     Pass `1` from `temporarilyShow` so a single failure returns
    ///     immediately and the caller's fallback path fires promptly.
    /// - Returns: What the owner was observed to do in response. Callers
    ///   that need the window the click opened can read it from here
    ///   instead of scanning for it themselves.
    @discardableResult
    func click(
        item: MenuBarItem,
        with mouseButton: CGMouseButton,
        skipInputPause: Bool = false,
        maxAttempts: Int = 3
    ) async throws -> ClickReactionVerifier.Reaction {
        guard let appState else {
            throw EventError.cannotComplete
        }

        if mouseButton == .left, appState.settings.advanced.useAXClickDelivery == true {
            let snapshot = ClickReactionVerifier.snapshot(for: item)
            do {
                try await AXItemActivator.activate(item: item)
                MenuBarItemManager.diagLog.debug("Activated \(item.logString) via AX click delivery")
                return await ClickReactionVerifier.verify(against: snapshot)
            } catch {
                // Last check before the fallback, because the fallback is a
                // click and a click on an item that already opened its menu
                // shuts it. The activator makes the same check between its own
                // attempts; this covers the errors raised before it gets that
                // far, where an action may still have landed.
                let reaction = await ClickReactionVerifier.verify(against: snapshot)
                if reaction.didReact {
                    MenuBarItemManager.diagLog.debug(
                        "AX activation reported \(error) but \(item.logString) reacted; not clicking on top of it"
                    )
                    return reaction
                }
                MenuBarItemManager.diagLog.debug("AX activation failed (\(error)), falling back to synthetic click")
            }
        }

        if !skipInputPause {
            try await waitForUserToPauseInput()
        }

        MenuBarItemManager.diagLog.info(
            """
            Clicking \(item.logString) with \
            \(mouseButton.logString)
            """
        )

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // An owner already known to ignore synthetic events gets one attempt
        // instead of three. Retrying it only repeats the cursor warp that the
        // user sees as the item jittering, and the extra attempts have never
        // been what makes such an owner answer.
        let maxAttempts: Int = if failureLedger.isUnresponsive(item) {
            1
        } else {
            max(1, maxAttempts)
        }
        let attemptStartTime = Date.now
        for n in 1 ... maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                let clickStartTime = Date.now
                let snapshot = ClickReactionVerifier.snapshot(for: item)
                try await postClickEvents(item: item, mouseButton: mouseButton)
                let clickDuration = Date.now.timeIntervalSince(clickStartTime)
                MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded in \(Int(clickDuration * 1000))ms, finished with click")

                // The events landed. Whether the owner did anything with
                // them is a separate question, and only a yes is allowed
                // to clear a standing unresponsive mark: an owner that
                // drops synthetic events acknowledges them exactly like
                // one that acts on them, so crediting the post itself
                // would forgive the very behaviour the mark records.
                let reaction = await ClickReactionVerifier.verify(against: snapshot)
                if reaction.didReact {
                    failureLedger.recordSuccess(for: item)
                } else {
                    MenuBarItemManager.diagLog.debug(
                        "\(item.logString) acknowledged the click but was not seen reacting to it"
                    )
                }
                return reaction
            } catch {
                let attemptDuration = Date.now.timeIntervalSince(attemptStartTime)
                MenuBarItemManager.diagLog.debug("Attempt \(n) failed after \(Int(attemptDuration * 1000))ms: \(error)")
                if n < maxAttempts {
                    await eventSleep()
                    continue
                }
                if let error = error as? EventError {
                    if error.indicatesUnresponsiveOwner {
                        failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    }
                    throw error
                }
                throw EventError.cannotComplete
            }
        }

        // Unreachable: the loop runs at least once and every path through
        // it either returns or throws.
        throw EventError.cannotComplete
    }
}

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    private final class TemporarilyShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The PID used to match this item back on the bar at rehide time.
        let sourcePID: pid_t

        /// Every process that could plausibly own this item's interface.
        ///
        /// The process that owns an item's *window* and the one that owns the
        /// *menu* that window opens are not always the same. On macOS 26
        /// Control Center hosts the status item while the app draws the menu,
        /// so a lookup keyed on either PID alone misses. It matters most for
        /// an item whose `sourcePID` never resolved, where collapsing to a
        /// single PID via `?? ownerPID` yields Control Center's — and the
        /// app's open menu can then never be found, so the rehide tears it
        /// down (#924).
        ///
        /// ``ClickReactionVerifier/Snapshot/pids`` accepts both for the same
        /// reason; this keeps the two in agreement.
        let interfacePIDs: Set<pid_t>

        /// The display identifier where the item was shown.
        let displayID: CGDirectDisplayID

        /// The destination to return the item to (captured at show-time).
        /// This is the preferred destination, but may become stale if the
        /// target item has moved or disappeared by the time we rehide.
        let returnDestination: MoveDestination

        /// The neighbor on the opposite side of the ``returnDestination``,
        /// used as a secondary fallback to preserve relative ordering when
        /// the primary target is gone.
        let fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?

        /// The original section the item belonged to before being temporarily
        /// shown. Used as a last-resort fallback when both neighbor-based
        /// destinations are stale.
        let originalSection: MenuBarSection.Name

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// The number of times the item was not found on the active space.
        /// Tracked separately from ``rehideAttempts`` to allow more retries
        /// for the "item not found" case (the app may be on another space
        /// or temporarily invisible).
        var notFoundAttempts = 0

        /// The number of rehide checks that have found the interface
        /// ``InterfaceState/unknown``.
        ///
        /// Bounded by ``maxUndetectedInterfaceChecks`` so an item whose
        /// interface can never be identified still goes home rather than
        /// sitting in the visible section forever.
        var undetectedInterfaceChecks = 0

        /// How many `unknown` readings to sit through before rehiding anyway.
        ///
        /// The checks are three seconds apart, so this trades roughly the
        /// length of the ordinary rehide timer against tearing down a menu
        /// that is open but unidentifiable. An item that lingers too long is
        /// a far cheaper failure than a menu that closes underneath the user.
        static let maxUndetectedInterfaceChecks = 4

        /// Timestamp for when the item was first shown so we can honor
        /// a short grace period for menus that use nonstandard windows.
        private let firstShownDate = Date.now

        /// Minimum time to treat the item as "showing" even if we can't
        /// detect a popup window (helps apps with unusual window levels).
        private let graceInterval: TimeInterval = 2

        /// What is known about the item's interface.
        enum InterfaceState {
            /// A window belonging to the item was observed on screen.
            case showing

            /// The interface was identified and is no longer on screen, so it
            /// has been closed or dismissed. Positive evidence.
            case absent

            /// The interface was never identified: nothing was captured when
            /// the item was clicked and nothing can be found now.
            ///
            /// Distinct from ``absent`` because it is an admission of
            /// ignorance rather than an observation. Rehiding on it is a
            /// guess, and when the guess is wrong the user loses the menu
            /// they just opened (#924).
            case unknown
        }

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
            interfaceState == .showing
        }

        /// What is currently known about the item's interface.
        var interfaceState: InterfaceState {
            // First check the tracked popup window; this is the most
            // reliable signal when available.
            if let window = shownInterfaceWindow,
               let current = WindowInfo(windowID: window.windowID)
            {
                if current.layer == CGWindowLevelForKey(.popUpMenuWindow)
                    || current.layer == CGWindowLevelForKey(.popUpMenuWindow) - 1
                    || current.layer == CGWindowLevelForKey(.statusWindow)
                    || current.layer == CGWindowLevelForKey(.mainMenuWindow)
                {
                    return current.isOnScreen ? .showing : .absent
                }
                if let app = current.owningApplication {
                    // The captured window is the popup we just opened, so trust its
                    // on-screen state rather than requiring the app to be active in
                    // two cases the isActive check gets wrong:
                    //   - Menu-bar agent apps (.accessory) can never report active,
                    //     so their popover (e.g. BetterDisplay) would look hidden
                    //     the instant it opens.
                    //   - Some apps (e.g. Claude/Electron) place their menu at a
                    //     non-standard window level, and it is our programmatic
                    //     trigger, not the user, that opened it, so the app is
                    //     not frontmost. A menu-sized window distinguishes this
                    //     from an incidental small window.
                    if app.activationPolicy == .accessory
                        || current.bounds.height > MenuBarItemManager.maxMenuBarItemHeight
                    {
                        return current.isOnScreen ? .showing : .absent
                    }
                    return app.isActive && current.isOnScreen ? .showing : .absent
                }
                return current.isOnScreen ? .showing : .absent
            }

            // The tracked window is gone or was never captured. During the
            // grace period, assume the interface is still showing to give
            // apps with nonstandard windows time to create them.
            if Date.now.timeIntervalSince(firstShownDate) < graceInterval {
                return .showing
            }

            // Grace period expired and no tracked window. Check whether the
            // app has any visible popup or overlay window that we missed.
            //
            // A miss here is not evidence the menu closed — we never found it
            // in the first place — so it reports `unknown` and the caller
            // decides how long to keep looking.
            return appHasVisiblePopup() ? .showing : .unknown
        }

        /// Checks whether any process that could own this item's interface has
        /// a visible menu window on screen.
        ///
        /// See ``MenuBarItemManager/windowIsOpenInterface(ownerPID:layer:height:interfacePIDs:)``
        /// for what counts.
        private func appHasVisiblePopup() -> Bool {
            WindowInfo.createWindows(option: .onScreen).contains { window in
                MenuBarItemManager.windowIsOpenInterface(
                    ownerPID: window.ownerPID,
                    layer: window.layer,
                    height: window.bounds.height,
                    interfacePIDs: interfacePIDs
                )
            }
        }

        init(
            tag: MenuBarItemTag,
            sourcePID: pid_t,
            interfacePIDs: Set<pid_t>,
            displayID: CGDirectDisplayID,
            returnDestination: MoveDestination,
            fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?,
            originalSection: MenuBarSection.Name
        ) {
            self.tag = tag
            self.sourcePID = sourcePID
            self.interfacePIDs = interfacePIDs
            self.displayID = displayID
            self.returnDestination = returnDestination
            self.fallbackNeighbor = fallbackNeighbor
            self.originalSection = originalSection
        }
    }

    /// Whether an on-screen window counts as the interface a temporarily shown
    /// item opened.
    ///
    /// Matches the pop-up menu level (the level macOS uses for menus opened
    /// from menu bar items). Some apps (e.g. DisplayLink) instead draw their
    /// menu as a status- or main-menu-level window owned by the app rather
    /// than at pop-up level, so those levels are also matched, but only when
    /// the window is taller than a menu bar item, so the status item itself
    /// (which sits in the menu bar) is not mistaken for an open menu. A
    /// liberal "above normal" match was previously used as a catch-all, but
    /// it matched floating panels, modal levels, and other unrelated app
    /// windows, keeping the interface reading positive indefinitely and
    /// preventing rehide.
    ///
    /// `interfacePIDs` is a set rather than one PID because the process that
    /// owns the item's window and the one that owns the menu it opens are not
    /// always the same — see
    /// ``TemporarilyShownItemContext/interfacePIDs``.
    static nonisolated func windowIsOpenInterface(
        ownerPID: pid_t,
        layer: Int,
        height: CGFloat,
        interfacePIDs: Set<pid_t>
    ) -> Bool {
        guard interfacePIDs.contains(ownerPID) else {
            return false
        }
        let level = CGWindowLevel(Int32(layer))
        if level == CGWindowLevelForKey(.popUpMenuWindow)
            || level == CGWindowLevelForKey(.popUpMenuWindow) - 1
        {
            return true
        }
        // Menu bar items are at most ~menu-bar height; a real menu drawn
        // at status/main-menu level is taller, which distinguishes it.
        if level == CGWindowLevelForKey(.statusWindow) || level == CGWindowLevelForKey(.mainMenuWindow) {
            return height > maxMenuBarItemHeight
        }
        return false
    }

    /// The tallest a window can be and still be a menu bar item rather than
    /// something the item opened.
    static nonisolated let maxMenuBarItemHeight: CGFloat = 40

    /// Picks the window to track as the interface a temporarily shown item
    /// just opened, out of the windows that appeared around its click.
    ///
    /// Picking wrong is worse than picking nothing. A tracked window
    /// short-circuits ``TemporarilyShownItemContext/interfaceState``: the grace
    /// period and the `unknown` budget are both skipped, and the instant the
    /// tracked window goes away the reading is a confident `absent`. So
    /// latching onto an incidental window that lives for a moment — and
    /// Control Center, which is in `interfacePIDs` for every item it hosts,
    /// opens them around a click — hands the rehide the same false negative
    /// those two mechanisms exist to prevent, only sooner and with more
    /// conviction. The menu goes down inside a second (#924).
    ///
    /// A candidate therefore has to look like an interface: a menu-level
    /// window first, then any window too tall to be a status item, which is how
    /// ``TemporarilyShownItemContext/interfaceState`` recognizes the popovers
    /// and non-standard-level menus that never reach pop-up level. Nothing
    /// qualifying means nothing is tracked, which leaves the reading `unknown`
    /// and the menu alone.
    static nonisolated func interfaceWindowToTrack(
        among candidates: [WindowInfo],
        interfacePIDs: Set<pid_t>
    ) -> WindowInfo? {
        let owned = candidates.filter { interfacePIDs.contains($0.ownerPID) }
        let menu = owned.first { window in
            windowIsOpenInterface(
                ownerPID: window.ownerPID,
                layer: window.layer,
                height: window.bounds.height,
                interfacePIDs: interfacePIDs
            )
        }
        return menu ?? owned.first { $0.bounds.height > maxMenuBarItemHeight }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown, along with the tag and PID of the neighbor on the
    /// opposite side (if any) for fallback ordering.
    ///
    /// Only neighbors that share `section` are considered. An item from
    /// another section is not a usable anchor: moving next to it returns the
    /// item into *that* section, and once macOS persists the position the
    /// item stays there across relaunches. Items that can never be hidden are
    /// the common case — Control Center modules such as `AudioVideoModule`
    /// come and go as the mic or camera is used, and even with the items
    /// sorted into left-to-right order, the physically adjacent item can
    /// belong to another section.
    private func getReturnDestination(
        for item: MenuBarItem,
        in items: [MenuBarItem],
        section: MenuBarSection.Name
    ) -> (destination: MoveDestination, fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?)? {
        // The anchor math below treats index adjacency as physical
        // adjacency, but the item list arrives in Window Server order.
        // Sort by each item's leading edge so successor/predecessor mean
        // the item's actual on-screen neighbors.
        let orderedItems = items.sorted { $0.bounds.minX < $1.bounds.minX }

        guard let index = orderedItems.firstIndex(matching: item.tag) else {
            return nil
        }

        let eligibleIndices = Set(orderedItems.indices.filter { candidateIndex in
            let candidate = orderedItems[candidateIndex]
            guard candidate.canBeHidden else {
                return false
            }
            return itemCache.address(for: candidate.tag)?.section == section
        })

        let anchors = LayoutSolver.returnAnchors(
            forIndex: index,
            itemCount: orderedItems.count,
            eligibleIndices: eligibleIndices
        )

        // Prefer anchoring to the neighbor on the right. The fallback is the
        // nearest eligible neighbor on the opposite side.
        if let successor = anchors.successor {
            let fallback: (MenuBarItemTag, pid_t)? = anchors.predecessor.map { predecessor in
                let neighbor = orderedItems[predecessor]
                return (neighbor.tag, neighbor.sourcePID ?? neighbor.ownerPID)
            }
            return (.leftOfItem(orderedItems[successor]), fallback)
        }
        if let predecessor = anchors.predecessor {
            return (.rightOfItem(orderedItems[predecessor]), nil)
        }

        // The section holds no other item to anchor against, so aim at the
        // section itself. Ordering within the section is not preserved, but
        // the item lands in the correct section.
        return sectionDestination(for: section, in: items).map { ($0, nil) }
    }

    /// Gets the destination that returns an item to the given section's
    /// boundary, used when no neighbor is available to preserve ordering.
    private func sectionDestination(
        for section: MenuBarSection.Name,
        in items: [MenuBarItem]
    ) -> MoveDestination? {
        switch section {
        case .hidden:
            items.first(matching: .hiddenControlItem).map { .leftOfItem($0) }
        case .alwaysHidden:
            // If the always-hidden section was disabled, fall back to hidden.
            (items.first(matching: .alwaysHiddenControlItem) ?? items.first(matching: .hiddenControlItem))
                .map { .leftOfItem($0) }
        case .visible:
            // Should not happen (we don't temporarily show items that are
            // already visible), but handle it gracefully.
            nil
        }
    }

    /// Waits for a menu bar item's position to stabilize after a move.
    ///
    /// After a Cmd+drag move, the Window Server updates the item's window
    /// position, but the owning app may take additional time to process the
    /// change internally. If we click the item before it has settled, the
    /// app may position its popup at the old location.
    ///
    /// This method polls the item's bounds until two consecutive reads
    /// return the same value, up to a maximum wait time.
    private nonisolated func waitForItemPositionToSettle(item: MenuBarItem) async {
        let maxWait: Duration = .milliseconds(250)
        let pollInterval: Duration = .milliseconds(20)
        let startTime = ContinuousClock.now

        var previousBounds = Bridging.getWindowBounds(for: item.windowID)

        while ContinuousClock.now - startTime < maxWait {
            await eventSleep(for: pollInterval)
            let currentBounds = Bridging.getWindowBounds(for: item.windowID)
            if currentBounds == previousBounds, currentBounds != nil {
                return
            }
            previousBounds = currentBounds
        }
    }

    /// Waits until the item's Window Server origin differs from `previousOrigin`,
    /// or until `timeout` elapses.
    ///
    /// Used on the fast path of `temporarilyShow` as a lightweight alternative
    /// to `waitForItemPositionToSettle`: we only need to confirm the Window
    /// Server has applied the new position; we don't need two consecutive
    /// identical readings.
    private nonisolated func waitForItemToLeaveOrigin(
        item: MenuBarItem,
        previousOrigin: CGPoint,
        timeout: Duration
    ) async {
        let pollInterval = Duration.milliseconds(15)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            await eventSleep(for: pollInterval)
            if let currentOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin,
               currentOrigin != previousOrigin
            {
                return
            }
        }
    }

    /// How long to wait before looking again while a temporarily shown item's
    /// menu is still open, or while the user is still mid-interaction.
    ///
    /// The item sits in the visible section until a check passes, so this is
    /// also how long it lingers there after the user dismisses the menu. The
    /// check itself is cheap in the common case — a single window lookup — and
    /// the expensive full enumeration only runs for an item whose interface was
    /// never identified, which is spaced further apart by the `unknown` branch
    /// of ``rehideTemporarilyShownItems(force:isCalledFromTemporarilyShow:)``.
    private static let rehidePollInterval: TimeInterval = 1

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        let interval = interval ?? 15
        MenuBarItemManager.diagLog.debug("Running rehide timer for interval: \(interval)")
        rehideTimer?.invalidate()
        rehideCancellable?.cancel()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MenuBarItemManager.diagLog.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
        // Also rehide when frontmost app changes (smart-ish).
        //
        // `dropFirst` because the KVO publisher's default options include
        // `.initial`, so subscribing replays the app that is already frontmost.
        // Every call to this method re-subscribes — including the retry calls
        // from `rehideTemporarilyShownItems` — so that replay turned each
        // "look again in `interval` seconds" into "look again in 200 ms". The
        // intervals below were reasoned about as seconds and were really a
        // fifth of one: the four `unknown` checks that read as twelve seconds
        // of grace for a menu we cannot identify were spending eight hundred
        // milliseconds (#924). Only a real app switch belongs here.
        //
        // Debounce so rapid app switches (Cmd-Tab spam) collapse to one
        // rehide attempt instead of queuing a separate Task per change ;
        // each rehide call can do an expensive on-screen window enumeration.
        rehideCancellable = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.rehideTemporarilyShownItems()
                }
            }
    }

    /// The result of a ``temporarilyShow(item:clickingWith:on:fastPath:)`` call.
    enum TemporaryShowResult {
        /// The item was never moved; a precondition failed (missing state,
        /// no return destination, no anchor, or the move itself failed).
        /// The item is still hidden; do **not** attempt a fallback click.
        case showFailed
        /// The item was moved into the visible area **and** the synthetic
        /// click completed successfully.
        case movedAndClicked
        /// The item was moved into the visible area but the synthetic click
        /// failed. The icon is now visible; callers may attempt a fallback
        /// click using live bounds.
        case movedButClickFailed
    }

    /// Temporarily moves `item` into the visible area next to the Ice icon,
    /// clicks it, then schedules a rehide.
    ///
    /// The item is returned to its original location after approximately
    /// 15 seconds, though it may be sooner (e.g. when switching apps) or
    /// later due to the smart rehide logic.
    ///
    /// - Returns: A ``TemporaryShowResult`` describing whether the move and
    ///   click succeeded. Only act on ``TemporaryShowResult/movedButClickFailed``
    ///   for fallback clicks; the item is hidden for every other non-success case.
    @discardableResult
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton, on displayID: CGDirectDisplayID? = nil, fastPath: Bool = false) async -> TemporaryShowResult {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not showing \(item.logString)")
            return .showFailed
        }

        MenuBarItemManager.diagLog.debug("temporarilyShow: started for \(item.logString)")

        // Determine the displayID for this item.
        let resolvedDisplayID: CGDirectDisplayID
        if let displayID {
            resolvedDisplayID = displayID
        } else {
            let itemBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
            let screen = NSScreen.screens.first { $0.frame.intersects(itemBounds) }
            resolvedDisplayID = screen?.displayID ?? Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        // Determine the item's original section early so we can persist it
        // and use it as a fallback if the neighbor-based return destination
        // becomes stale by the time we rehide.
        let originalSection = itemCache.address(for: item.tag)?.section ?? .hidden
        let tagIdentifier = item.tag.tagIdentifier

        // Rehide any previously temporarily shown items before showing a new one.
        // This prevents stale contexts from accumulating when the user opens multiple
        // temporary items in quick succession.
        if !temporarilyShownItemContexts.isEmpty {
            rehideTimer?.invalidate()
            rehideCancellable?.cancel()
            await rehideTemporarilyShownItems(force: true, isCalledFromTemporarilyShow: true)

            // Only treat contexts with rehideAttempts > 0 as genuinely stuck
            // (move was attempted and failed). Contexts with rehideAttempts == 0
            // but notFoundAttempts > 0 are merely not visible on the active
            // space right now; they are transient and will retry fine.
            // Bailing on notFound items would leave them permanently stranded.
            let stuckItems = temporarilyShownItemContexts.filter {
                !$0.tag.matchesIgnoringWindowID(item.tag) && $0.rehideAttempts > 0
            }
            if !stuckItems.isEmpty {
                MenuBarItemManager.diagLog.error(
                    """
                    temporarilyShow: aborting; \(stuckItems.count) item(s) still stuck \
                    after force-rehide: \(stuckItems.map(\.tag)). \
                    Avoiding further semaphore saturation.
                    """
                )
                // Re-arm the rehide timer so stuck contexts are retried rather
                // than left stranded with no scheduled retry.
                runRehideTimer()
                return .showFailed
            }

            if temporarilyShownItemContexts.contains(where: { $0.tag.matchesIgnoringWindowID(item.tag) }) {
                // The item we want to show is already in the temporary list.
                // This can happen if the user clicks the same item twice very fast.
                // Remove the old context so we can create a fresh one with new bounds.
                removeTemporarilyShownItemFromCache(with: item.tag)
            }
        }

        // Fetch items specifically for the display where the item lives.
        let items = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .activeSpace)

        guard let returnInfo = getReturnDestination(for: item, in: items, section: originalSection) else {
            MenuBarItemManager.diagLog.error("No return destination for \(item.logString) on display \(resolvedDisplayID)")
            return .showFailed
        }

        // Prefer inserting to the left of the Thaw/visible control item so the icon appears
        // where users expect. If it's missing, fall back to the first non-control item.
        let visibleControl = items.first(matching: .visibleControlItem)
        let targetItem = visibleControl ?? items.first(where: { !$0.isControlItem && $0.canBeHidden }) ?? items.first

        // If we couldn't find any anchor, bail gracefully.
        guard let anchor = targetItem else {
            MenuBarItemManager.diagLog.warning("Not enough room or no anchor to show \(item.logString)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Not enough room to show \"\(item.displayName)\"")
            alert.runModal()
            return .showFailed
        }

        let moveDestination: MoveDestination = .leftOfItem(anchor)

        // Record the item's original section early so we can relocate it if its app
        // quits before we get a chance to rehide it (macOS persists the
        // physical position set by the Cmd+drag, so on relaunch the icon
        // would otherwise stay in the visible section).
        pendingRelocations[tagIdentifier] = sectionKey(for: originalSection)

        // Also store the return destination to preserve ordering
        let neighborTag = returnInfo.destination.targetItem.tag
        let position = switch returnInfo.destination {
        case .leftOfItem: "left"
        case .rightOfItem: "right"
        }
        pendingReturnDestinations[tagIdentifier] = [
            "neighbor": neighborTag.tagIdentifier,
            "position": position,
        ]
        persistPendingRelocations()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        MenuBarItemManager.diagLog.debug("Temporarily showing \(item.logString) on display \(resolvedDisplayID)")

        // Capture the item's origin before the move so the fast-path settle
        // can detect when the Window Server has applied the new position.
        let preMoveOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin

        do {
            if fastPath {
                // Two-attempt move on the fast path. The first attempt almost always
                // repositions the item correctly; the second is a cheap safety net for
                // the rare case where the event cycle is dropped under CPU load.
                // Keeping retries at 2 (vs. the default 8) avoids the visible jitter
                // from a long retry loop while still tolerating one bad cycle.
                try await move(item: item, to: moveDestination, on: resolvedDisplayID, skipInputPause: true, maxMoveAttempts: 2)
            } else {
                try await move(item: item, to: moveDestination, on: resolvedDisplayID, skipInputPause: true)
            }
        } catch {
            MenuBarItemManager.diagLog.error("Error showing item: \(error)")

            // Determine whether the item physically left its original position
            // despite move() throwing. itemCache is a pre-move snapshot and is
            // not updated during a move() call, so itemCache.address(for:) would
            // always return originalSection here; giving a false negative.
            // Instead, compare live Window Server bounds against the origin
            // captured before the move started. Any nil (window gone or
            // pre-move capture missed) is treated as moved/unknown; preserving
            // rehide metadata is the safe-side choice.
            let currentOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin
            // Treat any nil as "moved/unknown"; preserving rehide metadata is
            // the safe-side choice when the move outcome cannot be determined.
            // Note: in Swift nil != nil evaluates to false, so without the nil
            // guards both-nil would wrongly indicate "item never moved."
            let itemHasMoved = currentOrigin == nil || preMoveOrigin == nil || currentOrigin != preMoveOrigin

            if itemHasMoved {
                // The item is no longer where it started; keep the rehide
                // metadata so the persistent-relocation path can restore it
                // when the app relaunches or the rehide timer fires.
                MenuBarItemManager.diagLog.warning("move() threw but item \(item.logString) is no longer in \(originalSection); preserving pending rehide metadata")
                // pendingRelocations already set above; re-assert return destination
                // in case it was not yet written (guard-exit paths above this block).
                pendingReturnDestinations[tagIdentifier] = [
                    "neighbor": neighborTag.tagIdentifier,
                    "position": position,
                ]
                persistPendingRelocations()
            } else {
                // Item never moved; safe to discard the speculative metadata.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                persistPendingRelocations()
            }

            return .showFailed
        }

        let context = TemporarilyShownItemContext(
            tag: item.tag,
            sourcePID: item.sourcePID ?? item.ownerPID,
            interfacePIDs: Set([item.ownerPID, item.sourcePID].compactMap(\.self)),
            displayID: resolvedDisplayID,
            returnDestination: returnInfo.destination,
            fallbackNeighbor: returnInfo.fallbackNeighbor,
            originalSection: originalSection
        )
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            // A poll, not the fifteen-second ceiling. Nothing else re-arms a
            // check until the frontmost app changes, and dismissing a menu with
            // Escape changes nothing, so scheduling the ceiling here would park
            // the item in the visible section for fifteen seconds every time
            // the user closed its menu without picking anything. Each check
            // reschedules itself, so the ceiling still arrives on time for an
            // item that opened nothing at all.
            runRehideTimer(for: Self.rehidePollInterval)
        }

        let clickItem: MenuBarItem
        if fastPath {
            // Fast path: lightweight settle (max 150 ms, 15 ms poll) so the
            // click target coordinates are live rather than the pre-move bounds.
            // This is shorter than the full waitForItemPositionToSettle (250 ms)
            // to keep the IceBar click feel snappy.
            if let preMoveOrigin {
                await waitForItemToLeaveOrigin(item: item, previousOrigin: preMoveOrigin, timeout: .milliseconds(150))
            }

            // Re-fetch the item so getCurrentBounds inside postClickEvents
            // uses a fresh window reference rather than the stale pre-move struct.
            let refreshedItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
            clickItem = refreshedItems.first(where: { $0.windowID == item.windowID }) ??
                refreshedItems.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        ($0.sourcePID ?? $0.ownerPID) == (item.sourcePID ?? item.ownerPID)
                }) ?? item
        } else {
            // Wait for the item's position to stabilize after the move. Some
            // apps need time to process the window relocation before they can
            // correctly position their popup in response to a click.
            await waitForItemPositionToSettle(item: item)

            // Re-fetch the item from the live window list specifically for this display.
            // Prefer an exact windowID match, then fall back to namespace+title with PID matching.
            let refreshedItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
            clickItem = refreshedItems.first(where: { $0.windowID == item.windowID }) ??
                refreshedItems.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        ($0.sourcePID ?? $0.ownerPID) == (item.sourcePID ?? item.ownerPID)
                }) ?? item

            // Give the owning app a little extra time to finish processing the
            // move internally. Some apps (e.g. OneDrive) need more than just a
            // stable window position before they can respond to clicks.
            await eventSleep(for: .milliseconds(25))
        }

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        // Electron/Chromium tray items ignore the synthetic click, so open their
        // menu via an Accessibility press once revealed, mirroring the on-screen
        // path. Other apps (and right-clicks) use the synthetic click below. The
        // popup window capture that follows is unaffected by which path opened it.
        // The window the click opened, when the click path we took already
        // watched for it. Saves repeating the scan below.
        var observedInterfaceWindowID: CGWindowID?

        if mouseButton == .left, isElectronItem(clickItem), pressItemViaAccessibility(clickItem) {
            MenuBarItemManager.diagLog.info("Activated \(clickItem.logString) via AX press")
        } else {
            do {
                // Single attempt: the item is already at a known-good position with
                // fresh bounds. If it fails, fall through to the fallback path below
                // rather than spending 3× the semaphore timeout here.
                let reaction = try await click(item: clickItem, with: mouseButton, skipInputPause: true, maxAttempts: 1)
                observedInterfaceWindowID = reaction.openedWindowID
            } catch {
                MenuBarItemManager.diagLog.error("Error clicking item (first attempt): \(error); attempting fallback click")

                // Fallback: re-fetch the item from the live window list so the
                // click targets a fresh MenuBarItem with current windowID and
                // bounds, rather than the potentially stale pre-click struct.
                let fallbackItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
                let fallbackItem = fallbackItems.first(where: { $0.windowID == clickItem.windowID }) ??
                    fallbackItems.first(where: {
                        $0.tag.matchesIgnoringWindowID(clickItem.tag) &&
                            ($0.sourcePID ?? $0.ownerPID) == (clickItem.sourcePID ?? clickItem.ownerPID)
                    }) ?? clickItem

                // We stay inside temporarilyShow so that idsBeforeClick and context
                // remain in scope; shownInterfaceWindow can still be captured if
                // the fallback succeeds, keeping isShowingInterface accurate for
                // the rehide logic.
                do {
                    let reaction = try await click(item: fallbackItem, with: mouseButton, skipInputPause: true)
                    observedInterfaceWindowID = reaction.openedWindowID
                } catch {
                    MenuBarItemManager.diagLog.error("Fallback click also failed for \(item.logString): \(error)")
                    // Icon is visible but both click attempts failed.
                    return .movedButClickFailed
                }
            }
        }

        // Capture the popup window opened by whichever click path succeeded.
        // The synthetic-click paths already waited for it and told us which
        // one it was; only the AX press path, which posts nothing and so has
        // nothing to verify, still has to look for itself.
        let interfaceCandidates: [WindowInfo]
        if let observedInterfaceWindowID, let observed = WindowInfo(windowID: observedInterfaceWindowID) {
            interfaceCandidates = [observed]
        } else {
            await eventSleep(for: .milliseconds(100))
            interfaceCandidates = WindowInfo.createWindows(option: .onScreen)
                .filter { !idsBeforeClick.contains($0.windowID) }
        }

        // Either PID counts, for the reason ``interfacePIDs`` documents: the
        // item's window and the menu it opens can belong to different
        // processes, and the item's own owner is Control Center's for every
        // item it hosts.
        //
        // What the click path saw goes through the same test as what a scan
        // finds. ``ClickReactionVerifier`` is answering a different question —
        // did the owner react at all — and settles for any new window of the
        // owner's when no menu-level one appeared, which is sound evidence of a
        // reaction and a poor guess at the menu.
        context.shownInterfaceWindow = MenuBarItemManager.interfaceWindowToTrack(
            among: interfaceCandidates,
            interfacePIDs: context.interfacePIDs
        )

        return .movedAndClicked
    }

    /// Resolves the best move destination for returning a temporarily shown
    /// item to its original section.
    ///
    /// Tries destinations in order of preference:
    /// 1. The captured ``TemporarilyShownItemContext/returnDestination``
    ///    (primary neighbor, refreshed with current bounds).
    /// 2. The ``TemporarilyShownItemContext/fallbackNeighbor`` (the
    ///    neighbor on the opposite side, to preserve relative ordering).
    /// 3. The control item for the item's original section (guarantees
    ///    the item ends up in the correct section, though ordering within
    ///    the section may differ).
    private func resolveReturnDestination(
        for context: TemporarilyShownItemContext,
        in items: [MenuBarItem]
    ) -> MoveDestination? {
        // 1. Try the primary neighbor-based destination.
        //    Re-wrap with the fresh item so the move uses current bounds.
        let targetTag = context.returnDestination.targetItem.tag
        let targetPID = context.returnDestination.targetItem.sourcePID ?? context.returnDestination.targetItem.ownerPID
        if let freshTarget = items.first(where: {
            $0.tag.matchesIgnoringWindowID(targetTag) &&
                ($0.sourcePID ?? $0.ownerPID) == targetPID
        }) {
            switch context.returnDestination {
            case .leftOfItem:
                return .leftOfItem(freshTarget)
            case .rightOfItem:
                return .rightOfItem(freshTarget)
            }
        }

        // 2. Try the fallback neighbor (opposite side).
        if let fallbackNeighbor = context.fallbackNeighbor,
           let freshFallback = items.first(where: {
               $0.tag.matchesIgnoringWindowID(fallbackNeighbor.tag) &&
                   ($0.sourcePID ?? $0.ownerPID) == fallbackNeighbor.pid
           })
        {
            switch context.returnDestination {
            case .leftOfItem:
                return .rightOfItem(freshFallback)
            case .rightOfItem:
                return .leftOfItem(freshFallback)
            }
        }

        // 3. Fallback: use the control item for the original section.
        MenuBarItemManager.diagLog.debug(
            """
            Return destination neighbors not found for \(context.tag); \
            falling back to section-level destination for \(context.originalSection.logString)
            """
        )
        guard let destination = sectionDestination(for: context.originalSection, in: items) else {
            MenuBarItemManager.diagLog.error(
                """
                No section destination to resolve return destination for \
                \(context.tag) in \(context.originalSection.logString)
                """
            )
            return nil
        }
        return destination
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items, unless `force`
    /// is `true`, in which case all items are rehidden immediately.
    ///
    /// - Parameter force: If `true`, skip the interface-showing and
    ///   user-input guards and rehide all items immediately.
    func rehideTemporarilyShownItems(force: Bool = false, isCalledFromTemporarilyShow: Bool = false) async {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }

        MenuBarItemManager.diagLog.debug("rehideTemporarilyShownItems: started (force=\(force), isCalledFromTemporarilyShow=\(isCalledFromTemporarilyShow))")

        if !force {
            // interfaceState is computed, and its terminal case enumerates
            // every on-screen window; on a 1-second poll, evaluate it once
            // per context per check and answer both questions from that.
            let interfaceStates = temporarilyShownItemContexts.map {
                ($0, $0.interfaceState)
            }
            guard !interfaceStates.contains(where: { $0.1 == .showing }) else {
                MenuBarItemManager.diagLog.debug("Menu bar item interface is shown, so waiting to rehide")
                runRehideTimer(for: Self.rehidePollInterval)
                return
            }

            // No context reports a showing interface, but some may report that
            // they never identified one. Rehiding on that is a guess, and the
            // cost of guessing wrong is the user's open menu being dragged off
            // the bar (#924). Spend a bounded number of further checks looking
            // before treating it as closed.
            let undetected = interfaceStates.filter { $0.1 == .unknown }.map(\.0)
            let stillWorthChecking = undetected.filter {
                $0.undetectedInterfaceChecks < TemporarilyShownItemContext.maxUndetectedInterfaceChecks
            }
            if !stillWorthChecking.isEmpty {
                for context in stillWorthChecking {
                    context.undetectedInterfaceChecks += 1
                }
                MenuBarItemManager.diagLog.debug(
                    "Interface never identified for \(stillWorthChecking.count) temporarily shown item(s); waiting to rehide rather than assuming it closed"
                )
                runRehideTimer(for: 3)
                return
            }
            if !undetected.isEmpty {
                MenuBarItemManager.diagLog.info(
                    "Interface still unidentified for \(undetected.count) temporarily shown item(s) after \(TemporarilyShownItemContext.maxUndetectedInterfaceChecks) checks; rehiding anyway"
                )
            }
            guard hasUserPausedInput(for: .milliseconds(250)) else {
                MenuBarItemManager.diagLog.debug("Found recent user input, so waiting to rehide")
                runRehideTimer(for: Self.rehidePollInterval)
                return
            }
        }

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // Use a shorter settle time when called from temporarilyShow; the user
        // is actively waiting for the next click. The eventSemaphore and
        // waitForMoveOperationBuffer in move() provide adequate race protection.
        await eventSleep(for: isCalledFromTemporarilyShow ? .milliseconds(50) : .milliseconds(250))

        MenuBarItemManager.diagLog.debug("Rehiding temporarily shown items")

        // Use the same 30 s watchdog as the bulk-apply path so the 1 s
        // default cursor-watchdog cannot force-show the cursor mid-batch
        // (#899). Without this, a rehide that takes longer than 1 s
        // (eventSleep + moves) lets the watchdog fire, flash the cursor,
        // and reset hideCount to 0 — observed as cursor flicker.
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer {
            MouseHelpers.showCursor()
        }

        // Suppress per-item cursor hide/show inside the move loop so the
        // outer pair owns visibility for the whole batch. Without this,
        // each move() does its own hide/show and the cursor oscillates
        // per item — observed as flicker during rehide.
        let wasBulkApplyInProgress = isBulkApplyInProgress
        isBulkApplyInProgress = true
        defer {
            isBulkApplyInProgress = wasBulkApplyInProgress
        }

        while let context = currentContexts.popLast() {
            guard let item = items.first(where: {
                $0.tag.matchesIgnoringWindowID(context.tag) &&
                    ($0.sourcePID ?? $0.ownerPID) == context.sourcePID
            }) else {
                context.notFoundAttempts += 1
                MenuBarItemManager.diagLog.debug(
                    """
                    Missing temporarily shown item \(context.tag) on active space \
                    (not-found attempt \(context.notFoundAttempts)); will retry
                    """
                )
                // Keep the context for retry; the item may be on another
                // space or the app may have briefly hidden it. After enough
                // attempts, drop the in-memory context and rely on the
                // persisted pendingRelocations entry to recover on the next
                // cache cycle (relocatePendingItems).
                if context.notFoundAttempts < 10 {
                    failedContexts.append(context)
                } else {
                    MenuBarItemManager.diagLog.warning(
                        """
                        Giving up in-memory retry for \(context.tag) after \
                        \(context.notFoundAttempts) not-found attempts; \
                        pendingRelocations will handle recovery
                        """
                    )
                }
                continue
            }

            // Resolve the best return destination using fresh items.
            guard let destination = resolveReturnDestination(for: context, in: items) else {
                MenuBarItemManager.diagLog.error(
                    """
                    Could not resolve return destination for \(item.logString); \
                    item will remain in visible section until next cache cycle handles pendingRelocations
                    """
                )
                // Don't remove pendingRelocations; let relocatePendingItems handle it.
                continue
            }

            do {
                try await move(item: item, to: destination, on: context.displayID, skipInputPause: true)
                // Successfully rehidden; remove the pending relocation entry.
                let tagIdentifier = context.tag.tagIdentifier
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            } catch {
                context.rehideAttempts += 1
                MenuBarItemManager.diagLog.warning(
                    """
                    Attempt \(context.rehideAttempts) to rehide \
                    \(item.logString) failed with error: \
                    \(error)
                    """
                )
                // Maximum total attempts across all timer rounds.
                // 3 per-call attempts × 3 timer rounds = 9. Beyond this the
                // item is permanently stuck (dead PID, broken EventTap, etc.)
                // and retrying only keeps the event semaphore saturated.
                let maxTotalRehideAttempts = 9
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again immediately.
                } else if context.rehideAttempts < maxTotalRehideAttempts {
                    // Per-call cap reached; schedule a longer-delay retry.
                    failedContexts.append(context)
                } else {
                    // Total cap reached; drop this context from same-session retries.
                    // Overwrite the pendingRelocations entry with a waitForRelaunch
                    // sentinel so relocatePendingItems() skips move() this session.
                    // The sentinel encodes the current windowID; when the app
                    // relaunches its status item gets a new windowID, clearing the
                    // suppression automatically.
                    let tagIdentifier = context.tag.tagIdentifier
                    pendingRelocations[tagIdentifier] = waitForRelaunchValue(
                        windowID: item.windowID,
                        section: context.originalSection
                    )
                    persistPendingRelocations()
                    MenuBarItemManager.diagLog.error(
                        """
                        Giving up rehide for \(item.logString) after \
                        \(context.rehideAttempts) total attempts; \
                        marked waitForRelaunch; relocatePendingItems will \
                        retry only after app relaunch (new windowID)
                        """
                    )
                }
            }
        }

        persistPendingRelocations()

        // If force-hiding, we don't want to re-queue them for long delays.
        // We want them back in the section immediately or kept in context.
        if failedContexts.isEmpty {
            MenuBarItemManager.diagLog.debug("All items were successfully rehidden")
        } else {
            MenuBarItemManager.diagLog.error(
                """
                Some items failed to rehide; keeping in context for retry: \
                \(failedContexts.map(\.tag))
                """
            )
            temporarilyShownItemContexts.append(contentsOf: failedContexts.reversed())
            if !force {
                runRehideTimer(for: 3)
            }
        }
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(with tag: MenuBarItemTag) {
        while let index = temporarilyShownItemContexts.firstIndex(where: { $0.tag.matchesIgnoringWindowID(tag) }) {
            MenuBarItemManager.diagLog.debug(
                """
                Removing temporarily shown item from cache: \
                \(tag)
                """
            )
            temporarilyShownItemContexts.remove(at: index)
        }
        // Also clear any pending relocation since the user explicitly
        // placed the item in a new position.
        let tagIdentifier = tag.tagIdentifier
        if pendingRelocations.removeValue(forKey: tagIdentifier) != nil {
            pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            persistPendingRelocations()
        }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Relocates any newly appearing items that macOS placed to the left
    /// of our control items back into the visible section.
    ///
    /// Returns true if a relocation was performed.
    private func relocateNewLeftmostItems(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair,
        previousWindowIDs: [CGWindowID],
        recentWindowIDs: Set<CGWindowID>
    ) async -> Bool {
        guard appState != nil else { return false }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "relocateNewLeftmostItems: skipping for provisional AX-frame correlation"
            )
            return false
        }

        if suppressNextNewLeftmostItemRelocation {
            // Seed known identifiers so these baseline items won't be treated as "new"
            // on subsequent cache passes, then clear the suppression flag.
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()
            suppressNextNewLeftmostItemRelocation = false
            return false
        }

        // During startup settling, the first cache pass may have items tagged
        // with wrong namespaces (e.g. com.apple.controlcenter when sourcePID
        // hasn't resolved yet). Using those wrong tags to build hiddenTags /
        // alwaysHiddenTags causes ALL items to appear as "new" on the next
        // pass with correct sourcePIDs, triggering a destructive relocation
        // cascade that moves every hidden/always-hidden item to visible.
        // Seed identifiers and skip relocation; the settling-end restore pass
        // will handle correct placement.
        if isInStartupSettling {
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()

            // The Thaw icon is exempt from the deferral above. macOS can
            // restore our two control items in the wrong relative order,
            // parking the visible one left of the hidden divider — i.e.
            // off screen. Waiting for the settling-end pass to correct that
            // leaves the menu bar with no Thaw icon for as long as settling
            // runs, which is ~8 s when Control Center is slow to hand out
            // source PIDs, and reads as the app having crashed (#881).
            //
            // Safe to act on early because it turns only on geometry and our
            // own control item's tag; it is the namespace tags of *other*
            // items that aren't trustworthy yet.
            if let thawIcon = LayoutSolver.planThawIconMove(
                items: items,
                hiddenBounds: bestBounds(for: controlItems.hidden)
            ) {
                return await relocateThawIcon(thawIcon, controlItems: controlItems)
            }
            return false
        }

        // Cached hidden / always-hidden tags from the prior cache cycle.
        // The planner uses these to short-circuit re-relocating items
        // already placed in a hidden section.
        let hiddenTags = Set(itemCache[.hidden].map(\.tag))
        let alwaysHiddenTags = Set(itemCache[.alwaysHidden].map(\.tag))

        // Pre-compute live state for the planner. hiddenBounds and the
        // section classification both require the live Window Server;
        // computing them here keeps planLeftmostMove pure over its inputs.
        let hiddenBounds = bestBounds(for: controlItems.hidden)
        var sectionContext = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        var sectionByWindowID = [CGWindowID: MenuBarSection.Name]()
        for item in items {
            if let section = sectionContext.findSection(for: item) {
                sectionByWindowID[item.windowID] = section
            }
        }

        let decision = LayoutSolver.planLeftmostMove(
            items: items,
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: sectionByWindowID,
                previousWindowIDs: previousWindowIDs,
                recentWindowIDs: recentWindowIDs
            ),
            savedSectionOrder: savedSectionOrder,
            knownItemIdentifiers: knownItemIdentifiers,
            hiddenTags: hiddenTags,
            alwaysHiddenTags: alwaysHiddenTags,
            effectiveNewItemsSection: effectiveNewItemsSection
        )

        switch decision {
        case let .thawIcon(thawIcon):
            return await relocateThawIcon(thawIcon, controlItems: controlItems)

        case let .systemItem(systemItem):
            MenuBarItemManager.diagLog.info("Relocating non-hideable system item \(systemItem.logString) to visible section")
            do {
                try await move(
                    item: systemItem,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate system item \(systemItem.logString): \(error)")
                return false
            }
            return true

        case let .newHideableItem(candidate, identifierToMark):
            // Track this item so future cache cycles don't treat it as new.
            knownItemIdentifiers.insert(identifierToMark)
            persistKnownItemIdentifiers()

            let destination = newItemsMoveDestination(for: controlItems, among: items)

            MenuBarItemManager.diagLog.info(
                "Relocating new item \(candidate.logString) to \(effectiveNewItemsSection.logString)"
            )

            // Skip items with no valid bounds (transient clone windows
            // etc.). This live check stays in the orchestrator because
            // it requires Bridging.
            guard Bridging.getWindowBounds(for: candidate.windowID) != nil else {
                MenuBarItemManager.diagLog.warning("Skipping relocation for \(candidate.logString); no valid bounds, likely transient")
                return false
            }

            do {
                try await move(
                    item: candidate,
                    to: destination,
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate \(candidate.logString): \(error)")
                return false
            }
            return true

        case let .noop(reason):
            switch reason {
            case .unresolvedSourcePID:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: skipping, hideable items have unresolved sourcePIDs"
                )
            case .alreadyInTarget:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: candidate already in \(effectiveNewItemsSection.logString), skipping"
                )
            case .noNewCandidate, .noLeftmostItems:
                break
            }
            return false
        }
    }

    /// Moves the Thaw icon back to the right of the hidden divider, where it
    /// is on screen. Shared by the startup-settling path and the regular
    /// planner path, which reach the same decision from different inputs.
    private func relocateThawIcon(
        _ thawIcon: MenuBarItem,
        controlItems: ControlItemPair
    ) async -> Bool {
        MenuBarItemManager.diagLog.info("Relocating Thaw icon \(thawIcon.logString) to visible section")
        do {
            try await move(
                item: thawIcon,
                to: .rightOfItem(controlItems.hidden),
                skipInputPause: true
            )
        } catch {
            MenuBarItemManager.diagLog.error("Failed to relocate Thaw icon \(thawIcon.logString): \(error)")
            return false
        }
        return true
    }

    /// Relocates items whose apps quit while they were temporarily shown
    /// in the visible section back to their original section.
    ///
    /// When `temporarilyShow` moves an item to the visible section, macOS
    /// persists that position. If the app quits before rehide can move it
    /// back, the icon will reappear in the visible section on relaunch.
    /// This method checks for such items and moves them back.
    ///
    /// Returns `true` if any items were relocated.
    private func relocatePendingItems(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair
    ) async -> Bool {
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "relocatePendingItems: skipping for provisional AX-frame correlation"
            )
            return false
        }

        guard !pendingRelocations.isEmpty else {
            return false
        }

        // Don't interfere with items that are currently temporarily shown ;
        // those are handled by the normal rehide flow.
        let activelyShownTags = Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))

        let hiddenBounds = bestBounds(for: controlItems.hidden)

        // Pre-compute live per-item bounds for the planner's "already in
        // hidden section" comparison. Done here so the planner stays pure
        // over its inputs (no Bridging calls inside).
        var boundsForWindowID = [CGWindowID: CGRect]()
        for item in items {
            boundsForWindowID[item.windowID] = bestBounds(for: item)
        }

        // Extract fallback neighbor tags from temporarilyShownItemContexts.
        // The planner only needs the tag-identifier → neighbor mapping;
        // exposing the full context type to the planner would tangle its
        // signature with private state.
        var fallbackNeighborByTagIdentifier = [String: MenuBarItemTag]()
        for context in temporarilyShownItemContexts {
            if let neighbor = context.fallbackNeighbor?.tag {
                fallbackNeighborByTagIdentifier[context.tag.tagIdentifier] = neighbor
            }
        }

        var didRelocate = false

        // Iterate a snapshot of the dict keys so promotions of waitForRelaunch
        // sentinels mid-loop don't disturb iteration. The planner is called
        // per entry; the orchestrator handles persistence and re-runs after
        // a promotion so the regular section path executes.
        let allTagIdentifiers = Array(pendingRelocations.keys)
        for tagIdentifier in allTagIdentifiers {
            guard let rawSectionString = pendingRelocations[tagIdentifier] else { continue }

            // Parse the raw string into a typed PendingEntry for the planner.
            let entry: PendingLedger.PendingEntry
            if let sentinel = parseWaitForRelaunch(rawSectionString) {
                entry = PendingLedger.PendingEntry(
                    tagIdentifier: tagIdentifier,
                    kind: .waitForRelaunch(windowID: sentinel.windowID, section: sentinel.section)
                )
            } else if let parsedSection = sectionName(for: rawSectionString) {
                entry = PendingLedger.PendingEntry(tagIdentifier: tagIdentifier, kind: .section(parsedSection))
            } else {
                // Malformed entry; drop it.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                continue
            }

            var decision = PendingLedger.planPendingMove(
                entry: entry,
                items: items,
                controlItems: controlItems,
                hiddenBounds: hiddenBounds,
                boundsForWindowID: boundsForWindowID,
                activelyShownTags: activelyShownTags,
                returnInfo: PendingLedger.PendingReturnInfo(
                    destinations: pendingReturnDestinations,
                    fallbackNeighbors: fallbackNeighborByTagIdentifier
                )
            )

            // Handle a sentinel promotion in-place: rewrite pendingRelocations
            // to the regular section key, persist, then re-run the planner
            // for the same entry so the regular section path executes.
            if case let .promoteWaitForRelaunch(promotedSection) = decision {
                if let item = items.first(where: { entry.tagIdentifier == $0.tag.tagIdentifier }) {
                    MenuBarItemManager.diagLog.info(
                        "relocatePendingItems: \(item.logString) has new windowID; clearing waitForRelaunch sentinel"
                    )
                }
                pendingRelocations[tagIdentifier] = sectionKey(for: promotedSection)
                persistPendingRelocations()

                let promotedEntry = PendingLedger.PendingEntry(tagIdentifier: tagIdentifier, kind: .section(promotedSection))
                decision = PendingLedger.planPendingMove(
                    entry: promotedEntry,
                    items: items,
                    controlItems: controlItems,
                    hiddenBounds: hiddenBounds,
                    boundsForWindowID: boundsForWindowID,
                    activelyShownTags: activelyShownTags,
                    returnInfo: PendingLedger.PendingReturnInfo(
                        destinations: pendingReturnDestinations,
                        fallbackNeighbors: fallbackNeighborByTagIdentifier
                    )
                )
            }

            switch decision {
            case let .move(item, destination):
                let targetSection: MenuBarSection.Name = {
                    if case let .section(section) = entry.kind {
                        return section
                    }
                    if case let .waitForRelaunch(_, section) = entry.kind {
                        return section
                    }
                    return .hidden
                }()
                MenuBarItemManager.diagLog.info(
                    """
                    Relocating \(item.logString) back to \
                    \(targetSection.logString) after app relaunch
                    """
                )
                do {
                    try await move(item: item, to: destination, skipInputPause: true)
                    pendingRelocations.removeValue(forKey: tagIdentifier)
                    pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                    didRelocate = true
                } catch {
                    MenuBarItemManager.diagLog.error(
                        """
                        Failed to relocate \(item.logString) back to \
                        \(targetSection.logString): \(error)
                        """
                    )
                }

            case .clearEntry:
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)

            case .promoteWaitForRelaunch:
                // Unreachable: handled above by re-running the planner with
                // the promoted entry. If the planner returns promote a
                // second time we just leave the entry alone for next pass.
                break

            case let .skip(reason):
                switch reason {
                case .waitForRelaunchActive:
                    if let item = items.first(where: { entry.tagIdentifier == $0.tag.tagIdentifier }) {
                        MenuBarItemManager.diagLog.debug(
                            "relocatePendingItems: skipping \(item.logString); waitForRelaunch sentinel active (same windowID)"
                        )
                    }
                case .activelyShown, .itemNotPresent:
                    break
                }
            }
        }

        persistPendingRelocations()
        return didRelocate
    }

    /// Returns the best-known bounds for a menu bar item.
    private func bestBounds(for item: MenuBarItem) -> CGRect {
        Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
    }

    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    private func enforceControlItemOrder(controlItems: ControlItemPair) async {
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "Skipping control item order enforcement for provisional AX-frame correlation"
            )
            return
        }

        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            hidden.bounds.maxX <= alwaysHidden.bounds.minX
        else {
            return
        }

        do {
            MenuBarItemManager.diagLog.debug("Control items have incorrect order")
            try await move(item: alwaysHidden, to: .leftOfItem(hidden), skipInputPause: true)
        } catch {
            MenuBarItemManager.diagLog.error("Error enforcing control item order: \(error)")
        }
    }

    /// Returns a Boolean value that indicates whether any menu bar item
    /// currently has a menu open.
    func isAnyMenuBarItemMenuOpen() async -> Bool {
        let cacheFreshness: Duration = .milliseconds(250)

        if let cachedAt = menuOpenCheckCachedAt,
           cachedAt.duration(to: .now) <= cacheFreshness,
           let cachedResult = menuOpenCheckCachedResult
        {
            MenuBarItemManager.diagLog.debug("Menu open check: using cached result \(cachedResult)")
            return cachedResult
        }

        if let existingTask = menuOpenCheckTask {
            MenuBarItemManager.diagLog.debug("Menu open check: joining in-flight probe")
            return await applyMenuWindowPersistenceFilter(to: existingTask.value)
        }

        let cachedItems = itemCache.managedItems.filter(\.isOnScreen)
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description

        let task = Task.detached(priority: .utility) { () -> [MenuWindowCandidate] in
            // Get all on-screen windows.
            let windows = WindowInfo.createWindows(option: .onScreen)
            let potentialMenuWindows = windows.filter { window in
                guard window.isMenuRelated, window.title?.isEmpty ?? true else {
                    return false
                }
                guard window.owningApplication?.bundleIdentifier != controlCenterBundleID else {
                    MenuBarItemManager.diagLog.debug(
                        "Skipping Control Center window: PID \(window.ownerPID), title: \(window.title ?? "nil")"
                    )
                    return false
                }
                return true
            }

            guard !potentialMenuWindows.isEmpty else {
                MenuBarItemManager.diagLog.debug(
                    "Menu open check: no candidate menu windows on screen"
                )
                return []
            }

            let fastPathPIDs = Set(cachedItems.compactMap { item -> pid_t? in
                if let sourcePID = item.sourcePID {
                    return sourcePID
                }
                guard item.owningApplication?.bundleIdentifier != controlCenterBundleID else {
                    return nil
                }
                return item.ownerPID
            })

            MenuBarItemManager.diagLog.debug(
                """
                Checking for open menus - fast path with \(cachedItems.count) cached menu bar items, \
                \(fastPathPIDs.count) candidate PIDs, \(potentialMenuWindows.count) candidate menu windows
                """
            )

            let fastPathMatches = potentialMenuWindows.filter { window in
                let isMenuOpen = fastPathPIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on fast path: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated), bounds: \(NSStringFromRect(window.bounds))
                        """
                    )
                }
                return isMenuOpen
            }

            if !fastPathMatches.isEmpty {
                MenuBarItemManager.diagLog.debug("Menu open check: \(fastPathMatches.count) candidate windows (fast path)")
                return fastPathMatches.map { MenuWindowCandidate(windowID: $0.windowID, bounds: $0.bounds) }
            }

            let unresolvedWindows = WindowInfo.createWindows(
                from: cachedItems.compactMap { item in
                    guard item.sourcePID == nil, !item.isControlItem else {
                        return nil
                    }
                    guard item.owningApplication?.bundleIdentifier == controlCenterBundleID else {
                        return nil
                    }
                    return item.windowID
                }
            )

            guard !unresolvedWindows.isEmpty else {
                MenuBarItemManager.diagLog.debug("Menu open check: no candidate windows (fast path)")
                return []
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check: precise fallback resolving \(unresolvedWindows.count) unresolved window source PIDs"
            )

            let resolvedPIDs = await MenuBarItemManager.resolveAllSourcePIDs(for: unresolvedWindows)

            let precisePIDs = fastPathPIDs.union(resolvedPIDs)
            let preciseMatches = potentialMenuWindows.filter { window in
                let isMenuOpen = precisePIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on precise fallback: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated), bounds: \(NSStringFromRect(window.bounds))
                        """
                    )
                }
                return isMenuOpen
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check: \(preciseMatches.count) candidate windows (precise fallback with \(resolvedPIDs.count) resolved PIDs)"
            )
            return preciseMatches.map { MenuWindowCandidate(windowID: $0.windowID, bounds: $0.bounds) }
        }

        menuOpenCheckTask = task
        let matchedWindowIDs = await task.value
        menuOpenCheckTask = nil
        let result = applyMenuWindowPersistenceFilter(to: matchedWindowIDs)
        // Cache negative results too: bulk move operations (applyProfileLayout)
        // call this guard once per move, and re-enumerating on-screen windows
        // for every move when no menu is open is the common, expensive case.
        // Both polarities share the same freshness window.
        menuOpenCheckCachedResult = result
        menuOpenCheckCachedAt = .now
        return result
    }

    /// Updates first-seen tracking for the matched candidate windows and
    /// returns whether any of them is fresh enough — or currently under the
    /// pointer — to be a real open menu.
    private func applyMenuWindowPersistenceFilter(to candidates: [MenuWindowCandidate]) -> Bool {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: candidates,
            pointerLocation: CGEvent(source: nil)?.location,
            firstSeen: menuWindowFirstSeen,
            now: .now,
            isFirstProbe: !hasSeededMenuWindowProbe,
            threshold: MenuBarItemManager.menuWindowPersistenceThreshold,
            displayBounds: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        )
        menuWindowFirstSeen = outcome.updatedFirstSeen
        hasSeededMenuWindowProbe = true
        if !outcome.ignoredPersistentWindowIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "Menu open check: ignoring \(outcome.ignoredPersistentWindowIDs.count) persistent candidate window(s) \(outcome.ignoredPersistentWindowIDs.sorted())"
            )
        }
        MenuBarItemManager.diagLog.debug("Menu open check result: \(outcome.isMenuOpen)")
        return outcome.isMenuOpen
    }

    /// Pure classification core for the open-menu probe: a candidate window
    /// counts as an open menu while it is young, or at any age while the
    /// pointer is inside it (a user interacting with a long-open menu, or
    /// mid-drop on a shelf). Real menus are transient; persistent
    /// status-level windows (Droppy's shelf, notch HUDs) stay on screen for
    /// the app's whole lifetime and previously deferred every move
    /// indefinitely. Windows already on screen at the first probe are
    /// grandfathered as persistent, and entries for windows that
    /// disappeared are pruned so a reused window ID starts fresh.
    ///
    /// A display-sized candidate is never a menu, whatever its age and
    /// wherever the pointer is. Drop-shelf utilities raise an invisible
    /// menu-level drag-catcher over the whole screen during any drag
    /// session — including the user's own drag inside the layout bar — and
    /// a window that spans the display contains the pointer wherever it
    /// goes, so the under-pointer rule held the probe open for as long as
    /// the overlay stayed up and every drag the user made deferred itself
    /// (#899's greyed-out layout bar).
    static nonisolated func classifyMenuWindowCandidates(
        candidates: [MenuWindowCandidate],
        pointerLocation: CGPoint?,
        firstSeen: [CGWindowID: ContinuousClock.Instant],
        now: ContinuousClock.Instant,
        isFirstProbe: Bool,
        threshold: Duration,
        displayBounds: [CGRect] = []
    ) -> (
        isMenuOpen: Bool,
        updatedFirstSeen: [CGWindowID: ContinuousClock.Instant],
        ignoredPersistentWindowIDs: Set<CGWindowID>
    ) {
        let matchedWindowIDs = Set(candidates.map(\.windowID))
        var updatedFirstSeen = firstSeen.filter { matchedWindowIDs.contains($0.key) }
        let firstSeenForNewWindows = isFirstProbe ? now - threshold : now
        var isMenuOpen = false
        var ignored = Set<CGWindowID>()
        for candidate in candidates {
            let firstSeenAt: ContinuousClock.Instant
            if let existing = updatedFirstSeen[candidate.windowID] {
                firstSeenAt = existing
            } else {
                firstSeenAt = firstSeenForNewWindows
                updatedFirstSeen[candidate.windowID] = firstSeenAt
            }
            guard !Self.isDisplaySizedWindow(candidate.bounds, displayBounds: displayBounds) else {
                ignored.insert(candidate.windowID)
                continue
            }
            let isYoung = firstSeenAt.duration(to: now) < threshold
            let isUnderPointer = pointerLocation.map(candidate.bounds.contains) ?? false
            if isYoung || isUnderPointer {
                isMenuOpen = true
            } else {
                ignored.insert(candidate.windowID)
            }
        }
        return (isMenuOpen, updatedFirstSeen, ignored)
    }

    /// Whether a window covers enough of a display it touches to be an
    /// overlay rather than a menu.
    ///
    /// Half a display is far beyond any real menu — even a Wi-Fi picker
    /// with a long network list stays a narrow column — while a
    /// drag-catcher overlay covers all of one.
    static nonisolated func isDisplaySizedWindow(_ bounds: CGRect, displayBounds: [CGRect]) -> Bool {
        guard !bounds.isEmpty else {
            return false
        }
        return displayBounds.contains { display in
            !display.isEmpty
                && display.intersects(bounds)
                && bounds.width * bounds.height >= display.width * display.height * 0.5
        }
    }

    private static nonisolated func resolveAllSourcePIDs(for windows: [WindowInfo]) async -> Set<pid_t> {
        let pids = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows)
        return Set(pids.compacted())
    }
}

// MARK: - MenuBarItemEventType

/// Event types for menu bar item events.
private nonisolated enum MenuBarItemEventType {
    /// The event type for moving a menu bar item.
    case move(MoveSubtype)
    /// The event type for clicking a menu bar item.
    case click(ClickSubtype)

    var cgEventType: CGEventType {
        switch self {
        case let .move(subtype): subtype.cgEventType
        case let .click(subtype): subtype.cgEventType
        }
    }

    var cgEventFlags: CGEventFlags {
        switch self {
        // The reorder gesture is Command-held for its whole duration, so the
        // drag steps carry the modifier just like the initial press does.
        case .move(.mouseDown), .move(.mouseDragged): .maskCommand
        case .move, .click: []
        }
    }

    var cgMouseButton: CGMouseButton {
        switch self {
        case .move: .left
        case let .click(subtype): subtype.cgMouseButton
        }
    }

    // MARK: Subtypes

    /// Subtype for menu bar item move events.
    enum MoveSubtype {
        case mouseDown
        case mouseDragged
        case mouseUp

        var cgEventType: CGEventType {
            switch self {
            case .mouseDown: .leftMouseDown
            case .mouseDragged: .leftMouseDragged
            case .mouseUp: .leftMouseUp
            }
        }
    }

    /// Subtype for menu bar item click events.
    enum ClickSubtype {
        case leftMouseDown
        case leftMouseUp
        case rightMouseDown
        case rightMouseUp
        case otherMouseDown
        case otherMouseUp

        var cgEventType: CGEventType {
            switch self {
            case .leftMouseDown: .leftMouseDown
            case .leftMouseUp: .leftMouseUp
            case .rightMouseDown: .rightMouseDown
            case .rightMouseUp: .rightMouseUp
            case .otherMouseDown: .otherMouseDown
            case .otherMouseUp: .otherMouseUp
            }
        }

        var cgMouseButton: CGMouseButton {
            switch self {
            case .leftMouseDown, .leftMouseUp: .left
            case .rightMouseDown, .rightMouseUp: .right
            case .otherMouseDown, .otherMouseUp: .center
            }
        }

        var clickState: Int64 {
            switch self {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: 1
            case .leftMouseUp, .rightMouseUp, .otherMouseUp: 0
            }
        }
    }
}

// MARK: Layout Reset

extension MenuBarItemManager {
    /// Errors that can occur during a layout reset.
    enum LayoutResetError: LocalizedError {
        case missingAppState
        case missingControlItems
        case alreadyInProgress

        var errorDescription: String? {
            switch self {
            case .missingAppState:
                "Unable to access app state"
            case .missingControlItems:
                "Couldn't find section dividers in the menu bar"
            case .alreadyInProgress:
                "A layout reset is already in progress"
            }
        }

        var recoverySuggestion: String? {
            "Make sure \(Constants.displayName) is running and try again."
        }
    }

    /// Resets menu bar layout data to a fresh-install state and moves all
    /// movable, hideable items (except the Thaw icon) to the
    /// Hidden section.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToFreshState() async throws -> Int {
        try await resetLayout(to: .hidden)
    }

    /// Moves every movable, hideable item except the Thaw icon to Visible.
    func resetLayoutToVisible() async throws -> Int {
        try await resetLayout(to: .visible)
    }

    /// Moves every movable, hideable item except the Thaw icon to Always Hidden.
    func resetLayoutToAlwaysHidden() async throws -> Int {
        try await resetLayout(to: .alwaysHidden)
    }

    private func resetLayout(to target: LayoutResetTarget) async throws -> Int {
        guard !isResettingLayout else {
            MenuBarItemManager.diagLog.warning("resetLayout: already in progress, rejecting concurrent reset")
            throw LayoutResetError.alreadyInProgress
        }

        MenuBarItemManager.diagLog.info("Resetting menu bar layout to \(target.logString)")
        // A user-initiated reset is authoritative: end the startup settling period
        // immediately so that the post-reset cache is not blocked from running restore
        // and saveSectionOrder by an in-flight settling task.
        startupSettlingTask?.cancel()
        isInStartupSettling = false
        settlingDeadline = nil
        settlingExpectedBundleIDs.removeAll()
        settlingKind = nil
        isResettingLayout = true
        defer { isResettingLayout = false }

        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenWID
        ) else {
            MenuBarItemManager.diagLog.error("Layout reset aborted: missing hidden section control item")

            // Attempt a forced restore by re-enabling the always hidden section flag and
            // nudging macOS to recreate control items, then retry once.
            if appState.settings.advanced.enableAlwaysHiddenSection {
                appState.settings.advanced.enableAlwaysHiddenSection = false
                try? await Task.sleep(for: .milliseconds(50))
                appState.settings.advanced.enableAlwaysHiddenSection = true
                try? await Task.sleep(for: .milliseconds(150))

                items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                if let retryControlItems = ControlItemPair(
                    items: &items,
                    hiddenControlItemWindowID: hiddenWID,
                    alwaysHiddenControlItemWindowID: alwaysHiddenWID
                ), retryControlItems.canRepositionControlItems {
                    guard !target.requiresAlwaysHiddenDivider || retryControlItems.alwaysHidden != nil else {
                        throw LayoutResetError.missingControlItems
                    }
                    MenuBarItemManager.diagLog.info("Recovered hidden section control item after re-enabling always-hidden section")
                    prepareLayoutStateForReset()
                    await enforceControlItemOrder(controlItems: retryControlItems)
                    return try await resetLayoutWithControlItems(
                        controlItems: retryControlItems,
                        items: items,
                        target: target
                    )
                }
            }

            throw LayoutResetError.missingControlItems
        }

        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted: control items resolved only by provisional AX-frame correlation"
            )
            throw LayoutResetError.missingControlItems
        }
        guard !target.requiresAlwaysHiddenDivider || controlItems.alwaysHidden != nil else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted: always-hidden section divider is unavailable"
            )
            throw LayoutResetError.missingControlItems
        }

        // Mutate authoritative layout state only after divider identity is
        // authoritative; a provisional lookup must leave the saved layout intact.
        prepareLayoutStateForReset()

        await enforceControlItemOrder(controlItems: controlItems)

        return try await resetLayoutWithControlItems(
            controlItems: controlItems,
            items: items,
            target: target
        )
    }

    private func prepareLayoutStateForReset() {
        ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] = 0
        ControlItemDefaults.resetChevronPositions()

        knownItemIdentifiers.removeAll()
        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        pendingRelocations.removeAll()
        pendingReturnDestinations.removeAll()
        savedSectionOrder.removeAll()
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        persistKnownItemIdentifiers()
        persistPinnedBundleIDs()
        persistPendingRelocations()
        persistSavedSectionOrder()
        // A reset starts from no verdicts: surviving retirements would keep
        // pruning identifiers out of a layout the user just asked to rebuild.
        staleIdentifierLedger.removeAll()
        temporarilyShownItemContexts.removeAll()

        newItemsPlacement = NewItemsPlacement.defaultValue
        Defaults.removeObject(forKey: .newItemsSection)
        Defaults.removeObject(forKey: .newItemsPlacementData)
        suppressNextNewLeftmostItemRelocation = true
    }

    private func resetLayoutWithControlItems(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        target: LayoutResetTarget
    ) async throws -> Int {
        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        appState.menuBarManager.iceBarPanel.close()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        func destination(for controls: ControlItemPair) -> MoveDestination? {
            switch target {
            case .visible:
                .rightOfItem(controls.hidden)
            case .hidden:
                .leftOfItem(controls.hidden)
            case .alwaysHidden:
                controls.alwaysHidden.map(MoveDestination.leftOfItem)
            }
        }

        func itemsOutsideTarget(_ items: [MenuBarItem], controls: ControlItemPair) -> [MenuBarItem] {
            let hiddenBounds = Bridging.getWindowBounds(for: controls.hidden.windowID)
                ?? controls.hidden.bounds
            let alwaysHiddenBounds = controls.alwaysHidden.flatMap {
                Bridging.getWindowBounds(for: $0.windowID) ?? $0.bounds
            }
            return items.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let itemBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                return !target.contains(
                    itemBounds: itemBounds,
                    hiddenBounds: hiddenBounds,
                    alwaysHiddenBounds: alwaysHiddenBounds
                )
            }
        }

        func movePass(_ items: [MenuBarItem], controls: ControlItemPair) async -> Int {
            guard let destination = destination(for: controls) else {
                return items.count
            }
            var failed = 0
            for item in items {
                if item.tag == .visibleControlItem {
                    continue // Keep the Thaw icon in the visible section if enabled.
                }

                guard item.isMovable, item.canBeHidden, !item.isControlItem else {
                    continue
                }

                do {
                    try await move(
                        item: item,
                        to: destination,
                        skipInputPause: true,
                        watchdogTimeout: Self.layoutWatchdogTimeout
                    )
                } catch {
                    failed += 1
                    MenuBarItemManager.diagLog.error("Failed to move \(item.logString) during layout reset: \(error)")
                }
            }
            return failed
        }

        let firstPassItems = target.movesAllCandidatesInFirstPass
            ? items
            : itemsOutsideTarget(items, controls: controlItems)
        _ = await movePass(firstPassItems, controls: controlItems)

        // Give macOS a moment to settle after the first pass.
        try? await Task.sleep(for: .milliseconds(200))

        // Re-fetch and retry only items that are not yet in the target section.
        var refreshedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedMoves = 0
        let refreshHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let refreshAlwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        guard let refreshedControls = ControlItemPair(
            items: &refreshedItems,
            hiddenControlItemWindowID: refreshHiddenWID,
            alwaysHiddenControlItemWindowID: refreshAlwaysHiddenWID
        ), refreshedControls.canRepositionControlItems,
        !target.requiresAlwaysHiddenDivider || refreshedControls.alwaysHidden != nil
        else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted before pass 2: authoritative section dividers are unavailable"
            )
            throw LayoutResetError.missingControlItems
        }

        let notYetInTarget = itemsOutsideTarget(refreshedItems, controls: refreshedControls)
        if !notYetInTarget.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "Layout reset pass 2: \(notYetInTarget.count) items not yet in \(target.logString)"
            )
            failedMoves = await movePass(notYetInTarget, controls: refreshedControls)
        }

        cacheActor.clearCachedItemWindowIDs()
        itemCache = ItemCache(displayID: nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let token = self.addBackgroundCacheWaiter(continuation)
            Task { [weak self] in
                await self?.cacheItemsRegardless(skipRecentMoveCheck: true, waiterToken: token)
            }
            // Watchdog: guarantee this continuation is resumed even if the
            // cache call above bails before reaching the serialization gate
            // (in which case it never takes ownership of the waiter and the
            // defer in cacheItemsRegardless never fires for this token) or
            // if the nested recache Task it hands off to never runs because
            // `self` was deallocated first. Whichever side removes the token
            // from the waiter table first owns the resume; the other is a
            // no-op.
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.layoutWatchdogTimeout)
                guard let self, self.backgroundCacheWaiters[token] != nil else { return }
                MenuBarItemManager.diagLog.warning(
                    "resetLayout: background cache wait timed out after \(MenuBarItemManager.layoutWatchdogTimeout); resuming via watchdog"
                )
                self.resumeBackgroundCacheWaiter(token)
            }
        }
        suppressNextNewLeftmostItemRelocation = false

        await MainActor.run {
            appState.imageCache.clearAll()
            appState.imageCache.performCacheCleanup()
        }

        if itemCache.displayID != nil {
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }

        // `appState` is now `@Observable` (wave 4), so the manual
        // `objectWillChange.send()` poke that used to force views bound to
        // `appState` to refresh after the async `imageCache` mutations above
        // is no longer needed: Observation tracks each mutated property
        // (`imageCache`'s own storage) directly, independent of this poke.

        // Clear any stale -1 sentinel that may have been written into
        // menuBarHeightCache while the Menubar window was transiently
        // unavailable during the reset. The item cache is fully rebuilt
        // at this point, so the next mouse event will perform a fresh
        // live lookup and cache the correct height.
        NSScreen.invalidateMenuBarHeightCache()

        return failedMoves
    }

    /// Wrapper for UI callers; kept separate for clarity in call sites.
    @MainActor
    func resetLayoutFromSettingsPane() async throws -> Int {
        try await resetLayoutToFreshState()
    }

    /// Ends an in-flight settling period immediately. Used by paths that
    /// pre-flight a settling period before a potentially-no-op spacing
    /// apply: when applyOffset turns out not to relaunch anything, the
    /// pre-flight is cancelled so subsequent restore logic isn't
    /// suppressed unnecessarily.
    ///
    /// Refuses to cancel a settling that has already been promoted to
    /// expected-set mode by a real relaunch wave. Otherwise a concurrent
    /// no-op apply (typically from a duplicate screenParametersChanged
    /// notification that finds the on-disk spacing already correct) would
    /// tear down the wait for those bundle IDs to reattach, leaving
    /// applyProfileLayout to run against a half-populated cache.
    func cancelSettlingPeriod(reason: String) {
        guard isInStartupSettling || startupSettlingTask != nil else { return }
        if !settlingExpectedBundleIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling cancel ignored; \(settlingExpectedBundleIDs.count) expected bundle ID(s) still pending"
            )
            return
        }
        // Cold-boot settling is authoritative. A noOp from a boot-time
        // applyOffset that found on-disk values already correct must not
        // tear it down; many menu bar apps haven't reattached yet, and
        // applyProfileLayout would then run against a half-populated cache
        // and silently report "all items already in correct positions".
        if settlingKind == .cold {
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling cancel ignored; performSetup settling in flight"
            )
            return
        }
        startupSettlingTask?.cancel()
        startupSettlingTask = nil
        isInStartupSettling = false
        settlingDeadline = nil
        settlingKind = nil
        MenuBarItemManager.diagLog.debug("\(reason): settling period cancelled")
    }

    /// Schedules a debounced re-application of the active profile's layout
    /// to place late-arriving items in their correct positions. Multiple
    /// calls within the debounce window are coalesced into a single re-sort.
    private func scheduleProfileResort() {
        profileResortTask?.cancel()
        profileResortTask = Task { [weak self] in
            // Short debounce to coalesce multiple items appearing in quick
            // succession. The app-launch notification already has a 1s debounce,
            // so this only needs to cover the gap between detection and action.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return // Cancelled; a newer schedule replaced us.
            }
            guard let self, let layout = self.activeProfileLayout else { return }
            guard !self.isInStartupSettling else { return }
            guard !self.isRestoringItemOrder else { return }

            // Same gate `applySavedLayout` consults, for the same reason.
            // This dispatch already feeds the streak through
            // `recordBulkApplyOutcome`, but until now nothing read it here,
            // so a bar whose batches never complete re-sorted on every
            // late arrival forever. In #899 that ran seven passes in 22
            // seconds — each one a full move batch with the cursor
            // hijacked — until the reporter killed the app.
            //
            // A late-arrival re-sort is automatic, so it belongs under the
            // gate. User-initiated applies still bypass it: `applyProfile`
            // calls `applyProfileLayout` directly and never comes through
            // here.
            guard self.isAutomaticBulkApplyPermitted(caller: "Profile re-sort") else {
                self.profileResortTask = nil
                return
            }

            MenuBarItemManager.diagLog.info("Profile re-sort: re-applying layout for late-arriving items")
            // Clear profileResortTask BEFORE calling applyProfileLayout,
            // because applyProfileLayout cancels profileResortTask to
            // prevent concurrent re-sorts; which would cancel THIS task
            // and cause the move loop to exit via Task.isCancelled.
            self.profileResortTask = nil
            await self.applyProfileLayout(
                pinnedHidden: layout.pinnedHidden,
                pinnedAlwaysHidden: layout.pinnedAlwaysHidden,
                sectionOrder: layout.sectionOrder,
                itemSectionMap: layout.itemSectionMap,
                itemOrder: layout.itemOrder,
                automatic: true
            )
        }
    }

    /// Clears the cached active profile layout, stopping any pending
    /// late-arrival re-sort. Called when the active profile is cleared.
    func clearActiveProfileLayout() {
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        isApplyingProfileLayout = false
    }

    /// Awaits the end of the startup settling window before returning.
    ///
    /// Loops in case performSetup re-enters mid-await (e.g. a permission
    /// re-grant during login): re-entry cancels the captured task and
    /// starts a new settling window, so resuming on a single captured
    /// task could land back inside an active window. Re-check
    /// isInStartupSettling after each await and pick up the current
    /// startupSettlingTask.
    private func waitForStartupSettlingToEnd() async {
        while isInStartupSettling {
            guard let settlingTask = startupSettlingTask else { break }
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: waiting for startup settling to end"
            )
            await settlingTask.value
        }
    }

    /// Applies a profile's layout by moving items to match the profile's
    /// saved section assignments and within-section ordering.
    ///
    /// Uses per-item identifiers (not just bundle IDs) to correctly handle
    /// apps like Control Center that share a single bundle ID across many
    /// items (WiFi, Battery, etc.).
    ///
    /// The approach processes each section's saved item order and moves items
    /// into position one at a time, achieving both correct section placement
    /// and correct ordering in a single pass.
    /// Source of an applyProfileLayout invocation. Determines which
    /// pieces of class-level state are armed at entry and cleared at
    /// exit. The shared body (discovery, unmanaged placement, notch
    /// overflow, execution) is identical regardless of source.
    ///
    /// - profile: applying a profile spec. The spec overwrites
    ///   savedSectionOrder, pinning sets, and activeProfileLayout;
    ///   isApplyingProfileLayout gates concurrent restores; the
    ///   profile-sorted snapshot updates at exit for late-arrival
    ///   detection.
    /// - savedOrder: re-applying the user's saved layout (no profile
    ///   spec involved). savedSectionOrder is already the source of
    ///   truth and is not overwritten; pinning is preserved;
    ///   activeProfileLayout is not touched. Only isRestoringItemOrder
    ///   is armed.
    enum ApplySource {
        case profile
        case savedOrder
    }

    /// Arms in-memory profile state and the in-flight gate. No-op for
    /// .savedOrder so the saved-layout path skips profile-specific
    /// arming. Centralises the field set so adding a profile-scoped
    /// field touches one place.
    ///
    /// Disk persistence is deferred to persistProfileStateOnSuccess,
    /// which runs only after the bulk apply reaches a success exit
    /// (Phase 6 finished, an early-return for "already in target", or
    /// Phase 7 with Task.isCancelled false). If a crash, SIGKILL, or
    /// mid-apply cancellation aborts before that point, disk reflects
    /// the previous profile rather than an unexecuted intent.
    func armProfileState(
        source: ApplySource,
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        guard case .profile = source else { return }

        // Snapshot the displaced state before overwriting so a cancelled
        // apply can roll back to what disk still holds (persistence is
        // deferred to persistProfileStateOnSuccess). The token pins the
        // snapshot to this apply: once a newer apply re-arms, the
        // displaced apply no longer owns the state and must not restore.
        profileApplyToken &+= 1
        priorProfileApplySnapshot = ProfileApplySnapshot(
            token: profileApplyToken,
            pinnedHidden: pinnedHiddenBundleIDs,
            pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
            sectionOrder: savedSectionOrder,
            profileLayout: activeProfileLayout,
            profileItemIdentifiers: activeProfileItemIdentifiers
        )

        pinnedHiddenBundleIDs = pinnedHidden
        pinnedAlwaysHiddenBundleIDs = pinnedAlwaysHidden
        savedSectionOrder = sectionOrder

        profileResortTask?.cancel()
        profileResortTask = nil
        isApplyingProfileLayout = true
        activeProfileLayout = (
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )
        activeProfileItemIdentifiers = Set(itemOrder.values.flatMap(\.self))
    }

    /// Rolls back the in-memory profile state after a cancelled apply,
    /// but only when the cancelled apply still owns it (no newer apply
    /// has re-armed since). Ownership is checked via the apply token: a
    /// newer arm bumps the token, so the late-arriving cancellation of
    /// the displaced apply leaves the newer apply's state — including
    /// its in-flight flag — untouched.
    private func restoreProfileStateAfterAbortedApply(token: Int) {
        guard token == profileApplyToken,
              let snapshot = priorProfileApplySnapshot,
              snapshot.token == token
        else {
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: cancelled apply no longer owns the armed profile state, skipping rollback"
            )
            return
        }
        pinnedHiddenBundleIDs = snapshot.pinnedHidden
        pinnedAlwaysHiddenBundleIDs = snapshot.pinnedAlwaysHidden
        savedSectionOrder = snapshot.sectionOrder
        activeProfileLayout = snapshot.profileLayout
        activeProfileItemIdentifiers = snapshot.profileItemIdentifiers
        priorProfileApplySnapshot = nil
        isApplyingProfileLayout = false
        MenuBarItemManager.diagLog.info(
            "applyProfileLayout: aborted apply rolled back in-memory profile state to the last committed profile"
        )
    }

    /// Refreshes the cached active-profile spec to match a freshly saved
    /// layout, without performing any moves. Called when the user updates the
    /// currently-active profile (Update Layout / Update All): the saved layout
    /// is captured from the live savedSectionOrder, so the bar is already in
    /// the target arrangement and only the in-memory spec that drives
    /// late-arrival re-sorts needs to catch up. armProfileState runs only on
    /// apply, so without this an update leaves activeProfileLayout pointing at
    /// the pre-update spec and the next late-arrival re-sort reverts the bar
    /// until the profile is re-applied.
    ///
    /// Unlike armProfileState this performs a pure cache refresh: it does not
    /// touch savedSectionOrder or the live pinning sets (the snapshot already
    /// equals them), does not arm isApplyingProfileLayout, and does not cancel
    /// an in-flight re-sort.
    func rearmActiveProfileLayout(
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        activeProfileLayout = (
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )
        activeProfileItemIdentifiers = Set(itemOrder.values.flatMap(\.self))
        MenuBarItemManager.diagLog.debug(
            "rearmActiveProfileLayout: refreshed cached profile spec after active-profile update (\(self.activeProfileItemIdentifiers.count) item identifiers)"
        )
    }

    /// Persists the profile's pinning sets and saved section order to
    /// disk. Called from each applyProfileLayout success exit so the
    /// on-disk intent only commits once the bar reflects it. No-op for
    /// .savedOrder (that path doesn't overwrite either store).
    private func persistProfileStateOnSuccess(source: ApplySource) {
        guard case .profile = source else { return }
        persistPinnedBundleIDs()
        persistSavedSectionOrder()
        // Committed: the pre-arm snapshot can no longer be rolled back to.
        priorProfileApplySnapshot = nil
    }

    /// Refreshes profileSortedItemIdentifiers from the supplied item
    /// set. Called from each apply early-return so late-arrival re-sort
    /// doesn't keep re-triggering for items already evaluated. No-op
    /// for .savedOrder (no active profile to track).
    private func updateProfileSortedSnapshot(source: ApplySource, items: [MenuBarItem]) {
        guard case .profile = source else { return }
        profileSortedItemIdentifiers = Set(
            items
                .filter { !$0.isControlItem }
                .map(\.uniqueIdentifier)
        )
    }

    /// Profile-only exit cleanup: refresh the sorted snapshot and clear
    /// the in-flight profile flag. No-op for .savedOrder.
    private func clearProfileState(source: ApplySource, items: [MenuBarItem]) {
        updateProfileSortedSnapshot(source: source, items: items)
        guard case .profile = source else { return }
        isApplyingProfileLayout = false
    }

    /// Cleanup for a profile apply that needed no item moves: the bar was
    /// already in the target arrangement, so the move loop is skipped and the
    /// normal Phase 7 exit (which clears the in-flight flag) is never reached.
    /// This early exit must run the same profile-only teardown as Phase 7,
    /// otherwise a no-moves apply (common on a display reconnect, where the
    /// active-display profile is re-applied onto an already-correct bar) leaks
    /// isApplyingProfileLayout = true and permanently blocks applySavedLayout
    /// for the rest of the session.
    func concludeProfileApplyWithoutMoves(source: ApplySource, items: [MenuBarItem]) {
        persistProfileStateOnSuccess(source: source)
        clearProfileState(source: source, items: items)
    }

    /// Schedules the post-apply refresh sequence on a detached Task:
    /// a full cache cycle (which updates itemCache, re-runs the
    /// relocate paths and persists savedSectionOrder if appropriate),
    /// then imageCache cleanup and an observer notification.
    ///
    /// applyProfileLayout's exit points (Phase 7 normal exit plus the
    /// Phase 6 early-returns) cannot inline-await cacheItemsRegardless
    /// because they're inside a body that the outer cacheItemsRegardless
    /// is awaiting via applySavedLayout. The outer call holds its
    /// serial cacheGate across that await, so an inline recursive call
    /// is rejected with "serial cache operation already in progress,
    /// skipping" and itemCache stays stale (the field-reported symptom:
    /// quit apps still appear in Settings Layout, ThawBar, and Search
    /// until something else triggers a non-applySavedLayout cache
    /// cycle). Spawning a Task defers execution until after the outer
    /// releases the gate, mirroring the relocate-path recache pattern.
    /// The uiSettleDelay gives WindowServer a tick to settle the moves
    /// (or, for early-returns, the windowID churn that triggered the
    /// apply) before the next snapshot.
    private func scheduleDeferredCacheRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            guard let self else { return }
            // skipSavedLayoutApply=true breaks the dispatch loop: the
            // apply already ran (we're scheduling a refresh after it);
            // re-entering applySavedLayout here would re-trigger on
            // any transient windowID-set churn and live-lock the bar.
            // Cache update + save still run via uncheckedCacheItems.
            await self.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                skipSavedLayoutApply: true
            )
            guard let appState = self.appState else { return }
            appState.imageCache.performCacheCleanup()
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            // `appState` is now `@Observable` (wave 4); Observation tracks
            // the `imageCache` mutations above directly, so the manual
            // `objectWillChange.send()` poke is no longer needed.
        }
    }

    func applyProfileLayout(
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder rawSectionOrder: [String: [String]],
        itemSectionMap rawItemSectionMap: [String: String],
        itemOrder rawItemOrder: [String: [String]],
        source: ApplySource = .profile,
        automatic: Bool = false
    ) async {
        // A profile saved before an item was renamed after its app still
        // names it by its helper (`at.obdev.littlesnitch.agent:Item-0`).
        // Migrate on the way in so the plan is built against identifiers
        // the live bar can actually produce; the profile on disk is
        // rewritten the next time the layout is persisted. Keyed maps are
        // migrated too, or the section lookup misses the renamed entry.
        let sectionOrder = LayoutSolver.canonicalizedSectionOrder(rawSectionOrder)
        let itemOrder = LayoutSolver.canonicalizedSectionOrder(rawItemOrder)
        let itemSectionMap = Dictionary(
            rawItemSectionMap.map { (LayoutSolver.canonicalIdentifier($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        // MARK: Phase 0: gate on startup settling

        //
        // During settling, cacheItemsRegardless skips restore and
        // absorbs every current item into profileSortedItemIdentifiers;
        // a layout applied here has its moves silently shadowed and the
        // late-arrival re-sort path is broken for items that appeared
        // inside the window.
        await waitForStartupSettlingToEnd()

        // Automatic applies additionally wait for the user to stop
        // interacting. `automatic` is the same distinction
        // `automaticBulkApplyPermitted` already draws at the two dispatch
        // sites: a late-arrival re-sort or a saved-layout restore is
        // something Thaw decided to do, and it can afford to wait for a
        // lull. A profile the user just picked cannot — they are watching
        // for it to happen, and their hand is still on the mouse that
        // picked it.
        if automatic {
            // The escape hatch. Checked before the idle wait so a bar in
            // manual mode spends nothing at all on an apply it will not
            // perform, and before armProfileState so no profile state is
            // armed for a sequence that never runs.
            let automaticArrangementEnabled = (Defaults.object(forKey: .automaticArrangementEnabled) as? Bool)
                ?? Defaults.DefaultValue.automaticArrangementEnabled
            guard automaticArrangementEnabled else {
                MenuBarItemManager.diagLog.info(
                    "Profile layout: skipping automatic apply; automaticArrangementEnabled is false (manual arrangement only)"
                )
                return
            }
            // The dispatch sites check this too, but every automatic caller
            // funnels through here, so enforcing it at the funnel keeps a
            // future dispatch site from bypassing the breaker unknowingly.
            guard isAutomaticBulkApplyPermitted(caller: "Profile layout") else {
                return
            }
            await waitForBulkApplyIdleWindow()
        }

        // Bail before arming any profile state if cancellation arrived
        // during the settling wait (a newer apply has replaced us via
        // applyProfile's layoutTask?.cancel()).
        if Task.isCancelled {
            return
        }

        // MARK: Phase 1: persist state and arm in-flight flags

        // Profile-only: overwrite the persisted layout state with the
        // profile spec and arm activeProfileLayout / late-arrival
        // tracking. The savedOrder path keeps savedSectionOrder
        // unchanged (it IS the source) and skips activeProfileLayout
        // entirely; the relocateNewLeftmostItems path handles
        // late-arrivals for non-profile restores.
        armProfileState(
            source: source,
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )

        // Token identifying this apply's ownership of the armed profile
        // state. Captured immediately after arming, before any await can
        // let a newer apply re-arm. Only meaningful for the .profile
        // source (the cancellation rollback below is gated on it).
        let applyToken = profileApplyToken

        // Prevent the cache cycle from saving intermediate positions.
        // Shared across both sources: the apply moves items in flight
        // regardless of trigger, and saveSectionOrder must not capture
        // those intermediate states.
        isRestoringItemOrder = true
        isRestoringItemOrderTimestamp = Date()
        defer {
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        guard !itemOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applyProfileLayout: no item order, skipping")
            concludeProfileApplyWithoutMoves(source: source, items: [])
            return
        }
        guard let appState else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing appState")
            clearProfileState(source: source, items: [])
            return
        }

        // MARK: Phase 2: discover items, classify sections, build sequences

        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        // Build desired flat sequence (right-to-left): visible, hidden, alwaysHidden.
        // This is the target linear order of all items across all sections.
        // Control item UIDs are inserted at section boundaries after the
        // items are discovered (since we need the ControlItemPair first).
        var desiredFlat = [String]()
        for key in ["visible", "hidden", "alwaysHidden"] {
            if let order = itemOrder[key] {
                desiredFlat.append(contentsOf: order)
            }
        }

        // Discover current items and build current flat sequence (right-to-left).
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // Drop transient System Status Item Clone windows before planning.
        // partitionUnmanagedUIDs would otherwise classify a clone as an
        // unmanaged item and anchor it into a section, dragging a phantom
        // and reshuffling the bar. This fetch is independent of the cache
        // path, so it needs its own filter.
        items.removeAll(where: \.isSystemClone)

        // Skip the bulk apply while the majority of items have no resolved
        // sourcePID — uniqueIdentifier (used to match items against
        // itemOrder/itemSectionMap) is derived from sourcePID via
        // MenuBarItemTag's namespace, so an unresolved-PID majority means
        // the identifiers used for matching are unreliable.
        let unresolvedSourcePIDCount = items.count { $0.sourcePID == nil }
        if Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedSourcePIDCount, itemCount: items.count) {
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: skipping, \(unresolvedSourcePIDCount)/\(items.count) items have unresolved sourcePIDs (XPC resolution likely failed)"
            )
            clearProfileState(source: source, items: items)
            return
        }

        // Never drag items while a menu bar item menu is tracking — a synthetic
        // Cmd-drag would tear down the user's interaction (Wi-Fi picker, input
        // methods). State is unwound so a subsequent apply can retry cleanly.
        if await isAnyMenuBarItemMenuOpen() {
            MenuBarItemManager.diagLog.info("applyProfileLayout: skipping, a menu bar item menu is open")
            clearProfileState(source: source, items: items)
            return
        }

        guard var itemsCopy = Optional(items),
              let controlItems = ControlItemPair(
                  items: &itemsCopy,
                  hiddenControlItemWindowID: hiddenWID,
                  alwaysHiddenControlItemWindowID: alwaysHiddenWID
              )
        else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing control items")
            clearProfileState(source: source, items: items)
            return
        }

        // The always-hidden divider is what tells always-hidden items apart
        // from hidden ones. Without it findSection collapses the two sections,
        // so Phase 1 reads every always-hidden item as sitting in hidden and
        // plans a cross-section move for each one. Those moves land — the
        // mover finds the divider by tag even when the pair could not — and
        // change nothing, so the next pass plans the same set again.
        //
        // #881's 08:41 log dragged the same six items 69 times over four
        // minutes on `ahCtrlUID=nil, crossSectionMoves=8`, the always-hidden
        // divider having gone unresolved in 552 of 578 cycles.
        //
        // `saveSectionOrder` already refuses to persist this reading (#849).
        // Refusing to move on it is the same judgement one step earlier: an
        // apply that cannot see the boundary cannot plan across it. The state
        // is unwound so the next cache tick retries once the pair resolves.
        guard LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: controlItems.alwaysHidden != nil,
            isAlwaysHiddenSectionEnabled: appState.menuBarManager
                .section(withName: .alwaysHidden)?.isEnabled ?? false
        ) else {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping, always-hidden divider unresolved while its section is enabled"
            )
            clearProfileState(source: source, items: items)
            return
        }

        // AX-frame correlation is sufficient for a read-only cache snapshot,
        // but not for any synthetic drag. Even ordinary-item LCS destinations
        // depend on section classification and may fall back to one of these
        // dividers, so restricting only direct divider moves is not enough.
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping, control items resolved only by provisional AX-frame correlation"
            )
            if case .profile = source {
                restoreProfileStateAfterAbortedApply(token: applyToken)
            }
            return
        }

        // Build current flat sequence grouped by section (same structure as desired).
        // Raw X-position order interleaves sections and gives bad LCS results.
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )

        func isProfileItem(_ item: MenuBarItem) -> Bool {
            (item.canBeHidden || item.tag == .visibleControlItem) && item.isMovable
        }

        let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
        let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

        // Snapshot each item's current section ONCE so the cache-log loop
        // and Phase 1 below see identical classifications. context.findSection
        // re-queries the Window Server via Bridging.getWindowBounds on every
        // call. Between the cache-log iteration (a few lines below) and the
        // Phase 1 iteration further down, the transient bounds reported
        // during a section.show()-driven control-item move can flip an
        // item's classification, producing empty currentHiddenSet and
        // currentAHSet that let Phase 1 skip the AH_ctrl move when items
        // legitimately need to cross the hidden↔always-hidden boundary.
        // Indexed by windowID because items duplicated across displays
        // share a uniqueIdentifier but have distinct windows; storing per
        // window preserves each instance's own classification.
        var sectionByWindowID: [CGWindowID: MenuBarSection.Name] = [:]
        for item in items where isProfileItem(item) {
            if let section = context.findSection(for: item) {
                sectionByWindowID[item.windowID] = section
            }
        }

        // Rebuild desiredFlat with control items at section boundaries.
        var sectionMap = itemSectionMap
        var desiredFlatWithControls = [String]()
        if let order = itemOrder["visible"] {
            desiredFlatWithControls.append(contentsOf: order)
        }
        desiredFlatWithControls.append(hiddenCtrlUID)
        sectionMap[hiddenCtrlUID] = "hidden"
        if let order = itemOrder["hidden"] {
            desiredFlatWithControls.append(contentsOf: order)
        }
        if let ahCtrlUID {
            desiredFlatWithControls.append(ahCtrlUID)
            sectionMap[ahCtrlUID] = "alwaysHidden"
        }
        if let order = itemOrder["alwaysHidden"] {
            desiredFlatWithControls.append(contentsOf: order)
        }
        desiredFlat = desiredFlatWithControls

        // Build current flat sequence with control items at section
        // boundaries. The hidden and always-hidden control items are
        // filtered out of sectionItems even when findSection classifies
        // them into a section, because they are appended explicitly
        // after their respective sections below. Without this filter
        // each divider would appear twice in currentFlat (once via the
        // section iteration, once via the explicit append), which desyncs
        // it from the single-divider desiredFlat and makes the LCS plan
        // spurious divider moves every cycle.
        var sectionUIDs = [MenuBarSection.Name: [String]]()
        for sectionName in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
            let sectionItems = items.filter { item in
                guard isProfileItem(item) else { return false }
                let uid = item.uniqueIdentifier
                guard uid != hiddenCtrlUID, uid != ahCtrlUID else { return false }
                return sectionByWindowID[item.windowID] == sectionName
            }
            // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
            // Changing this string breaks log-replay regression tests.
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: current \(sectionName.logString) has \(sectionItems.count) items: \(sectionItems.map(\.uniqueIdentifier))"
            )
            sectionUIDs[sectionName] = sectionItems.map(\.uniqueIdentifier)
        }
        // Flatten with control items at the section boundaries via the shared
        // pure helper, so this path and the log-replay harness build currentFlat
        // identically.
        var currentFlat = LayoutSolver.flattenCurrentSections(
            visible: sectionUIDs[.visible] ?? [],
            hidden: sectionUIDs[.hidden] ?? [],
            alwaysHidden: sectionUIDs[.alwaysHidden] ?? [],
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID
        )

        // Filter desired sequence to only items present in the current bar.
        let currentSet = Set(currentFlat)
        var desiredFiltered = desiredFlat.filter { currentSet.contains($0) }

        // Record which of the profile's identifiers still correspond to
        // something on the bar. This is the one place in the apply that knows
        // both halves at once, and it sits past every early return, so an
        // apply that never looked at the bar cannot be counted as evidence
        // that an item is gone. Only the profile's own entries are sampled —
        // control items are always present and would dilute the ratio the
        // ledger uses to throw out a degraded pass.
        let plannedIdentifiers = Set(itemOrder.values.joined())
        staleIdentifierLedger.recordApply(
            planned: plannedIdentifiers,
            matched: plannedIdentifiers.intersection(currentSet)
        )

        // MARK: Phase 3: place unmanaged items via planUnmanagedPlacement

        // Items present in the menu bar but not in the profile are
        // placed via planUnmanagedPlacement. The planner consults the
        // user's saved layout history first (so a previously-seen app
        // returns to where the user last had it) and falls back to the
        // NewItemsPlacement preference for never-seen items. This
        // replaces the older hardcoded "park all unmanaged at visible-
        // leftmost" behavior.
        let visibleCtrlUID = items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier
        let desiredSet = Set(desiredFiltered)
        // Generic Control Center items (Item-N title) with no resolved source
        // PID are widgets macOS hosts under Control Center that Thaw cannot yet
        // attribute to their owning app (e.g. Little Snitch's agent before its
        // marker window appears). They fall back to the com.apple.controlcenter
        // namespace, never match a profile entry, and so would be relocated as
        // unmanaged arrivals on every cycle. Exclude them until they resolve.
        let provisionalIdentityUIDs = LayoutSolver.provisionalIdentityUIDs(items: items)
        let unmanagedUIDs = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: desiredSet,
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID,
            visibleCtrlUID: visibleCtrlUID,
            provisionalIdentityUIDs: provisionalIdentityUIDs
        )
        if !unmanagedUIDs.isEmpty {
            // Build a DesiredLayout for the profile-apply context: the
            // saved layout is the source of truth for previously-seen
            // items; NewItemsPlacement is the fallback for unseen ones.
            // Pinning is left empty here because this code path only
            // positions unmanaged items, not the profile spec items.
            // Retired identifiers are dropped before the lookup, not after:
            // the saved position is an *index* into these arrays, so a ghost
            // ahead of a live entry pushes a returning item one slot right of
            // where the user left it, every time, forever. The same pruned
            // order must feed the application below — a saved index only
            // means anything in the space it was computed in.
            let prunedSavedOrder = staleIdentifierLedger.pruning(savedSectionOrder)
            let desiredForUnmanaged = DesiredLayout.fromSavedSectionOrder(
                prunedSavedOrder,
                newItemsPlacement: newItemsPlacement
            )
            let placements = LayoutReconciler.unmanagedPlacementPlan(
                desired: desiredForUnmanaged,
                unmanagedUIDs: unmanagedUIDs,
                currentUIDs: Set(currentFlat)
            )

            // Per-uid decision trace. Shows which item was deemed
            // unmanaged and which placement strategy fired. Cheap
            // (only logs when unmanaged items exist) and the most
            // direct signal for triaging "why did X move?" reports.
            for uid in unmanagedUIDs {
                let placementSummary = switch placements[uid] {
                case let .saved(section, index)?:
                    "saved(section=\(section.logString), index=\(index))"
                case let .newItemAnchored(section, anchorUID, relation)?:
                    "newItemAnchored(section=\(section.logString), anchor=\(anchorUID), relation=\(String(describing: relation)))"
                case let .newItemDefault(section)?:
                    "newItemDefault(section=\(section.logString))"
                case nil:
                    "<no placement returned>"
                }
                // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
                // Changing this string breaks log-replay regression tests.
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: planUnmanagedPlacement \(uid) -> \(placementSummary)"
                )
            }

            let applied = LayoutReconciler.applyUnmanagedPlacementsToDesired(
                placements: placements,
                unmanagedUIDs: unmanagedUIDs,
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap,
                savedSectionOrder: prunedSavedOrder,
                controlUIDs: ControlUIDs(
                    visible: visibleCtrlUID,
                    hidden: hiddenCtrlUID,
                    alwaysHidden: ahCtrlUID
                )
            )
            desiredFiltered = applied.desiredFiltered
            sectionMap = applied.sectionMap

            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(unmanagedUIDs.count) unmanaged item(s) placed via planUnmanagedPlacement"
            )
        }

        // MARK: Phase 4: notch overflow rebalance

        // On notched displays, calculate available visible space and overflow
        // items that won't fit into the hidden section. The Thaw visible
        // control icon stays as the last visible item (nearest the hidden divider).
        // Gated by the user-facing "Enable menu bar item overflow" toggle in
        // Advanced Settings; when off, the saved profile layout is honoured
        // verbatim and items the notch would otherwise eject stay in visible.
        // The overflow gate reads the *actual* active menu bar screen — no
        // `NSScreen.main` fallback. Guessing a screen while the active one is
        // unknown risks budgeting against the wrong display, which is the
        // exact failure this gate prevents, so the gate fails closed instead.
        let activeMenuBarScreen = NSScreen.screenWithActiveMenuBar
        let activeIsMainDisplay = activeMenuBarScreen?.displayID == CGMainDisplayID()
        // A notched display that isn't the main menu bar display only hosts the
        // status items transiently (while it holds focus); ejecting there
        // strands profile items in hidden once focus returns to the main
        // screen. Log the skips so the field logs make the reason explicit.
        if appState.settings.advanced.enableMenuBarItemOverflow {
            if let screen = activeMenuBarScreen, screen.hasNotch, !activeIsMainDisplay {
                MenuBarItemManager.diagLog.debug(
                    "Notch overflow: skipping — active notched display \(screen.displayID) is a secondary "
                        + "(main display is \(CGMainDisplayID())); overflow only manages the main menu bar, "
                        + "so the saved layout is honoured verbatim"
                )
            } else if activeMenuBarScreen == nil {
                MenuBarItemManager.diagLog.debug(
                    "Notch overflow: skipping — active menu bar display is unknown; "
                        + "overflow does not guess a screen, so the saved layout is honoured verbatim"
                )
            }
        }
        if LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: appState.settings.advanced.enableMenuBarItemOverflow,
            activeScreenKnown: activeMenuBarScreen != nil,
            activeHasNotch: activeMenuBarScreen?.hasNotch ?? false,
            activeIsMainDisplay: activeIsMainDisplay
        ),
            let screen = activeMenuBarScreen,
            let notch = screen.frameOfNotch
        {
            let budget = Self.computeNotchOverflowBudget(
                items: items,
                screen: screen,
                notch: notch,
                spacingOffset: appState.spacingManager.offset
            )
            let rightBoundary = budget.rightBoundary
            var availableWidth = budget.availableWidth

            // Measure visible item widths from current bounds.
            let visibleUIDs = Array(desiredFiltered.prefix(while: { $0 != hiddenCtrlUID }))
            var uidWidths = [String: CGFloat]()
            for uid in visibleUIDs {
                if let item = items.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) }) {
                    uidWidths[uid] = item.bounds.width
                }
            }

            // Find the Thaw visible control icon, which must always stay visible.
            let visibleCtrlUID = items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier

            var chevronFootprint: CGFloat = 0
            if let visibleCtrlUID,
               let chevron = items.first(where: { $0.uniqueIdentifier == visibleCtrlUID }),
               chevron.bounds.minX >= notch.maxX,
               chevron.bounds.maxX <= rightBoundary
            {
                chevronFootprint = chevron.bounds.width
                availableWidth -= chevronFootprint
            }

            // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
            // Changing this string breaks log-replay regression tests.
            MenuBarItemManager.diagLog.debug(
                """
                Notch overflow budget: \(budget.logString) \
                visibleUIDs.count=\(visibleUIDs.count) chevronFootprint=\(chevronFootprint)
                """
            )

            let overflowResult = LayoutSolver.planNotchOverflow(
                desiredFiltered: desiredFiltered,
                unmanagedUIDs: unmanagedUIDs,
                controlUIDs: ControlUIDs(
                    visible: visibleCtrlUID,
                    hidden: hiddenCtrlUID,
                    alwaysHidden: ahCtrlUID
                ),
                sectionMap: sectionMap,
                uidWidths: uidWidths,
                availableWidth: availableWidth
            )

            // Replace (not union) so items freed by a previous overflow drop
            // out of the tracked set once they no longer overflow.
            notchOverflowEjectedUIDs = Set(overflowResult.overflowUIDs)

            if !overflowResult.overflowUIDs.isEmpty {
                // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
                // Changing this string breaks log-replay regression tests.
                MenuBarItemManager.diagLog.info(
                    "Profile layout: notch overflow; \(overflowResult.overflowUIDs.count) item(s) moved from visible to hidden"
                )
                desiredFiltered = overflowResult.updatedDesiredFiltered
                sectionMap = overflowResult.updatedSectionMap
            }
        } else if !notchOverflowEjectedUIDs.isEmpty {
            // Overflow doesn't apply here (no notch, or the feature is off):
            // this apply restores the saved layout verbatim, so the ejection
            // bookkeeping is obsolete.
            notchOverflowEjectedUIDs.removeAll()
        }

        // Re-check the divider geometry the saved-order dispatch already
        // refused, this time against the bounds this apply actually planned
        // from. applySavedLayout tests the cache cycle's snapshot, but Phase 2
        // re-reads every item from the Window Server, so the dividers can
        // collapse in between — and it is *these* bounds that classified the
        // sections above. A collapse means findSection misread the whole
        // hidden section as .visible, so the moves below would drag it to the
        // wrong side of the dividers and, by separating them, un-trip the
        // saveSectionOrder gate so the next cycle persists the damage (#868).
        // Refusing here leaves the bar untouched; the change gate re-fires via
        // layout divergence once the geometry recovers.
        //
        // Profile applies are exempt: their hidden count is a target, not a
        // description of the current bar, so a profile that fills a
        // currently-empty hidden section legitimately runs against dividers
        // that sit adjacent because nothing is between them yet.
        if case .savedOrder = source,
           !LayoutSolver.hiddenSectionHasRoom(
               hiddenControlItemMinX: controlItems.hidden.bounds.minX,
               alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX,
               savedHiddenItemCount: itemOrder[sectionKey(for: .hidden)]?.count ?? 0,
               liveHiddenItemCount: LayoutSolver.liveHiddenItemCount(
                   itemBounds: items.map(\.bounds),
                   hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                   alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX
               ),
               hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                   itemBounds: items.map(\.bounds),
                   hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                   screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
               )
           )
        {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping (savedOrder); hidden section has zero width between the dividers (hidden.minX=\(controlItems.hidden.bounds.minX) windowID=\(controlItems.hidden.windowID), alwaysHidden.maxX=\(controlItems.alwaysHidden?.bounds.maxX.description ?? "nil") windowID=\(controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
            clearProfileState(source: source, items: items)
            return
        }

        // Hide cursor for the entire profile apply to avoid visual jitter.
        // Capture in CoreGraphics space (top-left origin) so the Phase 7
        // restore can warp back directly — CGWarpMouseCursorPosition takes
        // CoreGraphics coordinates, matching what each inner move() already
        // uses. The previous AppKit capture flipped against the cursor's
        // *containing* screen instead of the primary, so on vertically
        // stacked or mixed-height multi-monitor setups the restore warped
        // the cursor onto the wrong display.
        //
        // The hide is released by `restoreCursor()` as soon as the last move
        // lands, *not* at function exit: everything after Phase 6 (control
        // item width restoration, the settling sleeps, the closing
        // getMenuBarItems pass, state persistence) moves no cursor, so
        // keeping it hidden there only lengthens the window in which the
        // user has no pointer. The `defer` is the balance for the early
        // return paths that never reach the end of Phase 6.
        let savedCursorPosition = MouseHelpers.locationCoreGraphics
        var cursorRestored = false
        func restoreCursor() {
            guard !cursorRestored else { return }
            cursorRestored = true
            // savedCursorPosition is already in CoreGraphics coordinates, so
            // warp back directly with no AppKit→CG flip (and no dependence on
            // which screen contains it).
            if let savedCursorPosition {
                MouseHelpers.restoreCursorPosition(to: savedCursorPosition)
            }
            MouseHelpers.showCursor()
        }
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer { restoreCursor() }

        // Spans the whole move sequence below (Phase 6). Lets
        // postMoveEvents skip its own per-item hide/show — this hide
        // already covers the sequence, and Phase 7 below restores the
        // cursor once at the end.
        isBulkApplyInProgress = true
        defer { isBulkApplyInProgress = false }

        // MARK: Phase 6: LCS execution

        // ── Sub-phase 0: Move control items to optimal boundary positions ──
        //
        // Moving a control item reassigns all items on either side to
        // different sections in a single move. Calculate whether moving
        // a control item is cheaper than moving individual items.
        var movedCount = 0
        var didAttemptHCtrl = false
        var canRepositionControlItems = controlItems.canRepositionControlItems
        // Moves this batch planned for an item that is still on the bar and
        // then did not enact. Any of these leaves the bar in an arrangement
        // nobody asked for, which the saveSectionOrder gate must not treat
        // as an order of record (#900).
        var unenactedMoveCount = 0

        /// Every abandon exits the same way: the abandoned remainder is one
        /// more unenacted move, the outcome feeds the circuit breaker, and
        /// in-flight profile state is torn down before the deferred cache
        /// refresh reconciles against reality. Callers with their own log
        /// line pass nil.
        func abandonApply(reason: String?, items: [MenuBarItem]) {
            unenactedMoveCount += 1
            if let reason {
                MenuBarItemManager.diagLog.warning(
                    "applyProfileLayout: \(reason); abandoning the remaining apply"
                )
            }
            recordBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)
            clearProfileState(source: source, items: items)
            scheduleDeferredCacheRefresh()
        }

        // Classify items into the two sets Phase 1 actually consults.
        // Read from the sectionByWindowID snapshot built earlier so the
        // classification here matches what the cache-log loop reported
        // above. Calling context.findSection again can return different
        // values for the same windowID if section.show()'s control-item
        // moves landed in between, which surfaces as an empty Phase 1
        // view of currently-occupied hidden / always-hidden sections.
        var currentVisibleSet = Set<String>()
        var currentHiddenSet = Set<String>()
        var currentAHSet = Set<String>()
        for item in items where isProfileItem(item) {
            switch sectionByWindowID[item.windowID] {
            case .visible:
                currentVisibleSet.insert(item.uniqueIdentifier)
            case .hidden:
                currentHiddenSet.insert(item.uniqueIdentifier)
            case .alwaysHidden:
                currentAHSet.insert(item.uniqueIdentifier)
            case nil:
                break
            }
        }

        let desiredHiddenSet = Set(itemOrder["hidden"] ?? [])
        let desiredAHSet = Set(itemOrder["alwaysHidden"] ?? [])
        // Logged for the log-replay harness so the desired visible set is
        // captured rather than inferred from current visible minus control
        // items and unresolved orphans. Also feeds the hidden-divider
        // boundary check below; the crossSectionMoves / totalSectionMismatch
        // arithmetic that follows still only crosses hidden and
        // always-hidden.
        let desiredVisibleSet = Set(itemOrder["visible"] ?? [])

        // Check if AH_ctrl needs to move: items changing between hidden↔alwaysHidden.
        let wrongInHidden = currentHiddenSet.subtracting(desiredHiddenSet).intersection(desiredAHSet)
        let wrongInAH = currentAHSet.subtracting(desiredAHSet).intersection(desiredHiddenSet)
        var crossSectionMoves = wrongInHidden.count + wrongInAH.count

        // Items that are in always-hidden currently but should be in
        // hidden per the profile (or vice versa), regardless of whether
        // they appear in BOTH desired sets. The previous
        // crossSectionMoves tally only counts items present in the
        // *opposite* desired section, which is too narrow: when the
        // profile has empty hidden/always-hidden, or when items have
        // simply drifted out of one section without an explicit
        // counterpart, the AH_ctrl move is still the right answer
        // because it's a single move that fixes the section boundary
        // for everything it crosses.
        let needsHiddenMove = currentAHSet.intersection(desiredHiddenSet)
        let needsAHMove = currentHiddenSet.intersection(desiredAHSet)
        var totalSectionMismatch = needsHiddenMove.count + needsAHMove.count

        // Items on the wrong side of H_ctrl. Both tallies above intersect
        // against currentHiddenSet / currentAHSet, so a bar whose hidden
        // divider has drifted past every managed item — leaving both sets
        // empty while the profile wants a full hidden section — scores
        // zero on both and falls through to the LCS. The LCS is blind to
        // it too: the dividers are stripped from its sequences, so a
        // divider-only divergence leaves current equal to desired and
        // plans no moves, and the apply reports "all items already in
        // correct positions" while the whole hidden section stays visible
        // (#879). One H_ctrl move fixes every one of them.
        let hiddenBoundaryMismatch = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: currentVisibleSet,
            currentHidden: currentHiddenSet,
            currentAlwaysHidden: currentAHSet,
            desiredVisible: desiredVisibleSet,
            desiredHidden: desiredHiddenSet,
            desiredAlwaysHidden: desiredAHSet
        )

        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: ahCtrlUID=\(ahCtrlUID ?? "nil"), crossSectionMoves=\(crossSectionMoves), totalSectionMismatch=\(totalSectionMismatch)"
        )
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: currentHidden=\(currentHiddenSet.sorted())"
        )
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: currentAH=\(currentAHSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: desiredHidden=\(desiredHiddenSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: desiredAH=\(desiredAHSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: desiredVisible=\(desiredVisibleSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: hiddenBoundaryMismatch=\(hiddenBoundaryMismatch)"
        )
        if hiddenBoundaryMismatch == 0 {
            parkedHiddenDividerMismatchStreak = 0
            didRecoverParkedHiddenDividerForCurrentMismatch = false
        }

        // ── Sub-phase 1: Move H_ctrl to the visible/hidden boundary ──
        //
        // Runs before the AH_ctrl placement so the always-hidden planning
        // below sees a divider pair that already brackets the right set of
        // items. Both dividers move by the same mechanism: one drag that
        // re-sections everything it crosses, which is why neither is left
        // to the per-item LCS pass.
        if hiddenBoundaryMismatch > 0, canRepositionControlItems, !Task.isCancelled {
            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(hiddenBoundaryMismatch) item(s) on the wrong side of H_ctrl, moving H_ctrl to the boundary"
            )

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var allFreshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &allFreshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                abandonApply(
                    reason: "control items degraded before moving H_ctrl",
                    items: allFreshItems
                )
                return
            }
            // CGDisplayBounds returns the Core Graphics display frame,
            // which is the coordinate space MenuBarItem.bounds and the
            // drag target points operate in. NSScreen.screens.map(\.frame)
            // is in AppKit's flipped coordinate space and can diverge for
            // mirrored or transitioning displays.
            let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            if case .savedOrder = source,
               recoverParkedHiddenDividerIfNeeded(
                   hiddenBoundaryMismatch: hiddenBoundaryMismatch,
                   hiddenControlItem: freshControl.hidden,
                   screenFrames: screenFrames
               )
            {
                // Keep the prior unfinished-batch arm intact without counting
                // the rebuild as another failed apply. That leaves the one
                // permitted retry available to verify the fresh divider.
                clearProfileState(source: source, items: allFreshItems)
                scheduleDeferredCacheRefresh()
                return
            }
            // Exclude items parked off-screen from the anchor candidate set.
            // A parked item's center falls on no screen; using it as the
            // H_ctrl drag anchor makes the move fail every retry — AppKit
            // snaps the divider back to its autosave position on mouse-up,
            // one on-screen flicker per attempt for the full 8-attempt
            // budget (#881: cursor seizure and icon storm). The per-item
            // LCS pass handles repositioning parked items onto the bar.
            let liveMovableUIDs = Set(
                allFreshItems.lazy.filter { item in
                    guard item.isMovable, isProfileItem(item) else { return false }
                    return LayoutSolver.isOnScreen(bounds: item.bounds, screenFrames: screenFrames)
                }.map(\.uniqueIdentifier)
            )
            let anchor = LayoutSolver.planHiddenDividerAnchor(
                desiredHidden: itemOrder["hidden"] ?? [],
                desiredVisible: itemOrder["visible"] ?? [],
                liveMovableUIDs: liveMovableUIDs
            )

            if let anchor {
                let hItem = freshControl.hidden
                let anchorUID = switch anchor {
                case let .rightOf(uid), let .leftOf(uid): uid
                }
                if let anchorItem = allFreshItems.first(where: { $0.uniqueIdentifier == anchorUID }) {
                    let dest: MoveDestination = switch anchor {
                    case .rightOf: .rightOfItem(anchorItem)
                    case .leftOf: .leftOfItem(anchorItem)
                    }
                    if !LayoutSolver.isOnScreen(bounds: hItem.bounds, screenFrames: screenFrames) {
                        // The divider itself has to be on screen for the drag
                        // to land. #881 excluded parked *anchors*; a parked
                        // H_ctrl fails the same way from the other side — the
                        // drag point is on screen so the owner accepts the
                        // events, but AppKit still snaps the divider back to
                        // its autosave position on mouse-up, and every attempt
                        // reports "events succeeded but item not at
                        // destination" for the full budget (#899). The
                        // per-item LCS pass below repositions items without
                        // needing the divider to travel.
                        unenactedMoveCount += 1
                        MenuBarItemManager.diagLog.warning(
                            "Profile layout: H_ctrl is parked offscreen (minX=\(hItem.bounds.minX)), skipping the boundary move"
                        )
                    } else if failureLedger.isUnderBackoff(for: hItem) {
                        // Same governance the per-item moves below already get.
                        // Without it a boundary move that cannot land is retried
                        // in full by every re-sort — eight drags a pass, a pass
                        // every few seconds, for as long as the mismatch stands.
                        // In #899 that ran until the user killed the app.
                        unenactedMoveCount += 1
                        MenuBarItemManager.diagLog.warning(
                            "Profile layout: H_ctrl under move-failure backoff, skipping"
                        )
                    } else {
                        MenuBarItemManager.diagLog.debug("Profile layout: moving H_ctrl → \(dest.logString)")
                        didAttemptHCtrl = true
                        do {
                            try await move(item: hItem, to: dest, skipInputPause: true)
                            movedCount += 1
                            failureLedger.recordSuccess(for: hItem)
                            try? await Task.sleep(for: .milliseconds(200))
                        } catch {
                            unenactedMoveCount += 1
                            // A move cancelled by a newer apply says nothing
                            // about the divider, and recording it would earn
                            // H_ctrl a backoff window it did not deserve —
                            // the same rule the LCS pass applies below.
                            if Task.isCancelled {
                                MenuBarItemManager.diagLog.debug(
                                    "Profile layout: H_ctrl move interrupted by a newer apply; leaving it unrecorded"
                                )
                            } else {
                                failureLedger.recordFailure(for: hItem, kind: Self.failureKind(of: error))
                                MenuBarItemManager.diagLog.error("Profile layout: failed to move H_ctrl: \(error)")
                            }
                        }
                    }
                }
            } else {
                // No live movable member on either side to anchor against;
                // the LCS pass below still runs against whatever ordering
                // divergence remains.
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: no anchor available for the H_ctrl boundary move"
                )
            }
        }

        // Moving H_ctrl changes the section of every item it crosses. The
        // snapshot used to decide the move is therefore stale at this point;
        // classify the post-move bounds again before deciding whether an
        // AH_ctrl move (and its per-item fallback) is still warranted.
        if didAttemptHCtrl {
            var postMoveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            postMoveItems.removeAll(where: \.isSystemClone)
            var postMoveItemsCopy = postMoveItems
            if let postMoveControl = ControlItemPair(
                items: &postMoveItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ) {
                canRepositionControlItems = postMoveControl.canRepositionControlItems
                guard canRepositionControlItems else {
                    abandonApply(
                        reason: "control items degraded to provisional AX-frame correlation after moving H_ctrl",
                        items: postMoveItems
                    )
                    return
                }
                var postMoveContext = CacheContext(
                    controlItems: postMoveControl,
                    displayID: Bridging.getActiveMenuBarDisplayID()
                )

                sectionByWindowID.removeAll(keepingCapacity: true)
                for item in postMoveItems where isProfileItem(item) {
                    if let section = postMoveContext.findSection(for: item) {
                        sectionByWindowID[item.windowID] = section
                    }
                }

                currentVisibleSet.removeAll(keepingCapacity: true)
                currentHiddenSet.removeAll(keepingCapacity: true)
                currentAHSet.removeAll(keepingCapacity: true)
                for item in postMoveItems where isProfileItem(item) {
                    switch sectionByWindowID[item.windowID] {
                    case .visible:
                        currentVisibleSet.insert(item.uniqueIdentifier)
                    case .hidden:
                        currentHiddenSet.insert(item.uniqueIdentifier)
                    case .alwaysHidden:
                        currentAHSet.insert(item.uniqueIdentifier)
                    case nil:
                        break
                    }
                }

                let postWrongInHidden = currentHiddenSet
                    .subtracting(desiredHiddenSet)
                    .intersection(desiredAHSet)
                let postWrongInAH = currentAHSet
                    .subtracting(desiredAHSet)
                    .intersection(desiredHiddenSet)
                crossSectionMoves = postWrongInHidden.count + postWrongInAH.count

                let postNeedsHiddenMove = currentAHSet.intersection(desiredHiddenSet)
                let postNeedsAHMove = currentHiddenSet.intersection(desiredAHSet)
                totalSectionMismatch = postNeedsHiddenMove.count + postNeedsAHMove.count

                MenuBarItemManager.diagLog.debug(
                    "Profile layout: post-H_ctrl classification crossSectionMoves=\(crossSectionMoves), totalSectionMismatch=\(totalSectionMismatch)"
                )
            } else {
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: could not reclassify sections after moving H_ctrl"
                )
                clearProfileState(source: source, items: postMoveItems)
                scheduleDeferredCacheRefresh()
                return
            }
        }

        if crossSectionMoves > 0 || totalSectionMismatch > 0,
           canRepositionControlItems,
           ahCtrlUID != nil
        {
            // Moving AH_ctrl to the correct position is 1 move that
            // fixes all hidden↔alwaysHidden assignments.
            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(crossSectionMoves) items would change hidden↔alwaysHidden, moving AH_ctrl instead"
            )

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var allFreshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &allFreshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems,
            let ahItem = freshControl.alwaysHidden
            else {
                abandonApply(
                    reason: "control items degraded before moving AH_ctrl",
                    items: allFreshItems
                )
                return
            }

            // Place AH_ctrl so that desired hidden items are to its
            // RIGHT and desired AH items are to its LEFT (screen coords).
            //
            // Anchor to the first desired hidden item (rightmost in
            // screen coords = index 0 in profile order). Place AH_ctrl
            // .leftOfItem(firstHidden) so it sits between the hidden
            // items and the AH items.
            //
            // If hidden is empty, AH_ctrl goes next to H_ctrl.
            // If AH is empty, AH_ctrl also goes next to H_ctrl (no
            // boundary needed).
            let desiredHiddenUIDs = itemOrder["hidden"] ?? []
            let dest: MoveDestination? = if let firstHiddenUID = desiredHiddenUIDs.first,
                                            let firstHidden = allFreshItems.first(where: { $0.uniqueIdentifier == firstHiddenUID && $0.isMovable })
            {
                // Place AH_ctrl to the LEFT of the rightmost hidden
                // item. This puts AH_ctrl between AH items and
                // hidden items.
                .leftOfItem(firstHidden)
            } else {
                // Hidden is empty; AH_ctrl goes next to H_ctrl.
                .leftOfItem(freshControl.hidden)
            }

            if let dest, !Task.isCancelled {
                MenuBarItemManager.diagLog.debug("Profile layout: moving AH_ctrl → \(dest.logString)")
                do {
                    try await move(item: ahItem, to: dest, skipInputPause: true)
                    movedCount += 1
                    try? await Task.sleep(for: .milliseconds(200))
                } catch {
                    unenactedMoveCount += 1
                    MenuBarItemManager.diagLog.error("Profile layout: failed to move AH_ctrl: \(error)")
                }
            }

            // Per-item cross-section fallback. The AH_ctrl move only
            // re-classifies items implicitly via its X position. When
            // the items destined for AH are currently RIGHT of items
            // destined for hidden (and vice versa); most commonly
            // after a fresh start where every managed item sits in
            // the hidden section; no single AH_ctrl placement can
            // split the two groups correctly. The move() no-op guard
            // can also cancel the AH_ctrl move outright when AH_ctrl
            // already sits adjacent to the chosen anchor. Either way,
            // a re-classification pass after the AH_ctrl attempt
            // tells us which items still need to cross the boundary,
            // and dragging them explicitly to .leftOfItem(AH_ctrl)
            // or .rightOfItem(AH_ctrl) puts them on the correct
            // side. The LCS within-section reorder pass below
            // handles intra-section ordering.
            let freshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var freshItemsCopy = freshItems
            if let freshControl = ControlItemPair(
                items: &freshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ) {
                guard freshControl.canRepositionControlItems else {
                    abandonApply(
                        reason: "control items degraded to provisional AX-frame correlation after moving AH_ctrl",
                        items: freshItems
                    )
                    return
                }
                guard let ahItem = freshControl.alwaysHidden else {
                    abandonApply(reason: nil, items: freshItems)
                    return
                }
                var verifyContext = CacheContext(
                    controlItems: freshControl,
                    displayID: Bridging.getActiveMenuBarDisplayID()
                )
                // Single classification pass, indexed by windowID so
                // multi-display duplicates of the same uniqueIdentifier
                // each keep their own section.
                var postSectionByWindowID: [CGWindowID: MenuBarSection.Name] = [:]
                for item in freshItems where isProfileItem(item) {
                    if let s = verifyContext.findSection(for: item) {
                        postSectionByWindowID[item.windowID] = s
                    }
                }
                var stillInHidden = Set<String>()
                var stillInAH = Set<String>()
                for item in freshItems where isProfileItem(item) {
                    switch postSectionByWindowID[item.windowID] {
                    case .hidden:
                        stillInHidden.insert(item.uniqueIdentifier)
                    case .alwaysHidden:
                        stillInAH.insert(item.uniqueIdentifier)
                    case .visible, .none:
                        break
                    }
                }
                let crossToAH = stillInHidden.intersection(desiredAHSet)
                let crossToHidden = stillInAH.intersection(desiredHiddenSet)

                if !crossToAH.isEmpty || !crossToHidden.isEmpty {
                    MenuBarItemManager.diagLog.debug(
                        "Profile layout: AH_ctrl placement left \(crossToAH.count) item(s) needing AH and \(crossToHidden.count) item(s) needing hidden, running per-item fallback"
                    )

                    // Move items destined for AH (currently in hidden)
                    // to the LEFT of AH_ctrl. Iterate in reverse
                    // profile order so the first item in
                    // itemOrder["alwaysHidden"] (rightmost in AH per
                    // profile convention, index 0) is moved last and
                    // therefore lands closest to AH_ctrl, matching
                    // the order LCS will leave it in.
                    let ahProfileOrder = itemOrder["alwaysHidden"] ?? []
                    let orderedCrossToAH = ahProfileOrder.reversed().filter { crossToAH.contains($0) }
                        + crossToAH.subtracting(ahProfileOrder).sorted()
                    for uid in orderedCrossToAH {
                        guard !Task.isCancelled else { break }
                        guard
                            let item = freshItems.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) })
                        else { continue }
                        do {
                            try await move(item: item, to: .leftOfItem(ahItem), skipInputPause: true)
                            movedCount += 1
                            try? await Task.sleep(for: .milliseconds(100))
                        } catch {
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.error(
                                "Profile layout: per-item move to AH failed for \(uid): \(error)"
                            )
                        }
                    }

                    // Move items destined for hidden (currently in AH)
                    // to the RIGHT of AH_ctrl. Iterate in profile
                    // order so itemOrder["hidden"] index 0 (rightmost
                    // in hidden = furthest from AH_ctrl) is moved
                    // first and gets pushed furthest right by
                    // subsequent moves.
                    let hiddenProfileOrder = itemOrder["hidden"] ?? []
                    let orderedCrossToHidden = hiddenProfileOrder.filter { crossToHidden.contains($0) }
                        + crossToHidden.subtracting(hiddenProfileOrder).sorted()
                    for uid in orderedCrossToHidden {
                        guard !Task.isCancelled else { break }
                        guard
                            let item = freshItems.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) })
                        else { continue }
                        do {
                            try await move(item: item, to: .rightOfItem(ahItem), skipInputPause: true)
                            movedCount += 1
                            try? await Task.sleep(for: .milliseconds(100))
                        } catch {
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.error(
                                "Profile layout: per-item move to hidden failed for \(uid): \(error)"
                            )
                        }
                    }
                }
            }
        }

        // ── Sub-phase 2: LCS for remaining item ordering ──
        //
        // Re-fetch items and rebuild sequences after control item moves
        // may have changed section assignments.
        if movedCount > 0 || didAttemptHCtrl {
            // Re-fetch items and rebuild section assignments after
            // the control item move changed section boundaries.
            items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var itemsCopy2 = items
            guard let freshControl = ControlItemPair(
                items: &itemsCopy2,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                MenuBarItemManager.diagLog.error("applyProfileLayout: lost control items after phase 1")
                // Abandoning here is itself an unenacted move: the LCS pass
                // never ran, and without the dividers the sections read back
                // from the bar are not the ones this apply was producing.
                abandonApply(reason: nil, items: items)
                return
            }

            var newContext = CacheContext(
                controlItems: freshControl,
                displayID: Bridging.getActiveMenuBarDisplayID()
            )

            currentFlat.removeAll()
            for sectionName in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
                let sectionItems = items.filter { item in
                    guard isProfileItem(item) else { return false }
                    return newContext.findSection(for: item) == sectionName
                }
                currentFlat.append(contentsOf: sectionItems.map(\.uniqueIdentifier))
            }
        }

        // Remove control items from sequences for LCS; they've been
        // handled in Phase 1. If Phase 1 moved a control item,
        // currentFlat was rebuilt so re-filter it.
        //
        // Source desiredFiltered (not desiredFlat): desiredFiltered
        // is the post-unmanaged-insert and post-notch-overflow
        // sequence. Using it lets the LCS planner consider
        // newly-detected items at their saved badge position
        // (so applying a profile relocates them to that spot
        // instead of leaving them wherever macOS detected them)
        // and respect notch-overflow's section reassignments.
        let currentNoControls = currentFlat.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }
        var desiredNoControls = desiredFiltered.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }

        // Optionally surrender ordering inside the concealed sections. The
        // relaxation runs on the desired sequence rather than on the
        // planned moves so the LCS itself sees those items as already in
        // place: filtering moves out afterwards would leave the surviving
        // moves anchored against items the plan assumed had shifted.
        let enforceConcealedOrder = (Defaults.object(forKey: .enforceConcealedSectionOrder) as? Bool)
            ?? Defaults.DefaultValue.enforceConcealedSectionOrder
        if !enforceConcealedOrder {
            desiredNoControls = LayoutSolver.relaxConcealedSectionOrder(
                desiredNoControls: desiredNoControls,
                currentNoControls: currentNoControls,
                sectionMap: sectionMap
            )
        }

        // The hidden and always-hidden dividers were filtered out of the
        // sequences above, but the chevron stays in: its position within
        // visible is part of the layout and is persisted. That also makes it
        // selectable as a move anchor, and anchoring a failing move on one of
        // Thaw's own dividers is what walks it across the bar (#924, #927).
        // Keep it in the order, bar it from being an anchor.
        let unanchorableUIDs = Set(
            items.lazy.filter(\.isControlItem).map(\.uniqueIdentifier)
        )

        let plannedMoves = LayoutSolver.planLCSMoveSequence(
            currentNoControls: currentNoControls,
            desiredNoControls: desiredNoControls,
            sectionMap: sectionMap,
            unanchorableUIDs: unanchorableUIDs,
            preferredMoveUIDs: Set(unmanagedUIDs)
        )

        guard !plannedMoves.isEmpty else {
            if movedCount > 0 {
                MenuBarItemManager.diagLog.info("Profile layout: completed with \(movedCount) control item move(s), no item reordering needed")
            } else {
                MenuBarItemManager.diagLog.info("Profile layout: all items already in correct positions")
            }
            // A control item that refused to move counts even when the LCS
            // pass has nothing left to plan: the divider is the boundary
            // that decides which section every item is in, so the sections
            // the cache reads back are not the ones this apply intended.
            recordBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)
            concludeProfileApplyWithoutMoves(source: source, items: items)
            scheduleDeferredCacheRefresh()
            return
        }

        MenuBarItemManager.diagLog.info(
            "Profile layout: \(plannedMoves.count) item move(s) needed (\(movedCount) control move(s) preceded)"
        )

        // Failures with no success between them; feeds moveBatchShouldAbandon.
        // Backoff skips do not count — they cost nothing and say nothing new.
        var consecutiveMoveFailures = 0

        for (plannedIndex, planned) in plannedMoves.enumerated() {
            // A cancelled sequence is one a newer apply replaced, and that
            // apply owns the arrangement from here on, so its own tally is
            // the one the gate should read. Leave the remainder uncounted.
            guard !Task.isCancelled else { break }

            if failureLedger.isUnderBackoff(key: planned.uid) {
                unenactedMoveCount += 1
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: \(planned.uid) under move-failure backoff, skipping"
                )
                continue
            }

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var freshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &freshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                // Losing the dividers abandons this move and every one
                // after it, so the whole remainder goes unenacted.
                unenactedMoveCount += plannedMoves.count - plannedIndex
                break
            }

            guard let item = allFreshItems.first(where: {
                $0.uniqueIdentifier == planned.uid && isProfileItem($0)
            }) else {
                continue
            }

            // Resolve the abstract destination against fresh items.
            // If the anchor item is missing (e.g. it disappeared
            // mid-sequence), the reconciler falls back to the
            // section boundary for the planned uid's target
            // section.
            let fallbackSection = sectionName(for: sectionMap[planned.uid] ?? "visible") ?? .visible
            let dest = LayoutReconciler.resolveDestination(
                planned.destination,
                items: allFreshItems,
                controlItems: freshControl,
                fallbackSection: fallbackSection
            )

            do {
                try await move(item: item, to: dest, skipInputPause: true)
                movedCount += 1
                consecutiveMoveFailures = 0
                failureLedger.recordSuccess(for: item)
                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                // The loop head's rule extends to a move that was in flight
                // when the cancellation arrived: the failure is the newer
                // apply's takeover, not the item's. Recording it would earn
                // an innocent item a backoff window and re-arm the save
                // withhold for a batch whose tally the newer apply owns
                // (#900's cannotComplete storms during overlapping applies).
                if Task.isCancelled {
                    MenuBarItemManager.diagLog.debug(
                        "Profile layout: move of \(planned.uid) interrupted by a newer apply; leaving it unrecorded"
                    )
                    break
                }
                unenactedMoveCount += 1
                consecutiveMoveFailures += 1
                failureLedger.recordFailure(for: item, kind: Self.failureKind(of: error))
                MenuBarItemManager.diagLog.error(
                    "Profile layout: failed to move \(planned.uid): \(error)"
                )
                if Self.moveBatchShouldAbandon(consecutiveFailures: consecutiveMoveFailures) {
                    unenactedMoveCount += plannedMoves.count - plannedIndex - 1
                    MenuBarItemManager.diagLog.warning(
                        "Profile layout: \(consecutiveMoveFailures) consecutive move failures, abandoning the remaining \(plannedMoves.count - plannedIndex - 1) move(s)"
                    )
                    break
                }
            }
        }

        MenuBarItemManager.diagLog.info("Profile layout: completed with \(movedCount) move(s)")

        recordBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)

        // Last move has landed; nothing below touches the cursor.
        restoreCursor()

        // MARK: Phase 7: finalize (cursor, snapshot, cache, UI refresh)

        // No-op on the paths that already restored at the end of Phase 6;
        // covers any branch that reaches here with the cursor still hidden.
        restoreCursor()

        // Re-fetch items after moves and update the snapshot so the
        // late-arrival detection doesn't re-trigger for items we just sorted.
        // Profile-only: the profile-sorted snapshot and
        // isApplyingProfileLayout flag are only meaningful when a
        // profile is active; the savedOrder source leaves them alone.
        items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // A cancelled profile apply (a newer apply replaced us via
        // applyProfile's layoutTask?.cancel()) must not commit anything:
        // roll back the in-memory profile state to the last committed
        // profile so the late-arrival re-sort path doesn't keep sorting
        // toward the cancelled spec, and skip the deferred cache refresh
        // (the apply that replaced us schedules its own at exit). The
        // rollback is token-guarded: if the newer apply has already
        // re-armed the state, it is left untouched.
        if Task.isCancelled, case .profile = source {
            restoreProfileStateAfterAbortedApply(token: applyToken)
            return
        }
        // Commit profile state to disk only if we weren't cancelled
        // mid-Phase-6. The in-loop cancellation guards break out of the
        // move loop but execution still flows into Phase 7; without
        // this check we'd persist a profile that was only partially
        // applied to the bar.
        if !Task.isCancelled {
            persistProfileStateOnSuccess(source: source)
        }
        clearProfileState(source: source, items: items)

        scheduleDeferredCacheRefresh()
    }

    /// Re-applies the user's saved menu-bar layout via the unified
    /// apply path. Builds the inputs that applyProfileLayout expects
    /// from savedSectionOrder and dispatches with source .savedOrder
    /// so the profile-only state arming (pinning
    /// overwrite, activeProfileLayout, isApplyingProfileLayout,
    /// late-arrival snapshot) is skipped while the shared discovery /
    /// unmanaged-placement / notch-overflow / execution machinery runs
    /// identically.
    ///
    /// Returns true if the bulk apply was dispatched (the body will
    /// drive its own follow-up cache cycle and the caller should not
    /// continue with the rest of its current cycle). Returns false
    /// when an entry guard rejects the call (no saved layout, profile
    /// apply in flight, cooldown active, no detected change to react
    /// to, no saved items currently present).
    /// Detects whether the current bar layout differs from
    /// `savedSectionOrder` in section membership. Returns true if any
    /// movable, hideable item whose baseID appears in the saved order
    /// is currently in a different section than where it was saved.
    ///
    /// Used as a secondary trigger for `applySavedLayout`: the windowID
    /// gate fires on app quit/relaunch, but ambient drift (third-party
    /// menu bar tools, Stage Manager toggles, macOS re-spawning the
    /// bar without churning windowIDs) leaves windowIDs intact while
    /// the layout drifts. This check catches that case so the bulk
    /// apply still reasserts the saved order.
    ///
    /// Lightweight by design: item bounds are read from the supplied
    /// items array (already populated by the caller's
    /// `getMenuBarItems` pass) rather than via per-item AX round-trips
    /// through `CacheContext`. Items that straddle a control-item
    /// boundary are ignored to avoid false positives during transient
    /// section show/hide animations. Exact instance identifiers participate
    /// directly; base-identifier fallback is allowed only when all saved
    /// instances for that base belong to one section, avoiding false positives
    /// from multi-instance items split across sections.
    /// Pure decision helper (#754) for whether a rebuild of the control
    /// items' underlying status items should be triggered, given the
    /// number of consecutive `ControlItemPair` lookup failures seen so far.
    /// Extracted so the escalation threshold can be unit-tested without a
    /// live `NSStatusItem`. The episode latch resets only after a successful
    /// lookup, so a permanent failure can trigger at most one rebuild.
    static nonisolated func shouldRebuildControlItems(
        consecutiveFailures: Int,
        alreadyRebuilt: Bool = false,
        threshold: Int = MenuBarItemManager.controlItemRebuildThreshold
    ) -> Bool {
        !alreadyRebuilt && consecutiveFailures >= threshold
    }

    /// The wait a change-detector recache must respect while control-item
    /// lookups keep failing, or `nil` while no backoff applies.
    ///
    /// A lookup failure leaves the window-ID snapshot uncommitted so the
    /// change detector re-fires — which is right for a transient race and
    /// wrong for a failure that is not going away: #933's process spent 27
    /// hours running a full recache every poll against a permanently
    /// missing control item. Below the rebuild threshold there is no wait,
    /// so startup transients recover at full speed; past it the wait
    /// doubles per failure and caps, keeping recovery automatic (a retry
    /// still runs every `maxDelay`) without the constant churn. Real
    /// changes are unaffected — event-driven recaches bypass the detector.
    static nonisolated func controlItemLookupRetryBackoff(
        consecutiveFailures: Int,
        threshold: Int = MenuBarItemManager.controlItemRebuildThreshold,
        baseDelay: Duration = .seconds(6),
        maxDelay: Duration = .seconds(60)
    ) -> Duration? {
        guard consecutiveFailures >= threshold else {
            return nil
        }
        // Cap the exponent before shifting so a long-running streak cannot
        // overflow; 1 << 6 * baseDelay already exceeds every realistic cap.
        let exponent = min(consecutiveFailures - threshold, 6)
        return min(baseDelay * (1 << exponent), maxDelay)
    }

    /// Whether a persistent zero-width hidden span has enough trustworthy
    /// observations to reset the hidden divider once for this episode.
    static nonisolated func shouldRecoverCollapsedHiddenSection(
        consecutiveCollapsedReadings: Int,
        alreadyRecovered: Bool = false,
        threshold: Int = MenuBarItemManager.hiddenSectionCollapseRecoveryThreshold
    ) -> Bool {
        !alreadyRecovered && consecutiveCollapsedReadings >= threshold
    }

    /// Whether repeated authoritative mismatch applies should reset a hidden
    /// divider that remains parked off every display.
    static nonisolated func shouldRecoverParkedHiddenDivider(
        consecutiveMismatchReadings: Int,
        alreadyRecovered: Bool = false,
        threshold: Int = MenuBarItemManager.parkedHiddenDividerRecoveryThreshold
    ) -> Bool {
        !alreadyRecovered && consecutiveMismatchReadings >= threshold
    }

    static nonisolated func baseIdentifier(forSavedIdentifier identifier: String) -> String {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return identifier }
        return "\(parts[0]):\(parts[1])"
    }

    static nonisolated func savedLayoutSectionLookup(
        savedSectionOrder: [String: [String]]
    ) -> (
        exact: [String: MenuBarSection.Name],
        unambiguousBase: [String: MenuBarSection.Name]
    ) {
        var exactSections = [String: Set<MenuBarSection.Name>]()
        var baseSections = [String: Set<MenuBarSection.Name>]()

        for (sectionKey, identifiers) in savedSectionOrder {
            guard let section = persistedSectionName(for: sectionKey) else { continue }
            for identifier in identifiers {
                exactSections[identifier, default: []].insert(section)
                baseSections[baseIdentifier(forSavedIdentifier: identifier), default: []].insert(section)
            }
        }

        let exact = exactSections.compactMapValues { sections in
            sections.count == 1 ? sections.first : nil
        }
        let unambiguousBase = baseSections.compactMapValues { sections in
            sections.count == 1 ? sections.first : nil
        }

        return (exact, unambiguousBase)
    }

    private func currentLayoutDivergesFromSaved(
        items: [MenuBarItem],
        controlItems: ControlItemPair
    ) -> Bool {
        // While the overflow feature is enabled and the active menu bar is
        // on a notched display, items the overflow rebalance ejected into
        // hidden diverge from the saved layout by design — reporting them
        // as divergent would re-dispatch a bulk apply every cache cycle.
        // The skip requires all three of: the feature still enabled (a
        // toggle-off must restore items promptly), a notched active display
        // (elsewhere the divergence is what triggers the restoring apply),
        // and the item actually sitting in hidden (an ejected item that
        // drifted to another section is genuine drift).
        let overflowSkipActive = (appState?.settings.advanced.enableMenuBarItemOverflow ?? false)
            && ((NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.hasNotch ?? false)

        return Self.layoutDivergesFromSaved(
            candidates: items
                .filter { !$0.isControlItem && $0.canBeHidden && $0.isMovable }
                .map { item in
                    DivergenceCandidate(
                        tagIdentifier: item.tag.tagIdentifier,
                        uniqueIdentifier: item.uniqueIdentifier,
                        bounds: item.bounds
                    )
                },
            sectionLookup: Self.savedLayoutSectionLookup(savedSectionOrder: savedSectionOrder),
            hiddenBounds: controlItems.hidden.bounds,
            alwaysHiddenBounds: controlItems.alwaysHidden?.bounds,
            overflowExemptUIDs: overflowSkipActive ? notchOverflowEjectedUIDs : [],
            activelyShownTags: Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))
        )
    }

    /// One item of a bar reading, reduced to what the divergence rule reads.
    struct DivergenceCandidate {
        let tagIdentifier: String
        let uniqueIdentifier: String
        let bounds: CGRect
    }

    /// Whether any item sits in a different section than `savedSectionOrder`
    /// records for it.
    ///
    /// This is the second of `applySavedLayout`'s two triggers, and the one
    /// that fires on ambient drift rather than on items coming and going. Both
    /// exemptions are passed in rather than derived so the rule stays pure:
    ///
    /// - `overflowExemptUIDs` carries the notch-overflow ejections, and is
    ///   empty unless the caller has already established that the feature is
    ///   on and the active display is notched.
    /// - `activelyShownTags` carries the items Thaw is temporarily showing. One
    ///   of those sits outside its saved section because Thaw put it there, and
    ///   it stays there until the rehide runs. Reading that as drift arms a
    ///   bulk apply whose only remaining brake is the open-menu probe, and a
    ///   false negative from the probe then drags the item home underneath the
    ///   menu the user just opened, tearing the menu down (#924). The rehide is
    ///   what returns these items; this pass has no business racing it.
    static nonisolated func layoutDivergesFromSaved(
        candidates: [DivergenceCandidate],
        sectionLookup: (exact: [String: MenuBarSection.Name], unambiguousBase: [String: MenuBarSection.Name]),
        hiddenBounds: CGRect,
        alwaysHiddenBounds: CGRect?,
        overflowExemptUIDs: Set<String>,
        activelyShownTags: Set<String>
    ) -> Bool {
        guard !sectionLookup.exact.isEmpty || !sectionLookup.unambiguousBase.isEmpty else { return false }

        let hiddenMinX = hiddenBounds.minX
        let hiddenMaxX = hiddenBounds.maxX
        let ahBounds = alwaysHiddenBounds

        for candidate in candidates {
            guard !activelyShownTags.contains(candidate.tagIdentifier) else { continue }
            let identifier = candidate.uniqueIdentifier
            let baseID = Self.baseIdentifier(forSavedIdentifier: identifier)
            guard let expectedSection = sectionLookup.exact[identifier]
                ?? sectionLookup.unambiguousBase[baseID]
            else {
                continue
            }

            let currentSection: MenuBarSection.Name? = if candidate.bounds.minX >= hiddenMaxX {
                .visible
            } else if let ahBounds, candidate.bounds.maxX <= ahBounds.minX {
                .alwaysHidden
            } else if let ahBounds, candidate.bounds.minX >= ahBounds.maxX, candidate.bounds.maxX <= hiddenMinX {
                .hidden
            } else if ahBounds == nil, candidate.bounds.maxX <= hiddenMinX {
                .hidden
            } else {
                nil
            }

            guard let currentSection else { continue }
            if currentSection == .hidden, overflowExemptUIDs.contains(identifier) {
                continue
            }
            if currentSection != expectedSection {
                return true
            }
        }
        return false
    }

    /// Decides whether a windowID-set difference between two cache cycles is a
    /// genuine change that should trigger a saved-layout re-apply, or merely an
    /// artifact of the active menu bar display switching to another screen.
    ///
    /// With "Displays have separate Spaces" enabled the menu bar follows the
    /// active display, so on a switch the previous display's item windows leave
    /// the active-space window list and read as "missing" even though the same
    /// logical items are still present on the other screen. Treating that as an
    /// item quit fires a full bulk re-sort on every cross-screen focus change,
    /// which on a notched display drifts items into always-hidden. A display
    /// switch is not a layout edit, so it must not advance the gate; the
    /// divergence check still runs and catches genuine section drift.
    static nonisolated func windowIDsChanged(
        previous: Set<CGWindowID>,
        current: Set<CGWindowID>,
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?
    ) -> Bool {
        // First cycle: no prior frame to diff against.
        guard !previous.isEmpty else { return false }
        // The active menu bar display moved to another screen. With separate
        // Spaces the prior display's windows are no longer on the active space,
        // so they read as missing even though the same logical items are still
        // present elsewhere. Not an item quit; do not advance the gate. Only
        // suppress when both displays are known and genuinely differ, so an
        // unknown display falls back to the plain disappearance signal.
        if let previousDisplayID, let currentDisplayID, previousDisplayID != currentDisplayID {
            return false
        }
        return !previous.isSubset(of: current)
    }

    /// Whether enough menu bar items are missing a resolved source PID that
    /// bulk-applying the saved layout would act on unmatchable identities.
    ///
    /// When the MenuBarItemService XPC connection fails (service cold start,
    /// connection interruption), most third-party items resolve to a nil
    /// sourcePID and collapse to ambiguous Control-Center-owned identifiers.
    /// A bulk apply dispatched in that state rearranges items it cannot match
    /// to the saved layout. A few system items (WiFi, Clock, BentoBox) and
    /// notch-hidden stragglers legitimately resolve to nil, so a minority
    /// share is normal; only a majority signals a resolution failure. The
    /// item-count floor keeps degenerate tiny sets from tripping the gate.
    static nonisolated func majorityOfSourcePIDsUnresolved(unresolvedCount: Int, itemCount: Int) -> Bool {
        itemCount >= 4 && unresolvedCount * 2 > itemCount
    }

    /// The profile's items that have appeared since the last profile sort,
    /// and so warrant a re-sort.
    ///
    /// Items with an unresolved `sourcePID` are excluded. `uniqueIdentifier`
    /// is derived from `sourcePID` via the tag's namespace, so an item whose
    /// PID did not resolve carries a fallback identity — it collapses into
    /// the Control Center host namespace or repeats its bundle ID as the
    /// title. Counting those as arrivals turns a resolution flap into a
    /// re-sort: the same item alternates between
    /// `eu.exelban.Stats:CPU_bar_chart` and `eu.exelban.Stats:eu.exelban.Stats:1`,
    /// and whichever form the last sort did not see reads as brand new.
    ///
    /// #881's reporter sat at 16–17 of 34 items unresolved for most of an
    /// hour — under ``majorityOfSourcePIDsUnresolved``'s bar, which needs a
    /// strict majority — so the applies ran and re-ran, each one landing its
    /// moves and each one re-arming the next.
    ///
    /// Excluding them costs nothing real: a late arrival is an app's item
    /// appearing after launch, and those resolve. The items that legitimately
    /// hold a nil PID (Wi-Fi, Clock, BentoBox) are always-present system
    /// items that never arrive late in the first place.
    static nonisolated func lateArrivingProfileIdentifiers(
        items: [MenuBarItem],
        profileIdentifiers: Set<String>,
        alreadySortedIdentifiers: Set<String>
    ) -> Set<String> {
        let identifiable = Set(
            items.lazy
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map(\.uniqueIdentifier)
        )
        return identifiable
            .intersection(profileIdentifiers)
            .subtracting(alreadySortedIdentifiers)
    }

    /// Narrows a saved order to the identifiers whose live item has a
    /// resolved sourcePID, for the early apply that runs while resolution is
    /// still in progress.
    ///
    /// Dropping an identifier from the desired order leaves the
    /// corresponding item untouched rather than mispositioned, because
    /// ``LayoutSolver/planLCSMoveSequence(currentNoControls:desiredNoControls:sectionMap:)``
    /// intersects current with desired and only moves identifiers present in
    /// both. Section keys are preserved even when they empty out, so the
    /// caller can tell an empty section from a missing one.
    ///
    /// The match is exact rather than base-identifier: a base match could
    /// admit an unresolved sibling of a resolved item (`Item-0:1` resolved,
    /// `Item-0:2` not), which is exactly what this restriction excludes.
    static nonisolated func savedOrderRestrictedToResolvedIdentities(
        savedSectionOrder: [String: [String]],
        resolvedIdentifiers: Set<String>
    ) -> [String: [String]] {
        savedSectionOrder.mapValues { identifiers in
            identifiers.filter(resolvedIdentifiers.contains)
        }
    }

    /// Decides whether a divergence observation should trigger the apply.
    ///
    /// A single divergent reading of `currentLayoutDivergesFromSaved` can be
    /// transient: an app activating with a wide application menu compresses
    /// or covers status items, shifting their bounds for the duration the
    /// menu is up. Reading that shift as "items in the wrong section" and
    /// immediately dispatching a bulk apply replays the whole layout and
    /// yanks the cursor around (#723) for geometry that resolves itself once
    /// the menu closes. Requiring the same divergence to be observed on two
    /// consecutive cache cycles filters out that transient case while still
    /// reacting promptly to genuine, persistent drift.
    ///
    /// - Parameters:
    ///   - divergedNow: The result of the current cycle's divergence check.
    ///   - pendingSince: The timestamp of a prior unconfirmed observation, if
    ///     one is armed.
    ///   - now: The current time.
    ///   - staleness: How long an armed observation remains eligible for
    ///     confirmation. A stale arm is discarded and treated as a fresh
    ///     first observation rather than confirmed, so an old, likely
    ///     unrelated observation can't confirm a much later one.
    /// - Returns: Whether this observation confirms the divergence (i.e.
    ///   should trigger the apply), and the pending-observation state to
    ///   carry forward to the next cycle.
    static nonisolated func confirmedDivergence(
        divergedNow: Bool,
        pendingSince: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        staleness: Duration = .seconds(30)
    ) -> (confirmed: Bool, newPendingSince: ContinuousClock.Instant?) {
        guard divergedNow else {
            return (false, nil)
        }
        guard let pendingSince else {
            // First observation: arm and defer this pass.
            return (false, now)
        }
        guard now - pendingSince <= staleness else {
            // The prior arm is too old to confirm against; discard it and
            // re-arm on this observation instead.
            return (false, now)
        }
        // Second consecutive observation within the staleness window: confirmed.
        return (true, nil)
    }

    /// Whether a bulk apply that left moves unenacted should still hold
    /// the saveSectionOrder gate shut.
    ///
    /// Time alone cannot make the partial result authoritative: allowing this
    /// latch to expire rewrites the saved order with the failed batch's own
    /// wreckage on the next cache change (#900). A clean apply clears the
    /// latch through `recordBulkApplyOutcome`; an explicit user move clears it
    /// through `recordExternalMoveOperation`.
    static nonisolated func unfinishedMoveBatchBlocksSave(
        observedAt: ContinuousClock.Instant?
    ) -> Bool {
        observedAt != nil
    }

    /// Whether an automatic apply may dispatch given how the recent ones
    /// ended.
    ///
    /// A batch that fails is allowed one retry: the failure can be
    /// circumstantial (a menu was up, an owner was mid-relaunch) and the
    /// retry is what the save-withhold window exists to make room for. A
    /// second consecutive unfinished batch means the bar itself is
    /// refusing the moves (#900's `cannotComplete` bar), and each further
    /// pass costs the user a hidden cursor for the length of the batch
    /// while landing yet another partial arrangement (#899). From then on
    /// dispatch is rationed to one attempt per cooldown rather than one
    /// per confirmed divergence, which is unbounded when the divergence
    /// is the failed batches' own.
    ///
    /// User-initiated applies (a profile switch) do not consult this gate:
    /// an explicit request is worth a fresh attempt regardless of history.
    /// They still feed the streak through `recordBulkApplyOutcome`, so a
    /// failed manual attempt does not hand the automatic path a clean
    /// slate.
    static nonisolated func automaticBulkApplyPermitted(
        consecutiveUnfinishedBatches: Int,
        lastUnfinishedBatchAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        maxConsecutive: Int = 2,
        cooldown: Duration = .seconds(60),
        hardCap: Int = 6
    ) -> Bool {
        if consecutiveUnfinishedBatches < maxConsecutive {
            return true
        }
        if consecutiveUnfinishedBatches >= hardCap {
            return false
        }
        guard let lastUnfinishedBatchAt else {
            return true
        }
        return now - lastUnfinishedBatchAt >= cooldown
    }

    /// Whether a move batch should abandon its remaining moves after a run
    /// of consecutive failures.
    ///
    /// The cursor stays hidden for the whole batch, and a failing move is
    /// the expensive kind: it burns its full attempt budget, each attempt
    /// with an event timeout and a settle wait, before throwing. On the
    /// #900 bar one pass logged 15 such failures — minutes of a dead
    /// pointer (#899) spent confirming the same conclusion. Three in a row
    /// with no success between them is that conclusion: the bar is
    /// refusing synthetic drags right now, and the items still queued will
    /// fare no better. The abandoned remainder counts as unenacted, so the
    /// arrangement is withheld from the saved order like any other partial
    /// batch.
    ///
    /// Consecutive, not total: successes reset the run, so a long batch
    /// with scattered failures — each already filed with the ledger for
    /// per-item backoff — still completes.
    static nonisolated func moveBatchShouldAbandon(
        consecutiveFailures: Int,
        threshold: Int = 3
    ) -> Bool {
        consecutiveFailures >= threshold
    }

    /// The idle window an automatic bulk apply should wait for, or `nil`
    /// when the gate is switched off.
    ///
    /// Splitting the sanitising out of the wait loop keeps the two things
    /// that can be got wrong — "is the gate on" and "when does waiting
    /// stop" — testable without a clock. A non-positive threshold is the
    /// off switch rather than a zero-length window, so the caller can skip
    /// the loop entirely; a negative cap is clamped rather than rejected,
    /// because a `defaults write` typo should degrade to "don't wait", not
    /// to a batch that never starts.
    static nonisolated func bulkApplyIdleWindow(
        thresholdMs: Int,
        capMs: Int
    ) -> (threshold: Duration, cap: Duration)? {
        guard thresholdMs > 0 else { return nil }
        return (.milliseconds(thresholdMs), .milliseconds(max(0, capMs)))
    }

    /// Whether an automatic bulk apply has waited long enough to start
    /// issuing moves.
    ///
    /// Two exits, and the second is the important one: the wait defers a
    /// batch, it never cancels it. A user who never stops moving the mouse
    /// would otherwise starve the apply indefinitely, and a saved layout
    /// that is never restored is a worse failure than one restored while
    /// the pointer is in motion — the per-move pause still applies once the
    /// batch is under way.
    static nonisolated func bulkApplyIdleWaitConcluded(
        userHasPausedInput: Bool,
        elapsed: Duration,
        cap: Duration
    ) -> Bool {
        userHasPausedInput || elapsed >= cap
    }

    func applySavedLayout(
        items: [MenuBarItem],
        previousWindowIDs: [CGWindowID],
        controlItems: ControlItemPair,
        previousDisplayID: CGDirectDisplayID? = nil,
        currentDisplayID: CGDirectDisplayID? = nil,
        previousCCGenericWindowIDs: Set<CGWindowID> = [],
        bypassMoveCooldown: Bool = false,
        resolvedIdentitiesOnly: Bool = false
    ) async -> Bool {
        // Each guard logs a distinct reason so a "Thaw stopped
        // restoring my layout" bug report can be diagnosed from the
        // first set of logs. Order is significant: the cheap state
        // checks run first; window-ID/tag inspection runs last so we
        // don't compute sets when an earlier guard would reject anyway.
        guard !savedSectionOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, savedSectionOrder is empty")
            return false
        }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping for provisional AX-frame correlation"
            )
            return false
        }
        guard !suppressNextNewLeftmostItemRelocation else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, suppressNextNewLeftmostItemRelocation armed")
            return false
        }
        // applyProfileLayout owns the in-flight layout while it's
        // running; a concurrent savedOrder apply would fight it.
        guard !isApplyingProfileLayout else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, profile apply in flight")
            return false
        }
        // 5 s cooldown after a recent move (same value the legacy
        // restoreItemsToSavedSections used) prevents cascading
        // re-applies when many apps relaunch in quick succession.
        //
        // bypassMoveCooldown opts the launch restore out: that pass runs
        // immediately after relocateNewLeftmostItems has moved our own
        // control item, so the cooldown it would observe is one this same
        // chain just stamped. There is no later retry, so honouring the
        // cooldown here means the saved layout is never applied at all and
        // the drifted arrangement gets persisted over it (#881).
        guard bypassMoveCooldown || !lastMoveOperationOccurred(within: .seconds(5)) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, within 5s move cooldown")
            return false
        }
        // Not bypassable: bypassMoveCooldown exempts a caller from a
        // cooldown its own chain just stamped, whereas this gate reads a
        // history of applies that did not complete. A launch restore is
        // unaffected anyway — the streak is session state and starts at 0.
        guard isAutomaticBulkApplyPermitted(caller: "applySavedLayout") else {
            return false
        }

        // Trigger detection. The cache cycle calls this on every tick;
        // without a change gate we would run a full bulk apply every
        // ~5 s indefinitely. Two independent signals advance past the
        // gate:
        //
        // 1. windowIDsChanged: a previous windowID is missing from the
        //    current set, i.e., an item disappeared. Covers app-quit
        //    and app-relaunch. Pure additions are owned by
        //    relocateNewLeftmostItems, not this path. WindowID
        //    recycling (same WID, different item) is uncovered.
        //    The previous-set-empty escape handles first-cycle startup
        //    where there's no prior frame to diff against.
        //
        // 2. layoutDiverged: at least one saved item is currently in a
        //    different section than savedSectionOrder records. Catches
        //    ambient drift (third-party tools repositioning icons,
        //    Stage Manager toggles, screen lock/unlock cycles, macOS
        //    re-spawning the bar) where windowIDs stay stable while
        //    sections shift. Also catches cold-boot for non-profile
        //    users, where the first cycle has previousWindowIDs empty
        //    but the bar is in macOS-default order rather than saved.
        //
        // Divergence is computed lazily: only consulted when
        // windowIDsChanged didn't already advance the gate, so the
        // happy path on app quit/relaunch pays nothing.
        //
        // A single divergent reading is required to be *stable* across two
        // consecutive cache cycles before it advances the gate (#723): an
        // app activating with a wide application menu can transiently
        // compress or cover status items, which currentLayoutDivergesFromSaved
        // reads as items in the wrong section even though the geometry
        // reverts once the menu closes. windowIDsChanged is a direct,
        // trustworthy signal (an item genuinely disappeared) and is not
        // subject to this confirmation — it stays immediate and never
        // arms/consumes the pending-divergence state below.
        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousWindowIDs)
        // Control-Center-generic (`Item-N`) windows churn windowIDs while
        // the visible item count stays stable (Live Activities, transient
        // CC widgets). Their disappearance is not an app quit/relaunch and
        // must not dispatch a bulk apply, or every churn cycle replays the
        // whole layout and hijacks the cursor (#736). Their identities are
        // never part of a saved layout (saveSectionOrder excludes them), so
        // ignoring them here can't miss a restorable change.
        let windowIDsChanged = Self.windowIDsChanged(
            previous: previousWindowIDSet.subtracting(previousCCGenericWindowIDs),
            current: currentWindowIDSet,
            previousDisplayID: previousDisplayID,
            currentDisplayID: currentDisplayID
        )
        let layoutDiverged: Bool
        if windowIDsChanged {
            layoutDiverged = false
        } else {
            let divergedNow = currentLayoutDivergesFromSaved(items: items, controlItems: controlItems)
            let now = ContinuousClock.now
            let decision = Self.confirmedDivergence(
                divergedNow: divergedNow,
                pendingSince: pendingDivergenceObservedAt,
                now: now
            )
            pendingDivergenceObservedAt = decision.newPendingSince
            if divergedNow, !decision.confirmed {
                MenuBarItemManager.diagLog.debug("applySavedLayout: divergence observed, awaiting confirmation on next cycle")
            } else if decision.confirmed {
                MenuBarItemManager.diagLog.debug("applySavedLayout: divergence confirmed on second consecutive cycle")
            }
            layoutDiverged = decision.confirmed
        }
        guard windowIDsChanged || layoutDiverged else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no windowID change and saved layout matches current")
            return false
        }
        // A windowID-change apply proceeds regardless of any pending
        // divergence arm; discard the stale arm so it can't spuriously
        // confirm on a later, unrelated cycle once the bar has settled.
        pendingDivergenceObservedAt = nil

        // Skip the bulk apply while the majority of items have no resolved
        // sourcePID — mirrors relocateNewLeftmostItems's unresolved-sourcePID
        // noop.
        //
        // resolvedIdentitiesOnly callers are exempt: they deliberately run
        // while most sourcePIDs are still unresolved, and confine the apply
        // to the identities that *are* resolved (see effectiveSavedOrder).
        let unresolvedSourcePIDCount = items.count { $0.sourcePID == nil }
        if !resolvedIdentitiesOnly,
           Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedSourcePIDCount, itemCount: items.count)
        {
            MenuBarItemManager.diagLog.info(
                "applySavedLayout: skipping, \(unresolvedSourcePIDCount)/\(items.count) items have unresolved sourcePIDs (XPC resolution likely failed)"
            )
            return false
        }

        // Never drag items while a menu bar item menu is tracking — a synthetic
        // Cmd-drag would tear down the user's interaction (Wi-Fi picker, input
        // methods). The change gate stays armed, so the next cache cycle retries.
        if await isAnyMenuBarItemMenuOpen() {
            MenuBarItemManager.diagLog.info("applySavedLayout: skipping, a menu bar item menu is open")
            return false
        }

        // Saved-item intersection: skip if none of the saved items are
        // currently present. Prefer exact namespace/title/instance matches;
        // fall back to namespace/title only when every saved instance for that
        // base belongs to one section. This avoids treating ambiguous
        // multi-instance Control Center items (for example Item-0:1 visible,
        // Item-0:2 hidden) as evidence that the saved layout is present and
        // needs a bulk apply.
        let sectionLookup = Self.savedLayoutSectionLookup(savedSectionOrder: savedSectionOrder)
        let currentIdentifiers = Set(items.map(\.uniqueIdentifier))
        let currentBaseIdentifiers = Set(items.map { Self.baseIdentifier(forSavedIdentifier: $0.uniqueIdentifier) })
        guard !Set(sectionLookup.exact.keys).isDisjoint(with: currentIdentifiers)
            || !Set(sectionLookup.unambiguousBase.keys).isDisjoint(with: currentBaseIdentifiers)
        else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no saved items currently present")
            return false
        }

        // The desired order this apply will actually enact.
        //
        // Under resolvedIdentitiesOnly the saved order is narrowed to
        // identifiers whose live item has a resolved sourcePID, so an item
        // we cannot yet identify is never a move target. That is safe
        // because planLCSMoveSequence intersects current with desired and
        // only moves identifiers present in both — dropping one from
        // desired leaves it untouched rather than mispositioned. The
        // settling-end pass then runs unrestricted and, because LCS keeps
        // whatever is already in place, moves only the remainder.
        //
        // Match is exact on uniqueIdentifier: base-identifier fallback
        // could admit an unresolved sibling of a resolved item, which is
        // precisely the item this restriction exists to exclude.
        let effectiveSavedOrder: [String: [String]]
        if resolvedIdentitiesOnly {
            effectiveSavedOrder = Self.savedOrderRestrictedToResolvedIdentities(
                savedSectionOrder: savedSectionOrder,
                resolvedIdentifiers: Set(
                    items.lazy.filter { $0.sourcePID != nil }.map(\.uniqueIdentifier)
                )
            )
            guard effectiveSavedOrder.values.contains(where: { !$0.isEmpty }) else {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, no saved items have resolved identities yet"
                )
                return false
            }
        } else {
            effectiveSavedOrder = savedSectionOrder
        }

        // Build itemSectionMap from the effective order. Each identifier
        // points back at its persisted section key.
        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in effectiveSavedOrder {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }

        let trigger = if windowIDsChanged {
            "windowID change"
        } else if resolvedIdentitiesOnly {
            "layout divergence, resolved identities only"
        } else {
            "layout divergence"
        }

        // The apply must refuse the same geometry the save path refuses to
        // persist. When the dividers have collapsed onto one coordinate,
        // findSection has already misread every hidden item, so the section
        // mismatch computed below is an artifact of the collapse, not drift
        // to correct — dispatching here drags the whole hidden section to
        // the wrong side of the dividers with synthetic mouse events. Worse,
        // the drags separate the dividers, so the saveSectionOrder gate that
        // caught the collapse a cycle earlier passes on the next cycle and
        // persists the damage (#868). Refusing keeps the bar untouched; the
        // change gate re-fires via layout divergence once the geometry
        // recovers, and the apply then runs against a trustworthy reading.
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: controlItems.hidden.bounds.minX,
            alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX,
            savedHiddenItemCount: effectiveSavedOrder[sectionKey(for: .hidden)]?.count ?? 0,
            // Read off the bar this apply was handed, not the cache: this path
            // is entered with `items` and runs before any recache.
            liveHiddenItemCount: LayoutSolver.liveHiddenItemCount(
                itemBounds: items.map(\.bounds),
                hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX
            ),
            hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                itemBounds: items.map(\.bounds),
                hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            )
        )
        guard hiddenSectionHasRoom else {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); hidden section has zero width between the dividers (hidden.minX=\(controlItems.hidden.bounds.minX) windowID=\(controlItems.hidden.windowID), alwaysHidden.maxX=\(controlItems.alwaysHidden?.bounds.maxX.description ?? "nil") windowID=\(controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
            return false
        }

        // Display-spread gate. While the active menu bar relocates to another
        // display macOS migrates the status item windows between screens
        // asynchronously, so the items transiently straddle two displays. A
        // bulk apply dispatched now resolves each item's move against whichever
        // display its window currently occupies and cannot converge, stranding
        // items on the wrong screen where they read as un-hidden. Skip; a later
        // tick retries once the items collapse back onto the active display.
        // Frames come from CGDisplayBounds so they share the top-left origin
        // coordinate space of the item bounds.
        //
        // Only items right of the hidden divider feed the gate. Parked hidden
        // and always-hidden items sit at arbitrary negative x, which belongs to
        // a display positioned left of the main one, and including them reports
        // a spread on a settled layout for as long as that display is
        // connected. This gate and the saveSectionOrder one are a pair: both
        // must judge the same geometry, or the layout gets applied from an
        // order that can no longer be saved.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        let unparkedCenters = items
            .filter { $0.bounds.minX >= controlItems.hidden.bounds.minX }
            .map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
        if LayoutSolver.itemsSpanMultipleDisplays(itemCenters: unparkedCenters, screenFrames: screenFrames) {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); menu bar items span multiple displays (relocation in progress)"
            )
            return false
        }

        MenuBarItemManager.diagLog.info("applySavedLayout: dispatching bulk apply (\(trigger))")

        // The shared body uses itemOrder as the per-section ordered
        // identifier list, which is structurally identical to
        // savedSectionOrder. Pass the saved order through unchanged.
        // Pinning is preserved from existing state, not derived from
        // savedSectionOrder (savedSectionOrder has no pinning concept).
        await applyProfileLayout(
            pinnedHidden: pinnedHiddenBundleIDs,
            pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
            sectionOrder: effectiveSavedOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: effectiveSavedOrder,
            source: .savedOrder,
            automatic: true
        )
        return true
    }

    /// Restores items that are stuck in a "blocked" state (positioned at x=-1)
    /// back to the visible section. This is called when the app is terminating
    /// to prevent items from being permanently stuck in macOS's Control Center preferences.
    /// Only items at x=-1 are restored; normally hidden items are left as-is.
    ///
    /// - Returns: The number of items that failed to move.
    @MainActor
    func restoreBlockedItemsToVisible() async -> Int {
        MenuBarItemManager.diagLog.info("Checking for blocked items (x=-1) to restore before app termination")

        guard let appState else {
            MenuBarItemManager.diagLog.error("Cannot restore items: missing appState")
            return 0
        }

        // Get current items
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        // Find items that are blocked (at x=-1)
        let blockedItems = items.filter { item in
            guard item.isMovable, !item.isControlItem else { return false }
            let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
            return bounds.origin.x == -1
        }

        guard !blockedItems.isEmpty else {
            MenuBarItemManager.diagLog.debug("No blocked items found - skipping restoration")
            return 0
        }

        MenuBarItemManager.diagLog.warning("Found \(blockedItems.count) blocked items at x=-1, attempting to restore")

        // Get window IDs from ControlItem objects
        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        // Create ControlItemPair to get MenuBarItem representations
        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenWID
        ), controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.error("Cannot restore items: unable to find hidden control item")
            return blockedItems.count
        }

        var failedMoves = 0

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // Move blocked items to the right of the hidden control item (visible section)
        for item in blockedItems {
            do {
                try await move(
                    item: item,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true,
                    watchdogTimeout: Self.layoutWatchdogTimeout
                )
                MenuBarItemManager.diagLog.info("Successfully restored blocked item \(item.logString) to visible section")
            } catch {
                failedMoves += 1
                MenuBarItemManager.diagLog.error("Failed to restore blocked item \(item.logString): \(error)")
            }
        }

        MenuBarItemManager.diagLog.info("Restore completed: \(blockedItems.count - failedMoves)/\(blockedItems.count) blocked items restored")

        // Give macOS a moment to settle
        try? await Task.sleep(for: .milliseconds(200))

        return failedMoves
    }
}

// MARK: - Notch Overflow

extension MenuBarItemManager {
    /// The measured beside-notch width budget for the visible section.
    struct NotchOverflowBudget {
        /// Usable width between the notch gap and the right boundary, with the
        /// footprint of unmanageable items already subtracted.
        var availableWidth: CGFloat
        /// The left edge of Control Center, or the screen's right edge when
        /// Control Center cannot be located.
        var rightBoundary: CGFloat

        var logString: String
    }

    /// Whether an item participates in the beside-notch budget as a managed
    /// item — i.e. Thaw can move it out of the way. Everything else (the clock,
    /// immovable system extras) is charged against the budget as fixed
    /// furniture instead.
    static nonisolated func isBudgetedManagedItem(_ item: MenuBarItem) -> Bool {
        (item.canBeHidden || item.tag == .visibleControlItem) && item.isMovable
    }

    /// Measures how much width the visible section actually has to the right of
    /// the notch.
    ///
    /// Shared by the profile-apply overflow phase and the continuous rebalance
    /// pass so both decide against identical geometry. Reads live item bounds
    /// only; the eject decision itself lives in
    /// ``LayoutSolver/planNotchOverflow(desiredFiltered:unmanagedUIDs:controlUIDs:sectionMap:uidWidths:availableWidth:)``.
    static func computeNotchOverflowBudget(
        items: [MenuBarItem],
        screen: NSScreen,
        notch: CGRect,
        spacingOffset: Int
    ) -> NotchOverflowBudget {
        let notchGap = MenuBarSection.notchGap
        // Available space: from notch gap to Control Center's left edge.
        let ccItem = items.first(where: { $0.tag == .controlCenter })
        let rightBoundary = ccItem.map(\.bounds.minX) ?? screen.frame.maxX
        var availableWidth = rightBoundary - (notch.maxX + notchGap)

        // NSStatusItemSpacing is recorded here for diagnostic logging
        // only. macOS bakes the spacing into each status item's frame
        // (verified empirically: item.bounds.width grows 1:1 with the
        // spacing value), so item.bounds.width and the Control Center
        // item's bounds.minX already account for it. Subtracting a
        // separate (count - 1) * spacing gap here used to double-count
        // the spacing and ejected items into hidden when the bar still
        // had room, most visibly at the macOS default of 16.
        let userSpacing = CGFloat(max(0, 16 + spacingOffset))

        // Subtract the layout footprint of items that occupy the visible area
        // but that Thaw cannot move: the Clock / date-time display, BentoBox
        // tray on systems that have it, and any immovable accessibility
        // extras. They take real estate in the same way managed items do but
        // are filtered out of the planner's uid list and would otherwise be
        // invisible to the budget check.
        // Transient system indicators (screen-recording AudioVideoModule,
        // FaceTime call indicator, ScreenCaptureUI overlay) appear and
        // disappear based on system events. Excluding them from the
        // budget keeps the overflow decision tied to the user's
        // permanent layout; otherwise, applying a profile while a
        // recording or call indicator is showing temporarily forces
        // a managed item out of visible, and that item won't come
        // back when the indicator goes away.
        let transientTags: [MenuBarItemTag] = [
            .audioVideoModule,
            .faceTime,
            .screenCaptureUI,
            .gameMode,
        ]
        var unmanagedFootprint: CGFloat = 0
        var unmanagedCount = 0
        var unmanagedBreakdown = [String]()
        for item in items where !isBudgetedManagedItem(item) {
            guard item.bounds.minX >= notch.maxX,
                  item.bounds.maxX <= rightBoundary
            else { continue }
            if transientTags.contains(where: {
                $0.namespace == item.tag.namespace && $0.title == item.tag.title
            }) || item.isTransientControlCenterItem || item.hasProvisionalIdentity {
                continue
            }
            unmanagedFootprint += item.bounds.width
            unmanagedCount += 1
            unmanagedBreakdown.append("\(item.uniqueIdentifier)=\(item.bounds.width)")
        }
        availableWidth -= unmanagedFootprint

        return NotchOverflowBudget(
            availableWidth: availableWidth,
            rightBoundary: rightBoundary,
            logString: """
            screen.maxX=\(screen.frame.maxX) notch=[\(notch.minX)…\(notch.maxX)] \
            rightBoundary=\(rightBoundary) availableWidth=\(availableWidth) \
            userSpacing=\(userSpacing) unmanagedCount=\(unmanagedCount) \
            unmanagedFootprint=\(unmanagedFootprint) \
            unmanagedBreakdown=[\(unmanagedBreakdown.joined(separator: ", "))]
            """
        )
    }

    /// Minimum interval between two continuous rebalance passes.
    ///
    /// A pass moves items, which recaches, which re-enters this path. The
    /// cooldown keeps that from becoming a loop when the geometry is right at
    /// the budget boundary and an ejected item's departure frees exactly enough
    /// room for the planner to want it back.
    private static let notchRebalanceCooldown: TimeInterval = 3

    /// Ejects items that no longer fit beside the notch into the hidden
    /// section, independently of any profile.
    ///
    /// Overflow used to exist only as a phase of ``applyProfileLayout``, so an
    /// item that arrived while no profile was active — or that belonged to no
    /// profile — was never ejected and simply grew the visible row across the
    /// notch. This pass runs off the cache-update tick instead, so a notched
    /// main display keeps its visible row inside the beside-notch budget at all
    /// times.
    ///
    /// When a profile *is* active the pass defers to
    /// ``scheduleProfileResort()``: a full apply re-runs the same planner while
    /// also honouring the saved order, so ejecting here would fight it. That
    /// handoff waits until the planner has actually found overflow — a pass
    /// with nothing to do must return without arming anything, or it drives
    /// the apply on every cache tick forever (#881).
    func rebalanceNotchOverflowIfNeeded(items: [MenuBarItem], controlItems: ControlItemPair) async {
        guard let appState else { return }
        guard appState.settings.advanced.enableMenuBarItemOverflow else { return }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "Notch overflow rebalance: skipping for provisional AX-frame correlation"
            )
            return
        }

        // Never fight another mover. Each of these owns the layout while it
        // runs and re-drives the cache when it finishes, so the next tick
        // picks up any overflow that is still outstanding.
        guard !isApplyingProfileLayout,
              !isRestoringItemOrder,
              !isInStartupSettling,
              !isBulkApplyInProgress
        else { return }

        // A temporarily-shown item is deliberately parked in visible for as
        // long as the user is interacting with it. Ejecting it would cancel
        // the reveal the user just asked for.
        guard temporarilyShownItemContexts.isEmpty else { return }

        // If the bar just refused synthetic drags in a profile apply, the
        // rebalance's own drags will fare no better — and each eject is a
        // full move() with its own cursor hijack. Without this gate the
        // rebalance fires on the very next cache tick after a failed apply,
        // trying 10–17 items one by one, each failing the same way, for tens
        // of seconds of dead pointer (#881, #907). The per-item failure-ledger
        // backoff cannot help because the rebalance's items are typically
        // different from the ones that failed in the batch.
        guard isAutomaticBulkApplyPermitted(caller: "Notch overflow rebalance", quietly: true) else {
            return
        }

        let activeMenuBarScreen = NSScreen.screenWithActiveMenuBar
        guard LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: activeMenuBarScreen != nil,
            activeHasNotch: activeMenuBarScreen?.hasNotch ?? false,
            activeIsMainDisplay: activeMenuBarScreen?.displayID == CGMainDisplayID()
        ),
            let screen = activeMenuBarScreen,
            let notch = screen.frameOfNotch
        else { return }

        // Mid-relocation between displays the item bounds straddle two screens
        // and the budget cannot be trusted. Same guard the persist path uses,
        // and the same input rule: only unparked items may feed it. Items left
        // of the hidden divider are parked at arbitrary negative x, which lands
        // inside a display positioned to the left of the main one and reads as
        // a permanent spread.
        //
        // The divider comes from the caller's ControlItemPair rather than a
        // lookup in items. Building that pair strips the hidden and
        // always-hidden control items out of the array it is given, and the
        // caller hands us that same stripped array, so searching it for
        // .hiddenControlItem finds nothing and the filter would silently pass
        // every parked item straight through.
        //
        // Frames come from CGDisplayBounds, not NSScreen.frame, for the same
        // reason as the other two call sites: item bounds are CoreGraphics
        // (top-left origin, y growing downward) while NSScreen.frame is AppKit
        // (bottom-left origin, y growing upward). Mixing them made every
        // containment test wrong off the main display, which on a vertically
        // stacked arrangement reads as no spread when the items really do
        // straddle two screens.
        let hiddenControlItemMinX = controlItems.hidden.bounds.minX
        let unparkedItems = items.filter { $0.bounds.minX >= hiddenControlItemMinX }
        guard !LayoutSolver.itemsSpanMultipleDisplays(
            itemCenters: unparkedItems.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) },
            screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        ) else { return }

        if let last = lastNotchRebalanceTimestamp,
           Date.now.timeIntervalSince(last) < Self.notchRebalanceCooldown
        {
            return
        }

        let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
        let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

        // Live flat order, grouped by section, in the shape planNotchOverflow
        // expects: visible items, hidden control item, hidden items,
        // always-hidden control item, always-hidden items.
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        var bySection: [MenuBarSection.Name: [MenuBarItem]] = [:]
        for item in items where Self.isBudgetedManagedItem(item) && !item.isControlItem {
            guard let section = context.findSection(for: item) else { continue }
            bySection[section, default: []].append(item)
        }
        for key in bySection.keys {
            // Tie-broken sort: this order is persisted as the layout of
            // record, so items sharing a minX mid-reflow must not land in a
            // different relative order from one snapshot to the next.
            bySection[key] = MenuBarItem.sortByLeadingEdgeThenIdentifier(bySection[key] ?? [])
        }

        var flat = (bySection[.visible] ?? []).map(\.uniqueIdentifier)
        let visibleUIDs = flat
        flat.append(hiddenCtrlUID)
        flat.append(contentsOf: (bySection[.hidden] ?? []).map(\.uniqueIdentifier))
        if let ahCtrlUID {
            flat.append(ahCtrlUID)
            flat.append(contentsOf: (bySection[.alwaysHidden] ?? []).map(\.uniqueIdentifier))
        }

        let budget = Self.computeNotchOverflowBudget(
            items: items,
            screen: screen,
            notch: notch,
            spacingOffset: appState.spacingManager.offset
        )
        var availableWidth = budget.availableWidth

        let visibleCtrlUID = items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier
        var uidWidths = [String: CGFloat]()
        for item in items where visibleUIDs.contains(item.uniqueIdentifier) {
            uidWidths[item.uniqueIdentifier] = item.bounds.width
        }
        if let visibleCtrlUID,
           let chevron = items.first(where: { $0.uniqueIdentifier == visibleCtrlUID }),
           chevron.bounds.minX >= notch.maxX,
           chevron.bounds.maxX <= budget.rightBoundary
        {
            availableWidth -= chevron.bounds.width
        }

        // Every visible item counts as unmanaged here: with no profile active
        // none of them has a saved position to protect, and the tiered rule
        // degenerates to leftmost-first. With a profile active the tiering is
        // wrong, but this call is only read for whether the set is empty, and
        // that answer is the total footprint against the budget either way —
        // the tiers decide which items are chosen, not whether any are.
        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: flat,
            unmanagedUIDs: visibleUIDs.filter { $0 != visibleCtrlUID },
            controlUIDs: ControlUIDs(
                visible: visibleCtrlUID,
                hidden: hiddenCtrlUID,
                alwaysHidden: ahCtrlUID
            ),
            sectionMap: [:],
            uidWidths: uidWidths,
            availableWidth: availableWidth
        )
        guard !result.overflowUIDs.isEmpty else { return }

        // A profile apply is the better tool: it re-runs this same planner and
        // restores the saved order at the same time.
        //
        // This hands off only once the planner has found real overflow. The
        // handoff used to happen at the top of this method, before the
        // cooldown and before the budget was ever computed, so a bar with a
        // profile and a notch re-armed a full profile apply on every cache
        // tick — and each apply recaches, which runs this pass again. #881's
        // 08:41 log turned over 73 applies in four minutes on a bar that
        // never once overflowed: the pass returned before reaching
        // `computeNotchOverflowBudget`, so not one ejection was ever planned.
        // The apply moved six items per pass on unrelated grounds, each move
        // a synthetic drag that takes the cursor.
        if activeProfileLayout != nil {
            lastNotchRebalanceTimestamp = .now
            MenuBarItemManager.diagLog.info(
                "Notch overflow rebalance: deferring \(result.overflowUIDs.count) item(s) to the profile apply"
            )
            scheduleProfileResort()
            return
        }

        // Bounce-back guard. Every UID the planner wants to eject is one this
        // pass already ejected, yet they are back in visible — the move is not
        // sticking (an owner that re-adds its item to the right of the divider,
        // typically). Retrying on every cache tick would drag the bar forever,
        // so stand down until something else changes the set.
        if result.overflowUIDs.allSatisfy(notchOverflowEjectedUIDs.contains) {
            MenuBarItemManager.diagLog.debug(
                "Notch overflow rebalance: standing down; all \(result.overflowUIDs.count) candidate(s) were already ejected once"
            )
            return
        }

        lastNotchRebalanceTimestamp = .now
        MenuBarItemManager.diagLog.info(
            """
            Notch overflow rebalance: ejecting \(result.overflowUIDs.count) item(s) to hidden; \
            \(budget.logString)
            """
        )

        // Leftmost-first, so each ejected item lands deeper in hidden than the
        // one before it and the surviving visible order is preserved.
        for uid in result.overflowUIDs {
            guard let item = items.first(where: { $0.uniqueIdentifier == uid }) else { continue }
            // The bounce-back guard above only covers ejections that landed.
            // A candidate whose eject keeps failing would otherwise be
            // re-dragged on every windowID change against unchanged geometry
            // (#900) — the ledger's growing per-item window bounds that the
            // same way it bounds the profile-layout moves.
            if failureLedger.isUnderBackoff(key: uid) {
                MenuBarItemManager.diagLog.debug(
                    "Notch overflow rebalance: \(uid) under move-failure backoff, skipping"
                )
                continue
            }
            do {
                try await move(item: item, to: .leftOfItem(controlItems.hidden))
                notchOverflowEjectedUIDs.insert(uid)
                failureLedger.recordSuccess(for: item)
            } catch {
                failureLedger.recordFailure(for: item, kind: Self.failureKind(of: error))
                MenuBarItemManager.diagLog.error(
                    "Notch overflow rebalance: failed to eject \(item.logString): \(error)"
                )
            }
        }
    }
}

// MARK: - CGEventField Helpers

private nonisolated extension CGEventField {
    /// Key to access a field that contains the event's window identifier.
    static let windowID = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// Fields that can be used to compare menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowID,
    ]
}

// MARK: - CGEventFilterMask Helpers

private nonisolated extension CGEventFilterMask {
    /// Specifies that all events should be permitted during event suppression states.
    static let permitAllEvents: CGEventFilterMask = [
        .permitLocalMouseEvents,
        .permitLocalKeyboardEvents,
        .permitSystemDefinedEvents,
    ]
}

// MARK: - CGEventType Helpers

private nonisolated extension CGEventType {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .null: "null event"
        case .leftMouseDown: "leftMouseDown event"
        case .leftMouseUp: "leftMouseUp event"
        case .rightMouseDown: "rightMouseDown event"
        case .rightMouseUp: "rightMouseUp event"
        case .mouseMoved: "mouseMoved event"
        case .leftMouseDragged: "leftMouseDragged event"
        case .rightMouseDragged: "rightMouseDragged event"
        case .keyDown: "keyDown event"
        case .keyUp: "keyUp event"
        case .flagsChanged: "flagsChanged event"
        case .scrollWheel: "scrollWheel event"
        case .tabletPointer: "tabletPointer event"
        case .tabletProximity: "tabletProximity event"
        case .otherMouseDown: "otherMouseDown event"
        case .otherMouseUp: "otherMouseUp event"
        case .otherMouseDragged: "otherMouseDragged event"
        case .tapDisabledByTimeout: "tapDisabledByTimeout event"
        case .tapDisabledByUserInput: "tapDisabledByUserInput event"
        @unknown default: "unknown event"
        }
    }
}

// MARK: - CGMouseButton Helpers

private nonisolated extension CGMouseButton {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .left: "left mouse button"
        case .right: "right mouse button"
        case .center: "center mouse button"
        @unknown default: "unknown mouse button"
        }
    }
}

// MARK: - Duration Helpers

private nonisolated extension Duration {
    /// Returns the duration in milliseconds as a Double.
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}

// MARK: - CGEvent Helpers

private nonisolated extension CGEvent {
    /// Returns an event that can be sent to a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The event's target item.
    ///   - source: The event's source.
    ///   - type: The event's specialized type.
    ///   - location: The event's location. Does not need to be
    ///     within the bounds of the item.
    static func menuBarItemEvent(
        item: MenuBarItem,
        source: CGEventSource,
        type: MenuBarItemEventType,
        location: CGPoint
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgEventType,
            mouseCursorPosition: location,
            mouseButton: type.cgMouseButton
        ) else {
            return nil
        }
        event.setFlags(for: type)
        event.setUserData(ObjectIdentifier(event))
        event.setWindowID(item.windowID, for: type)
        event.setClickState(for: type)
        return event
    }

    /// Returns a null event with unique user data.
    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        event.setUserData(ObjectIdentifier(event))
        return event
    }

    /// Posts the event to the given event tap location.
    ///
    /// - Parameter location: The event tap location to post the event to.
    func post(to location: EventTap.Location) {
        let type = self.type
        MenuBarItemManager.diagLog.debug(
            """
            Posting \(type.logString) \
            to \(location.logString)
            """
        )
        switch location {
        case .hidEventTap: post(tap: .cghidEventTap)
        case .sessionEventTap: post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: post(tap: .cgAnnotatedSessionEventTap)
        case let .pid(pid): postToPid(pid)
        }
    }

    /// Returns a Boolean value that indicates whether the given integer
    /// fields from this event are equivalent to the same integer fields
    /// from the specified event.
    ///
    /// - Parameters:
    ///   - other: The event to compare with this event.
    ///   - fields: The integer fields to check.
    func matches(_ other: CGEvent, byIntegerFields fields: [CGEventField]) -> Bool {
        fields.allSatisfy { field in
            getIntegerValueField(field) == other.getIntegerValueField(field)
        }
    }

    func setTargetPID(_ pid: pid_t) {
        let targetPID = Int64(pid)
        setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
    }

    private func setFlags(for type: MenuBarItemEventType) {
        flags = type.cgEventFlags
    }

    private func setUserData(_ bitPattern: ObjectIdentifier) {
        let userData = Int64(Int(bitPattern: bitPattern))
        setIntegerValueField(.eventSourceUserData, value: userData)
    }

    /// Stamps the target window onto the event.
    ///
    /// Move events additionally stamp the raw 0x33 `windowID` field. This was
    /// A/B tested against external reports that the field can make WindowServer
    /// discard event locations on pid-routed events; on real hardware moves are
    /// more reliable with it, so it is unconditional.
    private func setWindowID(_ windowID: CGWindowID, for type: MenuBarItemEventType) {
        let windowID = Int64(windowID)

        setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)

        if case .move = type {
            setIntegerValueField(.windowID, value: windowID)
        }
    }

    private func setClickState(for type: MenuBarItemEventType) {
        if case let .click(subtype) = type {
            setIntegerValueField(.mouseEventClickState, value: subtype.clickState)
        }
    }
}
