//
//  MenuBarItemManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
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

/// Manager for menu bar items.
@MainActor
@Observable
final class MenuBarItemManager {
    static let layoutWatchdogTimeout: Duration = .seconds(6)

    /// Delay between relocation/restore moves and the subsequent recache,
    /// giving macOS time to settle menu bar item positions.
    static let uiSettleDelay: Duration = .milliseconds(300)

    /// The current cache of menu bar items.
    var itemCache = ItemCache(displayID: nil)

    /// A Boolean value that indicates whether the control items for the
    /// hidden sections are missing from the menu bar.
    var areControlItemsMissing = false

    /// Number of consecutive `ControlItemPair` lookup failures seen by
    /// `cacheItemsRegardless`. Reset to zero on the first successful lookup.
    /// Once this reaches `controlItemRebuildThreshold`, the hidden and
    /// always-hidden control items' underlying status items are rebuilt once
    /// for that uninterrupted failure episode (see `recreateStatusItem()`).
    var controlItemLookupFailureStreak = 0

    /// Whether the current uninterrupted lookup-failure episode has already
    /// rebuilt the control items. Re-armed only after a successful lookup.
    var didRebuildControlItemsForCurrentFailureEpisode = false

    /// When the most recent `ControlItemPair` lookup failure was recorded.
    /// Feeds ``controlItemLookupRetryBackoff(consecutiveFailures:threshold:baseDelay:maxDelay:)``
    /// so the change-detector poll stops re-running a full recache every
    /// tick against a failure that is not going away (#933). Cleared on
    /// the first successful lookup.
    var lastControlItemLookupFailureAt: ContinuousClock.Instant?

    /// Consecutive authoritative cache readings in which the hidden section
    /// has no geometric span despite a populated saved hidden section.
    var hiddenSectionCollapseStreak = 0

    /// Prevents repeated divider recreation until healthy geometry re-arms
    /// recovery for a later collapse episode.
    var didRecoverHiddenSectionForCurrentCollapse = false

    /// Consecutive authoritative layout applies that need to move a hidden
    /// divider which macOS has parked off every display.
    var parkedHiddenDividerMismatchStreak = 0

    /// Prevents repeated divider recreation until the mismatch or parked
    /// geometry clears and re-arms recovery for a later episode.
    var didRecoverParkedHiddenDividerForCurrentMismatch = false

    /// Consecutive authoritative cache cycles in which the always-hidden
    /// section is enabled but its divider did not resolve while the hidden
    /// divider did. A display change can strand the AH status item on another
    /// screen's menu bar; `ControlItemPair` treats the missing divider as
    /// success, so the lookup-failure rebuild never sees it (#863).
    var missingAlwaysHiddenDividerStreak = 0

    /// Prevents repeated AH divider recreation until the divider resolves
    /// again and re-arms recovery for a later episode.
    var didRecoverMissingAlwaysHiddenDivider = false

    /// Number of consecutive `ControlItemPair` lookup failures required
    /// before the control items' status items are rebuilt.
    static nonisolated let controlItemRebuildThreshold = 3

    /// Number of consecutive collapsed readings required before discarding a
    /// hidden divider's stale autosave position.
    static nonisolated let hiddenSectionCollapseRecoveryThreshold = 3

    /// Number of authoritative mismatch applies required before discarding a
    /// parked hidden divider's stale autosave position.
    static nonisolated let parkedHiddenDividerRecoveryThreshold = 2

    /// Number of consecutive authoritative cache cycles with an enabled but
    /// unresolved always-hidden divider required before that divider's status
    /// item is rebuilt.
    static nonisolated let missingAlwaysHiddenDividerRecoveryThreshold = 3

    /// Supplementary AX-derived identity for items whose CG-side identity is
    /// degraded (a Control-Center generic `Item-N` placeholder title, or a
    /// bundle-id-shaped title — see `86f2514e`). Populated at most once per
    /// `cacheItemsRegardless` pass, only when at least one degraded item is
    /// present in that pass. Additive and display-only: this map is never
    /// consulted for matching, section assignment, or persisted layout keys
    /// — see plan 014. No display consumer exists on this branch, so this
    /// is groundwork for a future tooltip/display-name path.
    var degradedItemAXIdentities = [CGWindowID: AXIdentityCatalog.AXItemIdentity]()

