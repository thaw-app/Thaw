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

// CGEvent/CGEventSource aren't Sendable-annotated in the macOS 26/27 SDK. Drop
// @preconcurrency once Apple annotates them.
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

    /// Consecutive ControlItemPair lookup failures. At
    /// controlItemRebuildThreshold the hidden control items are rebuilt once
    /// per failure episode.
    var controlItemLookupFailureStreak = 0

    /// Whether the current uninterrupted lookup-failure episode has already
    /// rebuilt the control items. Re-armed only after a successful lookup.
    var didRebuildControlItemsForCurrentFailureEpisode = false

    /// Feeds the lookup retry backoff so the poll stops recaching every tick
    /// against a persistent failure (#933).
    var lastControlItemLookupFailureAt: ContinuousClock.Instant?

    /// Exact Control Center launch observed by the latest cache cycle.
    /// A new host process starts a new divider-recovery episode even if the
    /// preceding process never produced a successful lookup before exiting.
    var lastObservedControlCenterGeneration: ProcessGeneration?

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

    /// Cycles where the always-hidden divider is enabled but unresolved. A
    /// display change can strand it on another screen, and ControlItemPair
    /// treats that as success (#863).
    var missingAlwaysHiddenDividerStreak = 0

    /// Prevents repeated AH divider recreation until the divider resolves
    /// again and re-arms recovery for a later episode.
    var didRecoverMissingAlwaysHiddenDivider = false

    /// Number of consecutive ControlItemPair lookup failures required
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

    /// AX-derived identity for items with a degraded CG identity (`Item-N` or
    /// a bundle-ID-shaped title). Display only, never used for matching or
    /// layout keys. Nothing reads it yet.
    var degradedItemAXIdentities = [CGWindowID: AXIdentityCatalog.AXItemIdentity]()

    /// Enables the AX enrichment pass for diagnostics only, since nothing
    /// reads its result. Computed so runtime defaults writes are seen.
    static nonisolated var isDegradedIdentityEnrichmentEnabled: Bool {
        Defaults.store.bool(forKey: "EnableDegradedItemAXEnrichment")
    }

    /// Widest a control item can be while still counting as a marker rather
    /// than a collapsed section's stretched divider.
    ///
    /// Collapsed is 10000 pt (clamped to about the display span); expanded is
    /// single digits. The value only has to separate them.
    private static nonisolated let markerWidthCeiling: CGFloat = 256

    /// Whether a divider's geometry contradicts its section's logical state,
    /// meaning the snapshot was taken part-way through an expand or collapse.
    ///
    /// section.show() moves and resizes the divider in separate steps.
    /// Classifying that mixture puts the whole hidden section into visible
    /// (#851).
    ///
    /// - Parameters:
    ///   - dividerWidth: Width of the section's control item.
    ///   - isSectionCollapsed: Whether the section's logical state is hidden.
    ///
    /// - Returns: true when geometry and logical state disagree.
    static nonisolated func isMidSectionTransition(
        dividerWidth: CGFloat,
        isSectionCollapsed: Bool
    ) -> Bool {
        (dividerWidth > markerWidthCeiling) != isSectionCollapsed
    }

    /// The item windowIDs enumerated in each of the last few cache cycles,
    /// oldest first.
    ///
    /// Tells new items from renamed ones. One cycle wasn't enough: a Space
    /// switch or display change can drop windowIDs for a cycle, and the item
    /// then gets dragged out of its section (#849). Not unbounded, since
    /// WindowServer recycles windowIDs.
    var recentItemWindowIDCycles: Deque<Set<CGWindowID>> = []

    /// Consecutive cache passes discarded as mid expand/collapse.
    ///
    /// Bounded so a persistent disagreement can't freeze the cache.
    var midTransitionSkipStreak = 0

    /// How many consecutive passes may be discarded as mid expand/collapse
    /// before one is accepted regardless.
    static let maxMidTransitionSkips = 3

    /// How many cache cycles a windowID stays eligible as "recently seen".
    static let recentWindowIDCycleWindow = 10

    static nonisolated let diagLog = DiagLog(category: "MenuBarItemManager")

    /// Semaphore to prevent overlapping event operations.
    let eventSemaphore = SimpleSemaphore(value: 1)

    /// The single record of which items have been failing, and how.
    let failureLedger = MenuBarItemFailureLedger()

    /// Pauses automatic moves when they run away: icon dancing or repeated
    /// failed drags. Consulted by every move.
    let moveCircuitBreaker = MoveCircuitBreaker()

    /// When each item's failed automatic move was last presented to the user.
    /// Reports are still written while this presentation cooldown is active.
    var automaticMoveFailureReports = [String: Date]()

    /// When any automatic move failure was last presented, to space bursts
    /// involving several items from one layout pass.
    var lastAutomaticMoveFailureReport: Date?

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
    /// The save gate must tell these apart: Thaw's moves mean mid-restore
    /// and mustn't be saved, while a user's move must be saved promptly or
    /// the restore reverts it (#958).
    var lastUserMoveOperationTimestamp: ContinuousClock.Instant?

    /// Cached timeouts for move operations.
    var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// Items whose last move macOS refused, keyed by uniqueIdentifier. See
    /// noteRefusedMove(of:).
    var macOSRefusedMoves = [String: ContinuousClock.Instant]()

    /// Cached timeouts for click operations (adaptive per app).
    var clickOperationTimeouts = [MenuBarItemTag: Duration]()
    /// Serialization gate for cache operations.
    let cacheGate = CacheGate()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Observes appState.navigationState.
    private var navigationStateObservationTask: Task<Void, Never>?

    /// Task observing the item group set, so editing a group re-applies the
    /// gathered order to the live menu bar.
    private var groupOrderObservationTask: Task<Void, Never>?

    /// A candidate menu window matched by the open-menu probe.
    nonisolated struct MenuWindowCandidate {
        let windowID: CGWindowID
        let bounds: CGRect
    }

    /// Shared so concurrent smart-rehide callers don't each scan the bar.
    var menuOpenCheckTask: Task<[MenuWindowCandidate], Never>?

    /// The most recent open-menu probe result and its timestamp.
    var menuOpenCheckCachedResult: Bool?
    var menuOpenCheckCachedAt: ContinuousClock.Instant?

    /// A window on screen past menuWindowPersistenceThreshold is furniture
    /// (Droppy's shelf, notch HUDs), not a menu, and must not block moves.
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

    /// One-shot: the next saved-layout apply honours concealed-section order
    /// instead of relaxing it. Armed by ``sortSection`` when there is no
    /// active profile, since that path reorders through the saved-layout
    /// apply rather than a profile reapply. Cleared after one use.
    var enforceConcealedSectionOrderOnNextSavedApply = false

    @MainActor
    deinit {
        rehideTimer?.invalidate()
        rehideCancellable?.cancel()
        cacheTickCancellable?.cancel()
        menuOpenCheckTask?.cancel()
        navigationStateObservationTask?.cancel()
        groupOrderObservationTask?.cancel()
    }

    /// Continuations waiting for a background cache cycle to complete,
    /// keyed by an opaque token.
    ///
    /// A dictionary so one caller's early bail can't resume or strand
    /// another's waiter.
    var backgroundCacheWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    /// Cache cycles that observed the bar, changed or not. Settling uses it
    /// to tell an observed stable pass from a dropped one.
    var completedCacheCycles = 0

    /// Source of tokens for backgroundCacheWaiters.
    private var nextBackgroundCacheWaiterToken = 0

    /// Registers continuation as a waiter and returns its token.
    func addBackgroundCacheWaiter(_ continuation: CheckedContinuation<Void, Never>) -> Int {
        nextBackgroundCacheWaiterToken += 1
        let token = nextBackgroundCacheWaiterToken
        backgroundCacheWaiters[token] = continuation
        return token
    }

    /// Resumes the waiter for token, if it has not already been resumed.
    ///
    /// Removing before resuming makes a second call a no-op. Resuming twice
    /// crashes, so keep this as a single removal, not lookup then remove.
    func resumeBackgroundCacheWaiter(_ token: Int) {
        backgroundCacheWaiters.removeValue(forKey: token)?.resume()
    }

    // MARK: - Layout coordination state

    //
    // These flags guard separate AX and WindowServer timing issues found in
    // production. Merging them needs manual testing on real hardware.
    //
    // 1. In-flight gating: cacheItemsRegardless suppresses restore,
    //    late-arrival detection, and saves while one is set:
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
    // 3. Active-profile re-sort, so a late profile item can be reinserted
    //    without a full re-apply:
    //      - activeProfileLayout
    //      - activeProfileItemIdentifiers
    //      - profileSortedItemIdentifiers
    //      - profileResortTask
    //
    // isApplyingProfileLayout belongs to both 1 and 3.

    /// Suppresses image cache updates during layout reset to prevent stale cache during moves.
    var isResettingLayout = false
    /// Suppresses saving section order during an active order-restore pass.
    var isRestoringItemOrder = false
    /// Timestamp when isRestoringItemOrder was set (for timeout detection).
    var isRestoringItemOrderTimestamp: Date?
    /// Suppresses restores and saves while many apps launch at once, to avoid
    /// cascading moves. One final restore runs when it clears.
    var isInStartupSettling = false
    /// Limits the early resolved-items-only apply to one attempt per settling
    /// period; the settling-end pass covers the rest.
    var didAttemptEarlySavedLayoutApply = false
    /// Retained so a later performSetup() can cancel it first.
    var startupSettlingTask: Task<Void, Never>?
    /// The first full cache can be expensive, so it runs off the startup path.
    private var initialCacheTask: Task<Void, Never>?
    /// Stored so re-entering performSetup() keeps the original remaining time.
    var settlingDeadline: ContinuousClock.Instant?
    /// Bundle IDs settling waits on after a relaunch wave; empty for a
    /// preflight. When non-empty, cancelSettlingPeriod refuses, so a no-op
    /// apply can't end the wait early.
    var settlingExpectedBundleIDs = Set<String>()

    /// So a preflight can't replace a more authoritative settling.
    ///
    /// - cold: the cold-boot wait; only another cold or an expected-set
    ///   relaunch replaces it.
    /// - preflight: before applyOffset; cancelled by the no-op path.
    /// - expectedSet: waiting on relaunched bundle IDs.
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

    /// The last profile apply's layout, for re-sorting late profile items.
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

    /// Recreated on each late profile item; kept until its apply returns.
    var profileResortTask: Task<Void, Never>?

    /// Monotonic ownership for every bulk layout batch. A higher-authority
    /// batch invalidates the closures held by older work before it can issue
    /// another move or commit state.
    var layoutBatchGeneration: UInt = 0
    var activeLayoutBatchLease: LayoutBatchLease?

    /// Suppresses late-arrival detection during an in-flight sort.
    var isApplyingProfileLayout = false

    /// A cancelled apply may only roll back state while its token is current,
    /// so it can't clobber a newer apply's state.
    var profileApplyToken = 0

    /// Restored if the apply is cancelled, so memory matches disk and the
    /// re-sort path stops targeting a profile that never committed.
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

    /// The snapshot captured by the most recent .profile arm, if that
    /// apply has neither committed nor rolled back yet.
    var priorProfileApplySnapshot: ProfileApplySnapshot?

    /// Lets postMoveEvents skip per-item cursor hide/show; the apply hides
    /// the cursor for the whole sequence.
    var isBulkApplyInProgress = false

    /// First sighting of a divergence awaiting confirmation. See
    /// confirmedDivergence(divergedNow:pendingSince:now:staleness:).
    var pendingDivergenceObservedAt: ContinuousClock.Instant?

    /// When the last bulk apply left planned moves unenacted; nil when it
    /// finished. See unfinishedMoveBatchBlocksSave(observedAt:now:).
    private var unfinishedMoveBatchObservedAt: ContinuousClock.Instant?

    /// Monotonic marker and result for the most recently recorded outcome,
    /// which includes an explicit user move (see
    /// recordExternalMoveOperation) because that too clears the save
    /// latch.
    private(set) var bulkApplyOutcomeGeneration = 0
    private(set) var lastBulkApplyUnenactedMoveCount: Int?

    /// Monotonic marker bumped only when a bulk apply actually ran to
    /// completion.
    ///
    /// Separate from bulkApplyOutcomeGeneration: a user drag mid-apply also
    /// records an outcome, and must not count as a completed apply for
    /// trigger release restoration.
    private(set) var bulkApplyCompletionGeneration = 0

    /// The unenacted-move count of the apply that owns the current
    /// completion generation.
    ///
    /// Separate because lastBulkApplyUnenactedMoveCount is also overwritten
    /// by user moves.
    private(set) var lastCompletedBulkApplyUnenactedMoveCount: Int?

    /// Records how a bulk apply ended, for the saveSectionOrder gate.
    ///
    /// A clean batch clears the arm rather than letting it expire.
    ///
    /// - Parameter isCompletedApply: whether this is a real bulk apply
    ///   finishing, as opposed to a user move borrowing the same latch.
    func recordBulkApplyOutcome(unenactedMoveCount: Int, isCompletedApply: Bool = true) {
        bulkApplyOutcomeGeneration += 1
        if isCompletedApply {
            bulkApplyCompletionGeneration += 1
            lastCompletedBulkApplyUnenactedMoveCount = unenactedMoveCount
        }
        lastBulkApplyUnenactedMoveCount = unenactedMoveCount
        moveCircuitBreaker.noteBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)
        guard unenactedMoveCount > 0 else {
            unfinishedMoveBatchObservedAt = nil
            return
        }
        unfinishedMoveBatchObservedAt = .now
        MenuBarItemManager.diagLog.warning(
            "Profile layout: \(unenactedMoveCount) planned move(s) left unenacted; withholding the current arrangement from the saved order (streak: \(moveCircuitBreaker.unfinishedBulkApplyStreak))"
        )
    }

    /// Whether the latest bulk apply left a partial arrangement that must not
    /// replace the saved order.
    var hasUnfinishedMoveBatch: Bool {
        Self.unfinishedMoveBatchBlocksSave(observedAt: unfinishedMoveBatchObservedAt)
    }

    /// Asks the move circuit breaker and logs a refusal under the caller's name.
    ///
    /// - Parameter quietly: Log at debug, for callers that retry every tick.
    func isAutomaticBulkApplyPermitted(caller: String, quietly: Bool = false) -> Bool {
        if moveCircuitBreaker.permitsAutomaticBulkApply {
            return true
        }
        let message = "\(caller): skipping, automatic moves are paused (\(moveCircuitBreaker.stateDescription))"
        if quietly {
            MenuBarItemManager.diagLog.debug(message)
        } else {
            MenuBarItemManager.diagLog.warning(message)
        }
        return false
    }

    /// How long a failed item stays excluded from bulk-apply moves.
    static nonisolated func moveFailureBackoffInterval(failureCount: Int) -> Duration {
        MenuBarItemFailureLedger.backoffInterval(failureCount: failureCount)
    }

    /// How the failure ledger should file an arbitrary error thrown by a
    /// move. Only EventError carries enough detail to blame the owner.
    static nonisolated func failureKind(of error: any Error) -> MenuBarItemFailureLedger.FailureKind {
        (error as? EventError)?.failureKind ?? .other
    }

    /// Whether move(item:to:on:skipInputPause:maxMoveAttempts:) already
    /// filed this error against the item before throwing it.
    ///
    /// Double-filing an unresponsive-owner failure would use up the ledger's
    /// run in one go and mark the owner immediately (#687), leaving it one
    /// attempt instead of eight. Callers still file what move doesn't.
    static nonisolated func moveAlreadyFiledFailure(for error: any Error) -> Bool {
        // FailureKind's Equatable is main-actor isolated.
        if case .unresponsiveOwner = failureKind(of: error) {
            return true
        }
        return false
    }

    /// The move-operation budget the next attempt should use, given how the
    /// attempt that just finished turned out.
    ///
    /// Shrinks on a landing, grows on no response, and holds on a miss. A
    /// miss still nudges the item, and rewarding it starved the budget
    /// (#881).
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
    /// A landing nudges the target by about an item width. Moving further
    /// than the display width means it crossed sections or went offscreen
    /// (#900).
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
    /// A wrong-side insertion shoves the anchor left each attempt, too little
    /// to be stale. With a divider as anchor, this walks it offscreen until
    /// saves and applies stop (#924, #927). One nudge is normal; a run in
    /// one direction without a landing is the move pushing its own anchor.
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
    /// FNV-1a, since hashValue is seeded per process. Order-sensitive on
    /// purpose: a permutation is invisible in a count (#885).
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
    /// Calls out same membership in a new sequence, #885's signature, which
    /// nothing else in the log shows.
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

    /// How a single postMoveEvents attempt turned out, for the purpose of
    /// sizing the next attempt's budget.
    enum MoveAttemptOutcome {
        /// The item reached its destination.
        case landed
        /// The item moved but did not reach its destination.
        case displacedWithoutLanding
        /// The owner never answered the posted events.
        case ownerDidNotRespond
    }

    /// Original sections of temporarily shown items whose apps quit before
    /// the rehide, restored on relaunch.
    var pendingRelocations = [String: String]()

    /// Neighbor and side for restoring those items' ordering.
    var pendingReturnDestinations = [String: [String: String]]() // [tagIdentifier: ["neighbor": tag, "position": "left"|"right"]]

    /// Persisted per-section item order. Maps section key to an ordered list of
    /// uniqueIdentifier strings (right-to-left, matching cache array order).
    var savedSectionOrder = [String: [String]]()

    /// Items an active trigger owns: neither saved nor moved back until the
    /// trigger releases them.
    var triggerControlledItemIdentifiers = Set<String>()

    /// Released items awaiting full restoration, kept out of persistence
    /// until then.
    var triggerLayoutRestorationItemIdentifiers = Set<String>()

    /// Stored so a burst of releases coalesces into one wait.
    var triggerReleaseRecacheTask: Task<Void, Never>?

    /// Items notch overflow moved to hidden. Transient and per display, so
    /// never persisted as hidden. Cleared when overflow ends, a non-notched
    /// apply restores them, or the user moves them.
    var notchOverflowEjectedUIDs = Set<String>()

    /// Whether notch overflow currently has items ejected into hidden.
    ///
    /// Inline expansion can't show ejected items; there's no room.
    var hasNotchOverflowEjectedItems: Bool {
        !notchOverflowEjectedUIDs.isEmpty
    }

    /// When the last continuous notch-overflow rebalance ejected items. Used
    /// only for the cooldown in rebalanceNotchOverflowIfNeeded(items:controlItems:).
    var lastNotchRebalanceTimestamp: Date?
    /// Placement preference for newly detected menu bar items.
    var newItemsPlacement = NewItemsPlacement.defaultValue

    /// Shared with ProfileManager and --reset-layout so they can't drift.
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

    private func loadKnownItemIdentifiers() {
        let key = LayoutStateKey.knownItemIdentifiers
        let defaults = Defaults.store
        if let stored = defaults.array(forKey: key) as? [String] {
            knownItemIdentifiers = Set(stored)
        }
    }

    func persistKnownItemIdentifiers() {
        let key = LayoutStateKey.knownItemIdentifiers
        let defaults = Defaults.store
        defaults.set(Array(knownItemIdentifiers), forKey: key)
    }

    private func loadPinnedBundleIDs() {
        let defaults = Defaults.store
        if let hidden = defaults.array(forKey: LayoutStateKey.pinnedHiddenBundleIDs) as? [String] {
            pinnedHiddenBundleIDs = Set(hidden)
        }
        if let alwaysHidden = defaults.array(forKey: LayoutStateKey.pinnedAlwaysHiddenBundleIDs) as? [String] {
            pinnedAlwaysHiddenBundleIDs = Set(alwaysHidden)
        }
    }

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

    func persistPendingRelocations() {
        let key = LayoutStateKey.pendingRelocations
        Defaults.store.set(pendingRelocations, forKey: key)
        let destKey = LayoutStateKey.pendingReturnDestinations
        Defaults.store.set(pendingReturnDestinations, forKey: destKey)
    }

    /// Control Center's current display names, for spotting localized ghosts
    /// in the saved order (#949). Covers languages the whitespace heuristic
    /// misses (Kontrollzentrum).
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
            // Repair unmatchable entries already on disk (#788, #815).
            // Migrate helper namespaces first, so they're rewritten rather
            // than pruned.
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

    private func persistNewItemsPlacementPreference() {
        Defaults.set(newItemsPlacement.sectionKey, forKey: .newItemsSection)
        if let data = try? JSONEncoder().encode(newItemsPlacement) {
            Defaults.set(data, forKey: .newItemsPlacementData)
        } else {
            Defaults.removeObject(forKey: .newItemsPlacementData)
        }
    }

    func persistSavedSectionOrder() {
        Defaults.store.set(savedSectionOrder, forKey: LayoutStateKey.savedSectionOrder)
    }

    // MARK: - Item Groups

    /// The group set to enforce, wrapped in the planner-facing shape.
    private var activeGroupSet: MenuBarItemGroupPolicy.GroupSet? {
        guard let appState else { return nil }
        let resolved = appState.itemGroupManager.groupSet
        guard !resolved.groups.isEmpty else { return nil }
        let set = MenuBarItemGroupPolicy.GroupSet(groups: resolved.groups.map(\.memberIdentifiers))
        return set.isEmpty ? nil : set
    }

    /// Applies the group bundling invariant to a per-section order.
    ///
    /// Mirrors macOS 27: a split group moves to the section holding most of
    /// its members (ties to the leftmost), in one contiguous run.
    func gatheredSectionOrder(_ order: [String: [String]]) -> [String: [String]] {
        guard let groups = activeGroupSet, !order.isEmpty else {
            return order
        }
        var sections = [MenuBarSection.Name: [String]]()
        var unconvertible = [String: [String]]()
        for (key, identifiers) in order {
            guard let name = sectionName(for: key) else {
                unconvertible[key] = identifiers
                continue
            }
            sections[name] = identifiers
        }
        guard !sections.isEmpty else { return order }

        let (gatheredSections, report) = MenuBarItemGroupPolicy.gather(groups: groups, inSections: sections)
        guard report != .noChange else {
            return order
        }

        // Seed sections empty so an emptied one stays present; restoring
        // its identifiers would duplicate the moved members.
        var result = [String: [String]]()
        for name in sections.keys {
            result[sectionKey(for: name)] = []
        }
        for (name, identifiers) in gatheredSections {
            result[sectionKey(for: name)] = identifiers
        }
        // Preserve any section whose key could not be converted.
        for (key, identifiers) in unconvertible {
            result[key] = identifiers
        }
        return result
    }

    /// Re-gathers groups in the saved order and moves the live items to
    /// match, after a group edit.
    func applyGroupOrderToLiveSections() async {
        guard appState != nil else { return }
        let gathered = gatheredSectionOrder(savedSectionOrder)
        guard gathered != savedSectionOrder, !savedSectionOrder.isEmpty else {
            return
        }
        savedSectionOrder = gathered
        persistSavedSectionOrder()

        // A user edit, so `automatic: false` applies it now. Exclude
        // trigger-controlled items as applySavedLayout does, or the apply
        // would fight the trigger.
        let liveItems = itemCache.managedItems
        let effectiveGathered = Self.savedOrderExcludingTriggerControlledIdentifiers(
            gathered,
            controlledIdentifiers: triggerControlledItemIdentifiers,
            knownBaseIdentifiers: Set(liveItems.map(\.tag.stableIdentifierBase)),
            knownLiveIdentifiers: Set(liveItems.map(\.uniqueIdentifier))
        )
        guard effectiveGathered.values.contains(where: { !$0.isEmpty }) else {
            MenuBarItemManager.diagLog.debug(
                "applyGroupOrderToLiveSections: skipping live apply, every entry is trigger-controlled"
            )
            return
        }
        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in effectiveGathered {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }
        let spec = ProfileLayoutSpec(
            pinnedHidden: pinnedHiddenBundleIDs,
            pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
            sectionOrder: effectiveGathered,
            itemSectionMap: itemSectionMap,
            itemOrder: effectiveGathered
        )
        MenuBarItemManager.diagLog.info("Applying updated group order to live sections")
        await applyProfileLayout(spec, source: .savedOrder, automatic: false)
    }

    /// Computes the per-section order saveSectionOrder would persist, without
    /// writing it. Shared with ProfileManager.captureCurrentLayout so a
    /// captured itemOrder keeps closed apps and drops transient items.
    ///
    /// - Excludes control items except the chevron, unresolved items, and
    ///   transient Control Center items.
    /// - Treats temporarily shown items as closed apps, keeping their section.
    /// - Merges closed-app entries so a slot survives a quit.
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

        /// The chevron is persisted so the planner can tell when macOS put an
        /// item on its wrong side. The hidden dividers' positions are implicit.
        func isPersistable(_ item: MenuBarItem) -> Bool {
            guard !isTriggerProtected(item) else { return false }
            if item.tag == .visibleControlItem {
                return true
            }
            // A misattributed module (#1027) would persist an identifier the
            // bar can never produce; the healed saved entry keeps its slot.
            if item.tag.isMisattributedControlCenterModule {
                return false
            }
            return !item.isControlItem && item.sourcePID != nil
        }

        // Ejected items still in hidden are treated as absent, keeping their
        // saved positions. One found elsewhere was moved by the user.
        let ejectedStillInHidden = notchOverflowEjectedUIDs.intersection(
            Set(cache[.hidden].map(\.uniqueIdentifier))
        )
        notchOverflowEjectedUIDs = ejectedStillInHidden

        // A refused item sits where nobody put it; keep its saved slot.
        let refusedIdentifiers = refusedMoveIdentifiers()

        var allCurrentIdentifiers = Set<String>()
        var allCurrentBaseIdentifiers = Set<String>()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where isPersistable(item) {
                guard !pendingRehideTagIDs.contains(item.tag.tagIdentifier) else { continue }
                guard !ejectedStillInHidden.contains(item.uniqueIdentifier) else { continue }
                guard !refusedIdentifiers.contains(item.uniqueIdentifier) else { continue }
                // Track the base so stale transient entries get pruned below.
                let baseID = item.tag.stableIdentifierBase
                if !triggerProtectedBaseIdentifiers.contains(baseID) {
                    allCurrentBaseIdentifiers.insert(baseID)
                }
                // Also exclude unresolved Item-N: transient windows before
                // resolution, or items degraded by an XPC failure (#784).
                guard !item.isTransientControlCenterItem,
                      !item.hasProvisionalIdentity
                else { continue }
                allCurrentIdentifiers.insert(item.uniqueIdentifier)
            }
        }

        for section in MenuBarSection.Name.allCases {
            let currentInSection = cache[section]
                .filter {
                    isPersistable($0) &&
                        !$0.isTransientControlCenterItem &&
                        !$0.hasProvisionalIdentity &&
                        !pendingRehideTagIDs.contains($0.tag.tagIdentifier) &&
                        !ejectedStillInHidden.contains($0.uniqueIdentifier) &&
                        !refusedIdentifiers.contains($0.uniqueIdentifier)
                }
                .map(\.uniqueIdentifier)

            let oldSavedForSection = savedSectionOrder[sectionKey(for: section)] ?? []

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

    /// Persists computeSectionOrder's result, skipping unchanged orders.
    func saveSectionOrder(from cache: ItemCache) {
        // A failed XPC resolution collapses items into Control Center
        // identifiers; saving that would poison the layout (#784).
        let managedItems = cache.managedItems
        let unresolvedCount = managedItems.count { $0.sourcePID == nil }
        if Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedCount, itemCount: managedItems.count) {
            MenuBarItemManager.diagLog.info(
                "saveSectionOrder: skipping, \(unresolvedCount)/\(managedItems.count) items have unresolved sourcePIDs"
            )
            return
        }
        let computedOrder = computeSectionOrder(from: cache)
        // Gathered here so everything downstream sees contiguous groups.
        let newOrder = gatheredSectionOrder(computedOrder)
        guard newOrder != savedSectionOrder else { return }
        let previousOrder = savedSectionOrder
        savedSectionOrder = newOrder
        persistSavedSectionOrder()
        MenuBarItemManager.diagLog.debug("Saved section order: \(newOrder.mapValues(\.count))")
        // Separate from the counts, which stayed correct through #885.
        MenuBarItemManager.diagLog.info(
            "Saved section order changed: \(Self.sectionOrderChangeSummary(from: previousOrder, to: newOrder))"
        )
    }

    /// Sorts one section alphabetically by display name, saves it, and
    /// applies it. Returns the sorted identifiers, or nil if empty.
    @discardableResult
    func sortSection(_ section: MenuBarSection.Name) -> [String]? {
        let items = itemCache.managedItems(for: section)
        guard !items.isEmpty else { return nil }

        // Mirrors computeSectionOrder's filter, here and below.
        let pendingRehideTags = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: pendingReturnDestinations,
            pendingRelocations: pendingRelocations,
            waitForRelaunchPrefix: Self.waitForRelaunchPrefix
        )
        let ejectedStillInHidden = notchOverflowEjectedUIDs.intersection(
            Set(itemCache[.hidden].map(\.uniqueIdentifier))
        )
        let refusedIdentifiers = refusedMoveIdentifiers()
        func isSortPersistable(_ item: MenuBarItem) -> Bool {
            guard !Self.isTriggerProtected(
                item.uniqueIdentifier,
                by: triggerControlledItemIdentifiers.union(triggerLayoutRestorationItemIdentifiers),
                knownBaseIdentifiers: Set(itemCache.managedItems.map(\.tag.stableIdentifierBase)),
                knownLiveIdentifiers: Set(itemCache.managedItems.map(\.uniqueIdentifier))
            ) else { return false }
            if item.tag == .visibleControlItem {
                return true
            }
            guard !item.tag.isMisattributedControlCenterModule else { return false }
            return !item.isControlItem && item.sourcePID != nil
        }
        let persistableItems = items.filter {
            isSortPersistable($0)
                && !$0.isTransientControlCenterItem
                && !$0.hasProvisionalIdentity
                && !pendingRehideTags.contains($0.tag.tagIdentifier)
                && !ejectedStillInHidden.contains($0.uniqueIdentifier)
                && !refusedIdentifiers.contains($0.uniqueIdentifier)
        }
        guard !persistableItems.isEmpty else { return nil }
        // Merge with the saved order so closed apps keep their slots.
        let sortedLive = LayoutSolver.sortedSectionIdentifiers(persistableItems) { $0.displayName }
        guard !sortedLive.isEmpty else { return nil }

        let key = sectionKey(for: section)
        let oldSavedForSection = savedSectionOrder[key] ?? []

        // Tells a closed app from one moved to another section.
        let knownBaseIdentifiers = Set(itemCache.managedItems.map(\.tag.stableIdentifierBase))
        let triggerProtectedIdentifiers = triggerControlledItemIdentifiers
            .union(triggerLayoutRestorationItemIdentifiers)
        let triggerProtectedBaseIdentifiers = Set(triggerProtectedIdentifiers.compactMap {
            MenuBarItemTag.resolvedBaseIdentifier(
                for: $0,
                knownBaseIdentifiers: knownBaseIdentifiers
            )
        })
        var allCurrentIdentifiers = Set<String>()
        var allCurrentBaseIdentifiers = Set<String>()
        for item in itemCache.managedItems {
            guard isSortPersistable(item) else { continue }
            guard !pendingRehideTags.contains(item.tag.tagIdentifier) else { continue }
            guard !ejectedStillInHidden.contains(item.uniqueIdentifier) else { continue }
            guard !refusedIdentifiers.contains(item.uniqueIdentifier) else { continue }
            guard !item.isTransientControlCenterItem, !item.hasProvisionalIdentity else { continue }
            allCurrentIdentifiers.insert(item.uniqueIdentifier)
            let baseID = item.tag.stableIdentifierBase
            if !triggerProtectedBaseIdentifiers.contains(baseID) {
                allCurrentBaseIdentifiers.insert(baseID)
            }
        }

        let merged = LayoutSolver.planSectionOrder(
            currentInSection: sortedLive,
            oldSavedForSection: oldSavedForSection,
            allCurrentIdentifiers: allCurrentIdentifiers,
            allCurrentBaseIdentifiers: allCurrentBaseIdentifiers
        )
        guard !merged.isEmpty else { return nil }
        guard savedSectionOrder[key] != merged else { return merged }

        let previousOrder = savedSectionOrder
        var newOrder = savedSectionOrder
        newOrder[key] = merged
        savedSectionOrder = newOrder
        persistSavedSectionOrder()
        MenuBarItemManager.diagLog.info("Sorted section \(key) alphabetically: \(merged.count) identifier(s) (\(sortedLive.count) live + retained closed-app entries)")

        // reapplyActiveProfile reads the on-disk profile, so write the order
        // there first; on failure roll savedSectionOrder back. Without a
        // profile, a cache cycle applies the saved layout.
        if let profileManager = appState?.profileManager,
           profileManager.activeProfileID != nil
        {
            guard profileManager.updateActiveProfileSectionOrder(section, identifiers: merged) else {
                savedSectionOrder = previousOrder
                persistSavedSectionOrder()
                MenuBarItemManager.diagLog.error("sortSection: profile update failed; rolled back savedSectionOrder")
                return nil
            }
            profileManager.reapplyActiveProfile(enforceConcealedSectionOrder: true)
        } else {
            // The saved-layout apply relaxes concealed-section order by
            // default, so a hidden sort would never reach the bar. One-shot.
            enforceConcealedSectionOrderOnNextSavedApply = true
            Task { [weak self] in
                await self?.cacheItemsRegardless()
            }
        }
        return merged
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

    /// Prefix used in pendingRelocations values to mark items whose rehide
    /// failed terminally in the current session. The suffix is the item's
    /// windowID at the time of failure, used to detect app relaunches.
    private static let waitForRelaunchPrefix = "waitForRelaunch:"

    /// An app running since boot never changes windowID, so without this cap
    /// its sentinel keeps the item out of savedSectionOrder forever.
    static let waitForRelaunchAgeCap: Duration = .seconds(86400)

    /// Suppresses same-session moves. A relaunch's new windowID clears it, and
    /// the timestamp lets ``planPendingMove`` age it out.
    func waitForRelaunchValue(windowID: CGWindowID, section: MenuBarSection.Name, setAt: Date = Date()) -> String {
        "\(Self.waitForRelaunchPrefix)\(windowID):\(sectionKey(for: section)):\(Int(setAt.timeIntervalSince1970))"
    }

    /// Returns nil for a plain section key. setAt is nil for the older,
    /// untimestamped format, which ``planPendingMove`` treats as stale.
    func parseWaitForRelaunch(_ value: String) -> (windowID: CGWindowID, section: MenuBarSection.Name, setAt: Date?)? {
        guard value.hasPrefix(Self.waitForRelaunchPrefix) else { return nil }
        let payload = value.dropFirst(Self.waitForRelaunchPrefix.count)
        // Format: "<windowID>:<sectionKey>[:<unixTime>]"
        let parts = payload.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let wid = CGWindowID(parts[0]),
              let section = sectionName(for: String(parts[1]))
        else { return nil }
        let setAt: Date? = if parts.count >= 3, let secs = Int(parts[2]) {
            Date(timeIntervalSince1970: TimeInterval(secs))
        } else {
            nil
        }
        return (wid, section, setAt)
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

        // The anchor is gone (e.g. ejected by notch overflow); place the
        // badge against its nearest surviving profile sibling instead.
        if let nearestIndex = badgeIndexFromNearestProfileSibling(
            in: section,
            itemIdentifiers: itemIdentifiers
        ) {
            return nearestIndex
        }

        return defaultNewItemsBadgeIndex(in: section, itemCount: itemIdentifiers.count)
    }

    /// Walks the profile order outward from the missing anchor, in the saved
    /// relation's direction first. Nil when no profile or sibling applies.
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
    ///   - anchorPos: The anchor's position within profileOrder.
    ///   - itemIdentifiers: The identifiers currently in the section.
    ///   - walkLeftFirst: Whether the badge sat left of the anchor.
    ///
    /// - Returns: An index into itemIdentifiers, or nil when no sibling
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

    /// Applies a previously captured NewItemsPlacement (from a profile),
    /// clamping to the hidden section when the always-hidden section is
    /// disabled. Persists the updated preference.
    ///
    /// When clamping, re-anchor left of the rightmost hidden item, the spot
    /// users reach first, rather than the default leftmost slot.
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
                // Hidden is empty; drop the stale anchor.
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

    func performSetup(with appState: AppState) async {
        MenuBarItemManager.diagLog.debug("performSetup: starting MenuBarItemManager setup")
        self.appState = appState
        loadKnownItemIdentifiers()
        loadPinnedBundleIDs()
        loadPendingRelocations()
        loadSavedSectionOrder()
        loadNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("performSetup: loaded \(knownItemIdentifiers.count) known identifiers, \(pinnedHiddenBundleIDs.count) pinned hidden, \(pinnedAlwaysHiddenBundleIDs.count) pinned always-hidden, \(savedSectionOrder.values.map(\.count)) saved order entries")
        // On first launch, keep everything hidden until the user interacts.
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
                await cacheItemsRegardless(options: .init(resolveSourcePID: false))
                if itemCache.displayID != nil {
                    if attempt > 1 {
                        MenuBarItemManager.diagLog.debug(
                            "performSetup: fast initial cache succeeded on retry \(attempt)"
                        )
                    }
                    // Resolve PIDs concurrently so restore isn't blocked.
                    Task { @MainActor [weak self] in
                        await self?.cacheItemsRegardless(options: .init(resolveSourcePID: true))
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
        // At login many apps load over ~30 s, and restoring on each launch
        // produces an "icon parade".
        startSettlingPeriod(reason: "performSetup")
        MenuBarItemManager.diagLog.debug("performSetup: MenuBarItemManager setup complete")
    }

    /// Suppresses restores and saves until the bar stabilizes, then runs two
    /// final cache passes. Exits when every expected bundle ID is present
    /// with resolved PIDs, or, with no expected set, when the item count is
    /// stable. maxDuration is generous since some apps take tens of seconds
    /// to reattach. Re-entry keeps the later deadline.
    func startSettlingPeriod(
        reason: String,
        expectedBundleIDs: Set<String> = [],
        maxDuration: Duration = .seconds(60)
    ) {
        let mergedExpected = settlingExpectedBundleIDs.union(expectedBundleIDs)
        let incomingKind: SettlingKind = if !mergedExpected.isEmpty {
            .expectedSet
        } else if reason == "performSetup" {
            .cold
        } else {
            .preflight
        }

        // Boot race: a preflight must not replace a cold or expected-set
        // settling. Keep the merged expected set for later calls.
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
        // The cancelled task leaves shared state to this call.
        startupSettlingTask?.cancel()
        isInStartupSettling = true
        didAttemptEarlySavedLayoutApply = false
        MenuBarItemManager.diagLog.debug("\(reason): settling period started (max duration: \(maxDuration))")
        // @MainActor keeps notification-driven cycles from interleaving.
        startupSettlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.initialCacheTask?.value

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
                await cacheItemsRegardless(options: .init(skipRecentMoveCheck: true, resolveSourcePID: true))
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
                    // A dropped pass would read as stable without looking.
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

            // A display-bound profile is the source of truth. Await its apply
            // so applySavedLayout below can't race it.
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
            // Settling moves may have stamped the move timestamp. The flag only
            // clears the 1 s gate; applySavedLayout's 5 s gate needs the bypass
            // carried through the recache relocateNewLeftmostItems schedules.
            await cacheItemsRegardless(
                options: .init(
                    skipRecentMoveCheck: true,
                    resolveSourcePID: false,
                    bypassSavedLayoutCooldown: true
                )
            )
            // Resolves source PIDs; never suppressed by the move cooldown.
            await cacheItemsRegardless(
                options: .init(
                    skipRecentMoveCheck: true,
                    resolveSourcePID: true,
                    bypassSavedLayoutCooldown: true
                )
            )
        }
    }

    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        // Debounced: one edit lands as several mutations, and each re-order
        // costs a plist write and a move batch.
        groupOrderObservationTask?.cancel()
        groupOrderObservationTask = Task { [weak self, weak appState] in
            let changes = Observations { [weak appState] in
                appState?.itemGroupManager.groupSet
            }
            var isFirst = true
            for await _ in changes {
                guard let self else { return }
                if isFirst {
                    isFirst = false
                    continue
                }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await self.applyGroupOrderToLiveSections()
            }
        }

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

            // A tracked app relaunching (e.g. an update) churns the bar; settle
            // on its bundle ID, or the bulk apply sweeps hidden items into
            // visible. Usually exits in ~3 s.
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
                // Many apps register their status item over 1 s after launch.
                // Re-check at +2.5 s and +5 s; cheap when nothing changed.
                guard await (try? Task.sleep(for: .seconds(2.5))) != nil else { return }
                await self?.cacheItemsIfNeeded()
                guard await (try? Task.sleep(for: .seconds(2.5))) != nil else { return }
                await self?.cacheItemsIfNeeded()
            }
        }
        .store(in: &c)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )
        .debounce(for: 1, scheduler: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self else { return }
            // So a relaunch doesn't get the dead PID's cached icon.
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            {
                MenuBarItemIconFallback.forgetIcon(forPID: app.processIdentifier)
            }
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

        // Refresh the image cache when the Menu Bar Layout pane becomes
        // presented, via either property changing.
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

        // Catches late items (OneDrive) and the brief marker windows source-PID
        // resolution needs. Cheap when window IDs are unchanged.
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
    /// Clears the failed-batch save latch and any pending divergence reading.
    func recordExternalMoveOperation() {
        lastMoveOperationTimestamp = .now
        lastUserMoveOperationTimestamp = .now
        pendingDivergenceObservedAt = nil
        recordBulkApplyOutcome(unenactedMoveCount: 0, isCompletedApply: false)
    }

    /// Whether the save gate's user-move exemption applies: it must, and only,
    /// when the most recent move was the user's own.
    ///
    /// Compares recency, not presence: a user move followed by an automatic
    /// one must not exempt Thaw's own arrangement.
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