    /// Gates the AX enrichment pass in `cacheItemsRegardless`. No consumer of
    /// `degradedItemAXIdentities` exists yet (see its declaration), so the
    /// per-cycle `AXIdentityCatalog.snapshot` and per-item window bounds
    /// lookups run only when explicitly enabled for diagnostics. Computed so
    /// a runtime `defaults write` (and a test's scratch store) is observed
    /// rather than frozen at first access.
    static nonisolated var isDegradedIdentityEnrichmentEnabled: Bool {
        Defaults.store.bool(forKey: "EnableDegradedItemAXEnrichment")
    }

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
    var recentItemWindowIDCycles: Deque<Set<CGWindowID>> = []

    /// Consecutive cache passes discarded as mid expand/collapse.
    ///
    /// Bounds the guard: if geometry and logical state disagree persistently
    /// rather than transiently, the cache must still be allowed to move
    /// forward instead of serving a stale layout indefinitely.
    var midTransitionSkipStreak = 0

    /// How many consecutive passes may be discarded as mid expand/collapse
    /// before one is accepted regardless.
    static let maxMidTransitionSkips = 3

    /// How many cache cycles a windowID stays eligible as "recently seen".
    static let recentWindowIDCycleWindow = 10

    /// Diagnostic logger for the menu bar item manager.
    static nonisolated let diagLog = DiagLog(category: "MenuBarItemManager")

    /// Semaphore to prevent overlapping event operations.
    let eventSemaphore = SimpleSemaphore(value: 1)

    /// The single record of which items have been failing, and how.
    let failureLedger = MenuBarItemFailureLedger()

    /// The record of which saved identifiers no longer match anything.
    let staleIdentifierLedger = StaleIdentifierLedger()

    /// Actor for managing menu bar item cache operations.
    let cacheActor = CacheActor()

    /// Contexts for temporarily shown menu bar items.
    var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    var rehideTimer: Timer?
    var rehideCancellable: AnyCancellable?

    /// Timestamp of the most recent menu bar item move operation.
    var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// When the user last moved an item themselves, as opposed to Thaw
    /// moving one on their behalf.
    ///
    /// Both kinds stamp ``lastMoveOperationTimestamp``, and for the restore
    /// cooldown that is right — a bar that just moved should be left alone
    /// whoever moved it. The save gate needs to tell them apart. Thaw's own
    /// moves mean the bar is mid-restore and must not be written down; a
    /// user's move is the one thing that *must* be written down, and
    /// promptly, because the restore will otherwise revert it on the next
    /// cycle. Suppressing the save for both would make a Layout-editor drag
    /// undo itself (#958).
    var lastUserMoveOperationTimestamp: ContinuousClock.Instant?

    /// Cached timeouts for move operations.
    var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// Cached timeouts for click operations (adaptive per app).
    var clickOperationTimeouts = [MenuBarItemTag: Duration]()
    /// Serialization gate for cache operations.
    let cacheGate = CacheGate()

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
    var menuOpenCheckTask: Task<[MenuWindowCandidate], Never>?

    /// The most recent open-menu probe result and its timestamp.
    var menuOpenCheckCachedResult: Bool?
    var menuOpenCheckCachedAt: ContinuousClock.Instant?

    /// First-seen timestamps for candidate menu windows, keyed by window ID.
    /// A real menu is transient; a window that stays on screen longer than
    /// ``menuWindowPersistenceThreshold`` is persistent furniture (Droppy's
    /// shelf, notch HUDs) and must not block moves (#879 regression).
    var menuWindowFirstSeen: [CGWindowID: ContinuousClock.Instant] = [:]

    /// Whether the open-menu probe has run at least once. Windows already
    /// on screen at the first probe are grandfathered as persistent.
    var hasSeededMenuWindowProbe = false

    /// How long a candidate menu window may stay on screen before it is
    /// reclassified as persistent furniture rather than an open menu.
    static nonisolated let menuWindowPersistenceThreshold: Duration = .seconds(30)

    /// Timer for lightweight periodic cache checks.
    private var cacheTickCancellable: AnyCancellable?

    /// Persisted identifiers of menu bar items we've already seen.
    var knownItemIdentifiers = Set<String>()
    /// Suppresses the next automatic relocation of newly seen leftmost items.
    var suppressNextNewLeftmostItemRelocation = false

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
    var backgroundCacheWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    /// Count of cache cycles that observed the bar — rebuilding the cache
    /// or confirming it unchanged.
    ///
    /// The settling loop compares it across a poll to tell an observed pass
    /// from one the serial gate or a drag guard dropped; a dropped pass
    /// leaves the cache untouched without having looked, which must not
    /// count as stability. The stable no-op reads must, or a settled bar
    /// would produce no evidence and settling would run to its deadline.
    var completedCacheCycles = 0

    /// Source of tokens for ``backgroundCacheWaiters``.
    private var nextBackgroundCacheWaiterToken = 0

    /// Registers `continuation` as a waiter and returns its token.
    func addBackgroundCacheWaiter(_ continuation: CheckedContinuation<Void, Never>) -> Int {
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
    func resumeBackgroundCacheWaiter(_ token: Int) {
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
    var isRestoringItemOrder = false
    /// Timestamp when isRestoringItemOrder was set (for timeout detection).
    var isRestoringItemOrderTimestamp: Date?
    /// True during the startup settling period, during which restore operations
    /// and section-order saves are suppressed. This prevents cascading icon moves
    /// when many apps launch at login (login item boot) or restart in quick succession
    /// (e.g. app update checks). Cleared after a fixed delay, then one final
    /// restore runs to enforce the user's saved layout.
    var isInStartupSettling = false
    /// Whether the early, resolved-identities-only saved-layout apply has
    /// already been attempted for the current settling period. Bounds that
    /// pass to one attempt per launch: it exists to get the identifiable
    /// items into place while sourcePID resolution is still catching up, and
    /// the unrestricted settling-end pass covers whatever it left behind.
    var didAttemptEarlySavedLayoutApply = false
    /// Handle to the in-flight startup settling Task. Retained so that a
    /// subsequent performSetup() call can cancel the previous settling period
    /// before starting a new one, preventing multiple concurrent settling tasks.
    var startupSettlingTask: Task<Void, Never>?
    /// Handle to the initial cache warm-up task. The first full cache can be
    /// expensive on dense menu bars, so it runs off the startup critical path.
    private var initialCacheTask: Task<Void, Never>?
    /// Absolute deadline for the current startup settling period. Stored so
    /// that a re-entry of performSetup() (e.g. permission re-grant) can
    /// preserve any remaining time from the original period rather than
    /// resetting to a shorter delay based on current systemUptime.
    var settlingDeadline: ContinuousClock.Instant?
    /// Bundle IDs the current settling period is waiting on. Empty for a
    /// preflight (count-stability) settling. Promoted to non-empty when
    /// startSettlingPeriod is called with expectedBundleIDs after a real
    /// relaunch wave; cancelSettlingPeriod refuses to tear down a promoted
    /// settling so a concurrent no-op apply cannot clobber an in-flight
    /// wait for relaunched apps to reattach.
    var settlingExpectedBundleIDs = Set<String>()

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
    enum SettlingKind {
        case cold
        case preflight
        case expectedSet
    }

    var settlingKind: SettlingKind?
    /// Persisted bundle identifiers explicitly placed in hidden section.
    var pinnedHiddenBundleIDs = Set<String>()
    /// Persisted bundle identifiers explicitly placed in always-hidden section.
    var pinnedAlwaysHiddenBundleIDs = Set<String>()

    /// Cached layout parameters from the last profile apply, used to re-sort
    /// when profile-listed items appear after the initial apply. Read access
    /// is internal so tests can verify the re-arm path refreshes it; writes
    /// remain confined to this file (armProfileState and rearmActiveProfileLayout).
    var activeProfileLayout: (
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    )?

    /// Flattened set of item identifiers from the active profile's itemOrder,
    /// for O(1) lookup when detecting late-arriving profile items.
    var activeProfileItemIdentifiers = Set<String>()

    /// Set of item identifiers that were present when the profile layout was
    /// last applied (or re-applied). Used to detect genuinely new arrivals.
    var profileSortedItemIdentifiers = Set<String>()

    /// Handle for the debounced profile re-sort task. Cancelled and re-created
    /// each time a new late-arriving profile item is detected.
    var profileResortTask: Task<Void, Never>?

    /// True while `applyProfileLayout` is executing. Suppresses the
    /// late-arrival detection in `cacheItemsRegardless` to prevent
    /// false re-sort triggers during an in-flight sort.
    var isApplyingProfileLayout = false

    /// Monotonically increasing token identifying the most recent
    /// profile-state arm. Each `.profile` armProfileState call takes a
    /// new token; a cancelled apply may only roll back state it still
    /// owns (its token is still current), so a late-arriving
    /// cancellation cannot clobber the state armed by the newer apply
    /// that displaced it.
    var profileApplyToken = 0

    /// Pre-arm snapshot of the in-memory profile state, tagged with the
    /// token of the apply that captured it. Restored when that apply is
    /// cancelled mid-flight so memory reverts to what disk still holds
    /// (persistence is deferred to persistProfileStateOnSuccess) and the
    /// late-arrival re-sort path stops targeting a profile that never
    /// committed.
    struct ProfileApplySnapshot {
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
    var priorProfileApplySnapshot: ProfileApplySnapshot?

    /// True while `applyProfileLayout` is actively issuing the move
    /// sequence (Phase 6). Lets `postMoveEvents` skip redundant
    /// per-item cursor hide/show churn — the cursor is already held
    /// hidden for the whole sequence, and is restored once at Phase 7.
    var isBulkApplyInProgress = false

    /// Timestamp of the first observation of a diverged layout that has
    /// not yet been confirmed by a second consecutive observation. `nil`
    /// when no divergence is currently pending confirmation. See
    /// `confirmedDivergence(divergedNow:pendingSince:now:staleness:)`.
    var pendingDivergenceObservedAt: ContinuousClock.Instant?

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

    /// Monotonic marker and result for the most recently completed bulk
    /// apply. Trigger release restoration uses the generation to distinguish
    /// a real completed apply from an early-returned apply request.
    private(set) var bulkApplyOutcomeGeneration = 0
    private(set) var lastBulkApplyUnenactedMoveCount: Int?

    /// Records how a bulk apply ended, for the saveSectionOrder gate.
    ///
    /// A clean batch clears the arm rather than leaving it to expire: the
    /// bar now matches what the apply set out to produce, and there is no
    /// reason to keep withholding it from the saved order.
    func recordBulkApplyOutcome(unenactedMoveCount: Int) {
        bulkApplyOutcomeGeneration += 1
        lastBulkApplyUnenactedMoveCount = unenactedMoveCount
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
    func isAutomaticBulkApplyPermitted(caller: String, quietly: Bool = false) -> Bool {
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

    /// Whether ``move(item:to:on:skipInputPause:maxMoveAttempts:)`` already
    /// filed this error against the item before throwing it.
    ///
    /// `move` files every unresponsive-owner failure itself, so a caller that
    /// also files one on catching the throw counts a single failed move
    /// twice. That is not a cosmetic tally: the ledger deliberately waits for
    /// a run of unresponsive-owner failures before writing a persisted mark,
    /// and double-filing consumed the whole run in the same instant — the
    /// #687 log marks 1Password one millisecond after logging that it was
    /// still waiting. Every item that failed a single bulk-apply move was
    /// marked immediately, and marked items get one attempt instead of eight
    /// thereafter.
    ///
    /// Callers still file the failures `move` does not, so the backoff window
    /// keeps counting vanished items and stale destinations.
    static nonisolated func moveAlreadyFiledFailure(for error: any Error) -> Bool {
        // Pattern-matched rather than compared: `FailureKind`'s `Equatable`
        // conformance is main-actor isolated and this runs nonisolated.
        if case .unresponsiveOwner = failureKind(of: error) {
            return true
        }
        return false
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
    var pendingRelocations = [String: String]()

    /// Persisted mapping of item tag identifiers to their return destination for
    /// temporarily shown items. Stores the neighbor tag and position to restore
    /// the original ordering when the app relaunches.
    var pendingReturnDestinations = [String: [String: String]]() // [tagIdentifier: ["neighbor": tag, "position": "left"|"right"]]

    /// Persisted per-section item order. Maps section key to an ordered list of
    /// `uniqueIdentifier` strings (right-to-left, matching cache array order).
    var savedSectionOrder = [String: [String]]()

    /// Items whose section is temporarily owned by an active trigger. Their
    /// live placement must not overwrite the user's saved layout, and the
    /// saved-layout reconciler must not move them back while the trigger owns
    /// them. The trigger manager clears this set when an item is no longer
    /// controlled, at which point the normal saved-layout restore returns it
    /// to the user's pre-trigger position.
    var triggerControlledItemIdentifiers = Set<String>()

    /// Items released by a trigger that still need their full saved position
    /// (including order within a section) restored. They remain excluded from
    /// persistence until that replay finishes, so an intervening cache cycle
    /// cannot capture their temporary trigger placement as a user edit.
    var triggerLayoutRestorationItemIdentifiers = Set<String>()

    /// Identifiers most recently moved from visible to hidden by the
    /// notch-overflow rebalance (Phase 4 of the layout apply). The ejection
    /// is a transient, per-display accommodation — these items must not be
    /// persisted as hidden (the user never moved them), and their divergence
    /// from the saved layout is intentional while the notched display is
    /// active. Cleared when overflow no longer applies, when a non-notched
    /// apply restores them, or when the user moves them to another section.
    var notchOverflowEjectedUIDs = Set<String>()

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
    var lastNotchRebalanceTimestamp: Date?
    /// Placement preference for newly detected menu bar items.
    var newItemsPlacement = NewItemsPlacement.defaultValue

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
    func persistKnownItemIdentifiers() {
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
    func persistPinnedBundleIDs() {
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
    func persistPendingRelocations() {
        let key = LayoutStateKey.pendingRelocations
        Defaults.store.set(pendingRelocations, forKey: key)
        let destKey = LayoutStateKey.pendingReturnDestinations
        Defaults.store.set(pendingReturnDestinations, forKey: destKey)
    }

    /// Loads persisted section order.
    /// The display names Control Center is currently known by, used to
    /// recognize localized-namespace ghosts in the saved order (#949).
    ///
    /// The whitespace heuristic in `LayoutSolver` misses languages whose
    /// display name has none (Kontrollzentrum); the live localized name
    /// covers the current locale, and ghosts minted under a previous
    /// system language still fall to the whitespace test where they can.
    static func controlCenterDisplayNameAliases() -> Set<String> {
        Set(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.controlcenter"
            ).compactMap(\.localizedName)
        )
    }

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
            let pruned = LayoutSolver.prunedSectionOrder(
                migrated,
                displayNameAliases: Self.controlCenterDisplayNameAliases()
            )
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
    func persistSavedSectionOrder() {
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
        let knownBaseIdentifiers = Set(cache.managedItems.map(\.tag.stableIdentifierBase))
        let knownLiveIdentifiers = Set(cache.managedItems.map(\.uniqueIdentifier))
        let triggerProtectedIdentifiers = triggerControlledItemIdentifiers
            .union(triggerLayoutRestorationItemIdentifiers)
        let triggerProtectedBaseIdentifiers = Set(triggerProtectedIdentifiers.compactMap {
            MenuBarItemTag.resolvedBaseIdentifier(
                for: $0,
                knownBaseIdentifiers: knownBaseIdentifiers
            )
        })

        func isTriggerProtected(_ item: MenuBarItem) -> Bool {
            Self.isTriggerProtected(
                item.uniqueIdentifier,
                by: triggerProtectedIdentifiers,
                knownBaseIdentifiers: knownBaseIdentifiers,
                knownLiveIdentifiers: knownLiveIdentifiers
            )
        }

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
            guard !isTriggerProtected(item) else { return false }
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
                let baseID = item.tag.stableIdentifierBase
                if !triggerProtectedBaseIdentifiers.contains(baseID) {
                    allCurrentBaseIdentifiers.insert(baseID)
                }
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
    func saveSectionOrder(from cache: ItemCache) {
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
    func sectionKey(for section: MenuBarSection.Name) -> String {
        switch section {
        case .visible: "visible"
        case .hidden: "hidden"
        case .alwaysHidden: "alwaysHidden"
        }
    }

    /// Returns the section name for the given persisted key, if valid.
    static nonisolated func persistedSectionName(for key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }

    /// Returns the section name for the given persisted key, if valid.
    func sectionName(for key: String) -> MenuBarSection.Name? {
        Self.persistedSectionName(for: key)
    }

    /// Prefix used in `pendingRelocations` values to mark items whose rehide
    /// failed terminally in the current session. The suffix is the item's
    /// `windowID` at the time of failure, used to detect app relaunches.
    private static let waitForRelaunchPrefix = "waitForRelaunch:"

    /// Returns a `pendingRelocations` sentinel value that suppresses same-session
    /// move attempts. Encodes `windowID` so that a relaunch (new windowID) clears
    /// the suppression automatically.
    func waitForRelaunchValue(windowID: CGWindowID, section: MenuBarSection.Name) -> String {
        "\(Self.waitForRelaunchPrefix)\(windowID):\(sectionKey(for: section))"
    }

    /// Parses a `pendingRelocations` sentinel value.
    /// Returns `(windowID, section)` if the value is a wait-for-relaunch entry,
    /// or `nil` if it is a plain section key.
    func parseWaitForRelaunch(_ value: String) -> (windowID: CGWindowID, section: MenuBarSection.Name)? {
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
    func newItemsMoveDestination(
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

                let cyclesBefore = completedCacheCycles
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
                } else if completedCacheCycles != cyclesBefore {
                    // Only an observed cache pass is evidence. A dropped one
                    // (gate busy, drag in progress) leaves the cache exactly
                    // as it was, which would read as "stable" and could end
                    // settling on nothing.
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

    /// Returns a Boolean value that indicates whether the user moved an item
    /// themselves within the given duration.
    func lastUserMoveOperationOccurred(within duration: Duration) -> Bool {
        guard let timestamp = lastUserMoveOperationTimestamp else {
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
        lastUserMoveOperationTimestamp = .now
        pendingDivergenceObservedAt = nil
        recordBulkApplyOutcome(unenactedMoveCount: 0)
    }

    /// Whether the save gate's user-move exemption applies: it must, and only,
    /// when the most recent move was the user's own.
    ///
    /// Comparing recency rather than presence closes a hole in the cooldown:
    /// a user move at T0 followed by an automatic move at T+3 leaves both
    /// timestamps inside the five-second window, and an exemption keyed on
    /// "a user move happened recently" would disable the cooldown for an
    /// arrangement Thaw generated itself, letting the next cache cycle
    /// persist it.
    ///
    /// Pure over its inputs.
    static nonisolated func saveCooldownExemptForUserMove(
        lastMoveOperationTimestamp: ContinuousClock.Instant?,
        lastUserMoveOperationTimestamp: ContinuousClock.Instant?
    ) -> Bool {
        guard let lastMoveOperationTimestamp, let lastUserMoveOperationTimestamp else {
            return false
        }
        return lastUserMoveOperationTimestamp >= lastMoveOperationTimestamp
    }
}
