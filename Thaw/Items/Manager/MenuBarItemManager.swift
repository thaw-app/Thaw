//
//  MenuBarItemManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Combine
import CoreGraphics
import MenuBarModel
import Observation
import ThawLayout

/// Owns Thaw's picture of the menu bar and everything that changes it.
///
/// Two responsibilities meet here and pull against each other: observing
/// (enumerate the bar, work out each item's section, publish itemCache) and
/// acting (move items so the bar matches what the user asked for). The bar is
/// briefly wrong while it is being corrected, so most of the state on this
/// type exists to keep a mid-flight snapshot from being mistaken for the
/// user's intent.
///
/// The implementation is split across extensions by concern: caching, moving,
/// clicking, temporary reveals, layout reset, and divider ordering.
@MainActor
@Observable
final class MenuBarItemManager {
    /// Cursor-hide watchdog for macOS 27 layout moves. Sized for the worst
    /// legitimate drag session, eight engine attempts at about 2 s each
    /// (gesture, settle, verification walk), plus margin. A watchdog that
    /// fires mid-session force-shows the cursor and zeroes the hide count, so
    /// every later drag in the pass runs fully visible. Callers can extend it
    /// per move; MouseHelpers never shortens an armed watchdog.
    static let layoutWatchdogTimeout: Duration = .seconds(25)

    /// Delay between relocation/restore moves and the subsequent recache,
    /// giving macOS time to settle menu bar item positions.
    static let uiSettleDelay: Duration = .milliseconds(300)

    /// Minimum time cold-boot settling waits before declaring the bar stable.
    static var startupMinimumSettlingDuration: Duration {
        Constants.MenuBarTuning.startupMenuBarHostSettleDelay
    }

    /// Delay before the first AX scan after launch.
    private static var startupInitialScanDelay: Duration {
        startupMinimumSettlingDuration
    }

    /// Retry interval when Thaw's control items are not yet visible.
    private static var startupControlItemRetryDelay: Duration {
        Constants.MenuBarTuning.startupMenuBarHostSettleDelay
    }

    /// Backing storage for itemCache.
    ///
    /// Split from the facade so that every write runs through one place that
    /// can maintain the narrowed properties below. @Observable rules out the
    /// obvious didSet: its accessor macro has nowhere to expand to on a
    /// property that already observes itself.
    private var storedItemCache = ItemCache(displayID: nil)

    /// The bar as Thaw last understood it: every managed item, filed under the
    /// section it belongs to. The layout bars, the search panel, and the image
    /// cache all read from this rather than enumerating for themselves.
    var itemCache: ItemCache {
        get { storedItemCache }
        set {
            storedItemCache = newValue
            refreshCacheDerivedState()
        }
    }

    /// The items Thaw manages, across every section.
    ///
    /// Callers want the inventory, not the cache that holds it. Exposing the
    /// slice here keeps itemCache an implementation detail of the manager
    /// rather than something every consumer has to walk through, and leaves
    /// one place to change if the inventory is ever stored differently.
    var managedItems: [MenuBarItem] {
        itemCache.managedItems
    }

    /// The dividers as of the last cache walk.
    ///
    /// MenuBarItemCache does not retain them, its initializer removes them
    /// from the item list, so callers that need a divider outside a walk
    /// would otherwise have to enumerate the bar again to find one.
    var lastKnownControlItems: ControlItemPair?

    @ObservationIgnored var lastVisibleControlDiagnosticState: String?

    /// Whether Thaw manages no items at all.
    ///
    /// Stored rather than derived: a derived answer depends on the whole
    /// cache, which every accessibility walk reassigns even when only an
    /// item's bounds shifted by a fraction of a point, so any view asking this
    /// yes-or-no question would rebuild on every walk.
    private(set) var hasNoManagedItems = true

    /// The managed items' tags, in bar order, across every section.
    ///
    /// Membership and order with the geometry left out. Views that care only
    /// about which items exist, not where they sit, observe this instead of
    /// the cache and so are not woken by jitter.
    private(set) var managedItemTags: [MenuBarItemTag] = []

    /// Visible items macOS is not drawing on the bar. See
    /// refreshItemsNotShownOnBar().
    var itemsNotShownOnBarTags: Set<MenuBarItemTag> = []

    /// Consecutive passes each visible item has looked unshown.
    @ObservationIgnored var notShownStreaks: [MenuBarItemTag: Int] = [:]

    /// Canonical identifiers of the items in the Thaw Bar Only state. See
    /// moveToThawBarOnly(_:appState:).
    var thawBarOnlyIdentifiers: Set<String> = MenuBarItemManager.loadThawBarOnlyIdentifiers()

    /// Thaw Bar Only items already sent back to Hidden this session, so a
    /// move the section controller refuses is not retried on every scan. See
    /// keepThawBarOnlyItemsHidden().
    @ObservationIgnored var thawBarOnlyItemsReturnedToHidden = Set<String>()

    /// The menus a click on each item opened, by canonical identifier. Only
    /// windows that appeared with the click count, so a window the owner
    /// keeps on screen at menu level is never taken for an open menu.
    @ObservationIgnored var menusOpenedByClick = [String: Set<CGWindowID>]()

    /// Recomputes the narrowed views of the cache after a write.
    ///
    /// Each assignment is guarded against writing an equal value back:
    /// Observation notifies on write, not on change, so an unguarded
    /// assignment would hand back exactly the invalidation this avoids.
    private func refreshCacheDerivedState() {
        let isEmpty = storedItemCache.isEmpty
        if hasNoManagedItems != isEmpty {
            hasNoManagedItems = isEmpty
        }
        let tags = storedItemCache.managedItems.map(\.tag)
        if managedItemTags != tags {
            managedItemTags = tags
        }
        refreshItemsNotShownOnBar()
    }

    /// The display the current inventory was enumerated on, or nil before
    /// the first successful walk.
    ///
    /// Item bounds are only meaningful on the display they were read from, so
    /// consumers that reason about geometry need this alongside the items.
    var itemDisplayID: CGDirectDisplayID? {
        itemCache.displayID
    }

    /// The items Thaw manages in section.
    func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
        itemCache.managedItems(for: section)
    }

    /// The managed item carrying tag, if Thaw still knows about it.
    ///
    /// A lookup, unlike a scan of managedItems, does not need the
    /// inventory flattened first.
    func managedItem(withTag tag: MenuBarItemTag) -> MenuBarItem? {
        itemCache.item(withTag: tag)
    }

    /// The managed item backed by windowID, if Thaw still knows about it.
    func managedItem(withWindowID windowID: CGWindowID) -> MenuBarItem? {
        itemCache.item(withWindowID: windowID)
    }

    /// On-screen items from the most recent cache refresh AX walk. Readers hold
    /// the snapshot directly instead of reaching through this manager.
    let onScreenItemSnapshot = OnScreenItemSnapshot()

    /// Whether Thaw's own dividers went missing from the last enumeration.
    /// Surfaced to the UI, because without them the sections cannot be measured
    /// and the layout panes have nothing meaningful to show.
    var areControlItemsMissing = false

    /// Apps whose menu bar items Thaw expected and cannot see; see
    /// UnseenMenuBarHosts. Surfaced so the Layout pane can say why those
    /// items sit outside the menu bar look.
    var unseenHostBundleIDs: Set<String> = []

    /// Detection state behind unseenHostBundleIDs, seeded from the
    /// previous session on first use.
    var unseenHosts: UnseenMenuBarHosts?

    /// What unseenHosts last wrote, so an unchanged state is not rewritten
    /// on every cache pass.
    var lastPersistedExpectedHosts: [String: Int]?

    /// Diagnostic logger for the menu bar item manager.
    static nonisolated let diagLog = DiagLog(category: "MenuBarItemManager")

    /// Pauses reordering when activity runs away: icon dancing or repeated
    /// synthetic drags. Consulted by every reorder entry point.
    let moveCircuitBreaker = MoveCircuitBreaker()

    /// Admits one synthetic event sequence at a time. Two overlapping sequences
    /// interleave their events at the Window Server and neither lands.
    let eventSemaphore = SimpleSemaphore(value: 1)

    /// Serializes moves and section transitions, including pre-seat writes,
    /// verification, and the assignment commit.
    ///
    /// eventSemaphore only guards synthetic-drag posting, so two concurrent
    /// moves (a layout-pane drop and a convergence pass, or two convergence
    /// passes) would interleave their write, verify and drag phases and fight
    /// over one item, each attempt seeing the bar re-sorted by the other and
    /// never verifying. One move at a time makes each attempt judge a stable
    /// bar, and a superseded duplicate re-checks live position on entry and
    /// no-ops via itemHasCorrectPosition.
    let moveSerialSemaphore = SimpleSemaphore(value: 1)

    /// What the previous cache pass observed, for the next one to compare against.
    let cacheCycleState = CacheCycleState()

    /// When the bar was last disturbed by a move, Thaw's own or the user's.
    /// A cache pass taken too soon after one records positions that are still
    /// settling, so several paths consult this before trusting an enumeration.
    /// The tracker is the shared read surface: capture and search hold it
    /// directly instead of reaching through this manager.
    let moveActivity = MoveOperationTracker()

    /// In-memory record of what the reorder pipeline did, rendered by the
    /// Privacy pane's move inspector. Written by the pipeline itself so the
    /// pane cannot describe a move any other way than it happened.
    let moveMonitor = MovePipelineMonitor()

    /// How many preferred-position moves are waiting to be observed on the bar.
    ///
    /// A structural re-lay rewrites every weight in the permutation, so one
    /// landing inside a move's verification window renumbers the very slot the
    /// move just claimed. The move can then never be seen to have happened: the
    /// caller declines the write, falls back to the synthetic Command-drag, and
    /// the icon sits wherever the re-lay left it until the drag finishes.
    ///
    /// scheduleStructuralNormalization(after:) already waits moves
    /// out before re-laying. This covers the reveal-time caller, which does
    /// not. A count rather than a flag because reveals and moves overlap.
    var pendingPreferredPositionMoves = 0
    var layoutPublication = MenuBarLayoutPublicationState()

    /// The lock state the last move refusal check saw. See
    /// refuseMenuBarMutationWhileScreenLocked(_:).
    @ObservationIgnored var screenLockTransitions = ScreenLockTransitions()

    /// Owners whose moves were refused as unresponsive, so a hung app is logged
    /// once rather than on every pass. Cleared once the owner answers again.
    @ObservationIgnored var unresponsiveMoveOwners = Set<pid_t>()

    private var notificationCenterLayoutToken: UUID?
    private var notificationCenterLayoutSettleTask: Task<Void, Never>?

    var isNotificationCenterLayoutSuspended: Bool {
        notificationCenterLayoutToken != nil
    }

    func beginNotificationCenterLayoutSuspension() {
        notificationCenterLayoutSettleTask?.cancel()
        notificationCenterLayoutSettleTask = nil
        if notificationCenterLayoutToken == nil {
            layoutPublication.beginMutation()
        } else {
            layoutPublication.invalidate()
        }
        notificationCenterLayoutToken = UUID()
        postRestrictionRepairTask?.cancel()
        postRestrictionRepairTask = nil
        postRestrictionRepairNeedsRerun = false
        structuralNormalizationTask?.cancel()
        structuralNormalizationTask = nil
        deferredLayoutReconcileTask?.cancel()
        deferredLayoutReconcileTask = nil
    }

    @discardableResult
    func endNotificationCenterLayoutSuspension(
        settle: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(1200))
        }
    ) -> Task<Void, Never> {
        let token = notificationCenterLayoutToken
        notificationCenterLayoutSettleTask?.cancel()
        let task = Task { @MainActor [weak self] in
            do { try await settle() } catch { return }
            guard let self, let token, !Task.isCancelled,
                  notificationCenterLayoutToken == token
            else { return }
            notificationCenterLayoutToken = nil
            notificationCenterLayoutSettleTask = nil
            layoutPublication.endMutation()
            noteRestrictionChange()
        }
        notificationCenterLayoutSettleTask = task
        return task
    }

    /// Timestamp of the most recent runtime-kit restriction reflow.
    /// applySavedLayout is suppressed briefly afterward so a transient
    /// post-reflow geometry pass is not mistaken for real layout drift.
    var lastRestrictionChangeTimestamp: ContinuousClock.Instant?

    /// How long to defer automatic visible-section reorders after a restriction reflow.
    static let restrictionChangeLayoutSettleWindow: Duration = .seconds(10)

    /// Deferred repair after a restriction reflow. Concealing one bundle
    /// reshuffles the whole bar; visible-assigned neighbours from a multi-item
    /// bundle can land in the overflow/parked band and never recover
    /// because the layout-bar move cooldown blocks applySavedLayout.
    var postRestrictionRepairTask: Task<Void, Never>?

    /// Re-runs the saved-layout reconciler once a transient guard expires.
    ///
    /// applySavedLayout declines for reasons that clear on their own: a move
    /// cooldown, the restriction-reflow settle window, an in-flight ⌘-drag.
    /// While the user is editing, every drop re-arms the 5 s cooldown and the
    /// 10 s settle, so waiting for a cache cycle to land in a clear window
    /// would never run the reconciler. Scheduling against the blocking
    /// window's own expiry turns a decline into a deferral.
    private var deferredLayoutReconcileTask: Task<Void, Never>?

    /// When the pending deferred reconcile is due, so a second decline can keep
    /// the earlier retry instead of pushing it further out.
    private var deferredLayoutReconcileDue: ContinuousClock.Instant?

    /// Consecutive deferrals without the reconciler managing to run. Bounded
    /// because a reconcile whose own moves re-arm the move cooldown would
    /// otherwise reschedule itself forever.
    private var deferredLayoutReconcileCount = 0

    /// Consecutive deferrals allowed before giving up until the next edit.
    private static let deferredLayoutReconcileLimit = 5

    /// Set while a post-restriction repair pass is executing.
    var isRunningPostRestrictionRepair = false

    /// A restriction change arrived while a pass was already running, so one
    /// more pass is owed once the current one finishes.
    var postRestrictionRepairNeedsRerun = false

    /// Timestamps of recent macOS 27 section-order move failures, keyed by
    /// "<item identity>|<destination>". An anchored system item (e.g.
    /// Sound, Control Center) can sit between two items that a saved order
    /// wants adjacent, making the move permanently unachievable via the
    /// synthetic Command-drag. Without this backoff, applySavedLayout
    /// re-detects the divergence every cache cycle and re-dispatches the same
    /// doomed move forever, hijacking the cursor and disturbing the dragged
    /// item's AX and rendering state.
    var recentMoveFailures = [String: ContinuousClock.Instant]()

    /// How long to suppress retrying a macOS 27 section-order move after it
    /// fails, before giving the achievable-order solver another chance.
    static let moveFailureBackoff: Duration = .seconds(30)

    var recentItemMoveFailures = [String: ItemMoveFailureRecord]()

    /// Consecutive verify-failures for one item→target that trip the breaker.
    static let itemMoveFailureThreshold = 3

    /// How long an item→target stays suppressed once the breaker trips.
    static let itemMoveFailureCooldown: Duration = .seconds(30)

    /// Count of user-initiated reorders currently queued on (or holding)
    /// moveSerialSemaphore. The automatic per-pair reconcile loop in
    /// applySectionItemOrder(sections:controller:whileRevealing:repairAfterRestriction:visibleOrderOverride:reason:preferredMoveUIDs:)
    /// polls this between pairs and stops issuing further background moves while
    /// it is non-zero, so a user's layout-pane drop is not stuck behind a
    /// multi-second background drag on the serial gate. The in-flight drag is
    /// allowed to finish, since cutting a gesture mid-flight corrupts the bar;
    /// only the next pair is withheld.
    var pendingUserReorderCount = 0

    /// When the ambient applySavedLayout pass last attempted to restore the
    /// macOS 27 visible control's order, regardless of the planned destination or
    /// outcome. See restoreVisibleControlOrder and
    /// visibleControlRestoreCooldown.
    var lastVisibleControlRestoreAttempt: ContinuousClock.Instant?

    /// How long to leave the visible control alone after an ambient restore
    /// attempt. The restore runs on every cache tick, and when MenuBarAgent
    /// refuses or reverts the placement, moveFailureBackoff cannot
    /// suppress the retries: visibleControlRestoreMove keeps proposing a
    /// different neighbour, so every pass mints a fresh backoff key and Thaw
    /// re-nudges its own icon several times a second. The cooldown caps that
    /// at one nudge per window. A restore that sticks is never re-attempted,
    /// so the cooldown only bites during a thrash.
    static let visibleControlRestoreCooldown: Duration = .seconds(30)

    /// Nominal width used for the macOS 27 overflow budget when an item's AX
    /// bounds have collapsed to an untrusted sliver (see minimumTrustedGlyphWidth).
    /// Matches the standard status-item footprint so the budget approximates the
    /// real rendered width rather than the collapsed measurement.
    static nonisolated let nominalStatusItemWidth: CGFloat = 24

    /// Width to charge a non-control item against the macOS 27 overflow budget.
    ///
    /// macOS 27 collapses hidden/overflowed item AX bounds to a sliver, so the
    /// measured width understates the real footprint and deflates the budget's
    /// profile baseline. Below the trust threshold the item is charged a nominal
    /// status-item width instead; otherwise the measured width is used as-is.
    static nonisolated func budgetWidth(forMeasuredWidth measured: CGFloat) -> CGFloat {
        measured < MenuBarItemImageCache.minimumTrustedGlyphWidth ? nominalStatusItemWidth : measured
    }

    /// The most budget a notch-covered control item may take back. Past five
    /// items' worth, whatever still covers the icon is not a full bar, and
    /// conceal-until-it-shows would empty the visible section.
    static nonisolated let maximumNotchOcclusionDeficit: CGFloat = nominalStatusItemWidth * 5

    /// The overflow budget to withhold for notch-covered control items.
    ///
    /// Each pass that finds a control item under the notch withholds its width
    /// plus one nominal item on top of what earlier passes withheld, so the
    /// conceal set grows until the icon clears the notch. The deficit then
    /// holds while the same items compete for the bar, counting the ones it
    /// concealed, and is dropped once an item arrives or leaves.
    static nonisolated func notchOcclusionDeficit(
        previous: (width: CGFloat, visibleUIDs: Set<String>)?,
        occludedControlWidth: CGFloat,
        visibleUIDs: Set<String>,
        overflowUIDs: Set<String>
    ) -> (width: CGFloat, visibleUIDs: Set<String>)? {
        let membership = visibleUIDs.union(overflowUIDs)
        let carried = previous.flatMap { $0.visibleUIDs == membership ? $0.width : nil } ?? 0
        let width = occludedControlWidth > 0
            ? min(maximumNotchOcclusionDeficit, carried + occludedControlWidth + nominalStatusItemWidth)
            : carried
        return width > 0 ? (width, membership) : nil
    }

    /// The overflow budget to withhold for Visible items macOS did not draw.
    ///
    /// On a full bar, a notched one in particular, macOS parks the items that
    /// do not fit at x == -1 while the modeled budget can still show hundreds
    /// of points of headroom. Parked items are proof the lane holds exactly
    /// what it seats, so the pass that finds them withholds the whole modeled
    /// headroom plus their width and gaps: the planner then conceals that much
    /// from the left of Visible. A fixed per-item allowance was not enough,
    /// since the model's error can be larger than any number of items.
    ///
    /// The deficit holds while the same items compete for the bar and is
    /// dropped once an item arrives or leaves.
    ///
    /// Parked items only count while macOS shows its own overflow control.
    /// An app switched off in System Settings parks at x == -1 too, and no
    /// amount of concealing brings it back.
    static nonisolated func parkedLaneDeficit(
        previous: (width: CGFloat, visibleUIDs: Set<String>)?,
        parkedWidths: [CGFloat],
        isNativeOverflowActive: Bool,
        modeledHeadroom: CGFloat,
        visibleUIDs: Set<String>,
        overflowUIDs: Set<String>
    ) -> (width: CGFloat, visibleUIDs: Set<String>)? {
        let membership = visibleUIDs.union(overflowUIDs)
        let carried = previous.flatMap { $0.visibleUIDs == membership ? $0.width : nil } ?? 0
        guard isNativeOverflowActive, !parkedWidths.isEmpty else {
            return carried > 0 ? (carried, membership) : nil
        }
        let parked = parkedWidths.reduce(CGFloat.zero) { $0 + budgetWidth(forMeasuredWidth: $1) + 8 }
        let width = max(carried, max(0, modeledHeadroom) + parked)
        return width > 0 ? (width, membership) : nil
    }

    /// The single record of which items have been failing, and how.
    ///
    /// This ledger bounds how long one operation retries an unresponsive owner
    /// and remembers a cannotComplete verdict across launches. It does not
    /// gate bulk apply: on macOS 27 that skip is the destination-scoped
    /// recentMoveFailures backoff plus the item-scoped circuit
    /// breaker (isItemMoveCircuitBreakerTripped(key:)), both checked in
    /// applySectionItemOrder.
    let failureLedger = MenuBarItemFailureLedger()

    /// Per-item response times learned from previous clicks. See
    /// updateClickOperationTimeout(_:for:).
    var clickOperationTimeouts = [MenuBarItemTag: Duration]()
    /// Admits one cache pass at a time; see CacheGate.
    let cacheGate = CacheGate()

    /// Pending self-terminating coalesced cache rerun (see scheduleCoalescedCacheRerun()).
    var coalescedCacheRerunTask: Task<Void, Never>?

    /// Pending membership read after a ⌘-drag; see
    /// scheduleObservedMembershipAdoption(reason:).
    var manualMembershipTask: Task<Void, Never>?

    /// When the user's last ⌘-drag in the menu bar ended. See
    /// isUserArrangingMenuBar.
    var lastUserMenuBarDragEnd: ContinuousClock.Instant?

    /// Keeps the manager's own subscriptions alive for its lifetime.
    private var observers = Set<AnyCancellable>()

    private var navigationStateObservationTask: Task<Void, Never>?

    /// Answers "is any menu open" with caching and in-flight-probe joining.
    /// The item inventory is supplied lazily so the monitor can be constructed
    /// without a self-capture in a stored-property initializer.
    @ObservationIgnored
    lazy var menuOpenMonitor = MenuOpenMonitor { [weak self] in
        self?.itemCache.managedItems.filter(\.isOnScreen) ?? []
    }

    /// Timer for lightweight periodic cache checks.
    ///
    /// Only ever read or written from @MainActor methods, so no explicit
    /// isolation marker is needed.
    private var cacheTickCancellable: AnyCancellable?

    @ObservationIgnored var isPurgingDepartedOwners = false

    /// Last menu-bar window-list read by the periodic cacheItemsIfNeeded cheap
    /// gate (macOS 27). While this is unchanged tick-to-tick the bar is stable,
    /// so the full identity-signature AX walk is skipped entirely. nil until
    /// the first gated tick.
    var periodicWindowListSignature: [CGWindowID]?

    /// Persisted identifiers of menu bar items we've already seen.
    var knownItemIdentifiers = Set<String>()
    /// Suppresses the next automatic relocation of newly seen leftmost items.
    var suppressNextNewLeftmostItemRelocation = false

    /// Signature of the last macOS 27 divider move that failed. While the layout
    /// is unchanged, enforceControlItemOrder skips re-attempting the identical
    /// (unachievable) move so it doesn't loop every cache cycle, the source of
    /// the idle "cursor pulled to the menu bar / icons shuffling" thrash.
    var lastFailedDividerSignature: String?

    /// A candidate item signature seen to differ from the cache but not yet
    /// confirmed. cacheItemsIfNeeded requires a differing signature to persist,
    /// unchanged, for Constants.MenuBarTuning.signatureStabilityGrace before
    /// recaching, so a transient enumeration blip (a dynamic-title app
    /// momentarily dropping its AX subtree, a marker/clone window flickering
    /// during a reflow) does not trigger a full recache + assertion re-apply.
    /// Genuine changes hold past the grace window and confirm; a flap reverts to
    /// the cached signature and clears the gate. See signatureRecacheDecision.
    var pendingItemSignatureCandidate: [String]?

    /// When pendingItemSignatureCandidate was first observed. The candidate
    /// only confirms once it has held continuously since this instant for the
    /// stability grace; a changed difference resets both fields.
    var pendingItemSignatureFirstSeen: ContinuousClock.Instant?

    isolated deinit {
        cacheTickCancellable?.cancel()
        menuOpenMonitor.cancel()
        coalescedCacheRerunTask?.cancel()
    }

    /// Resumed when a background cache pass finishes, for callers that need to
    /// wait one out rather than race it.
    var backgroundCacheContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Layout coordination state

    // The flags below gate the cache cycle, the startup settling window, and
    // the last-applied profile spec. They stay separate because each guards a
    // different AX-timing or live Window Server interaction; consolidating
    // them needs manual testing on real hardware.
    //
    // isApplyingProfileLayout gates both the cache cycle and an active
    // profile apply.

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
    var didRunPositionStoreHygiene = false
    /// Handle to the in-flight startup settling Task. Retained so that a
    /// subsequent performSetup() call can cancel the previous settling period
    /// before starting a new one, preventing multiple concurrent settling tasks.
    var startupSettlingTask: Task<Void, Never>?
    /// Handle to the initial cache warm-up task. The first full cache can be
    /// expensive on dense menu bars, so it runs off the startup critical path.
    var initialCacheTask: Task<Void, Never>?
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

    /// How authoritative the current settling period is, so a preflight
    /// cannot tear down a stronger settling already in flight.
    enum SettlingKind {
        /// The cold-boot wait from performSetup. Only another cold start or an
        /// expected-set relaunch can replace it.
        case cold
        /// Suppresses restore while an applyOffset wave runs. The matching
        /// no-op path can cancel it.
        case preflight
        /// Waits for specific relaunched bundle IDs to reattach.
        case expectedSet
    }

    var settlingKind: SettlingKind?
    /// Persisted bundle identifiers explicitly placed in hidden section.
    var pinnedHiddenBundleIDs = Set<String>()
    /// Persisted bundle identifiers explicitly placed in always-hidden section.
    var pinnedAlwaysHiddenBundleIDs = Set<String>()

    /// Cached layout parameters from the last profile apply. A late-arriving
    /// profile item is accepted where it lands and never re-applies the
    /// profile (see LayoutChangeReason); this spec only lets the New
    /// Items placement anchor it against the profile's order. Read access is
    /// internal so tests can verify the re-arm path refreshes it; writes
    /// remain confined to this file (armProfileState and rearmActiveProfileLayout).
    var activeProfileLayout: (
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    )?

    /// True while applyProfileLayout is executing. Gates the cache cycle so
    /// an in-flight apply is not fought by a concurrent restore.
    var isApplyingProfileLayout = false

    /// Debounce for macOS 27 overflow rebalance (assignment backends skip legacy Phase 4).
    var lastOverflowRebalance: Date?

    /// Width the overflow budget gives up because a notch covered one of
    /// Thaw's own control items, and the visible items it was measured
    /// against. Sticky until that set changes: dropping it the moment the icon
    /// reappears re-admits the item that covered it, which covers it again.
    var heldNotchOcclusionDeficit: (width: CGFloat, visibleUIDs: Set<String>)?
    var heldParkedLaneDeficit: (width: CGFloat, visibleUIDs: Set<String>)?

    /// In-flight overflow rebalance task. Coalesces repeated post-cache rebalance
    /// triggers so the assertion reflow from one rebalance cannot immediately
    /// kick another, preventing the move→reflow→recache→move thrash cycle.
    var overflowRebalanceTask: Task<Void, Never>?

    /// The strongest request coalesced into the pending overflow rebalance.
    ///
    /// scheduleOverflowRebalance replaces its in-flight task on every
    /// call, so an explicit request (profile apply, setting flip) or an
    /// immediate one (native-overflow probe transition) followed by a
    /// cache-driven request would lose its intent. Merging every request here,
    /// and clearing it only once a rebalance runs with it, preserves that
    /// intent. See OverflowRebalanceRequest.
    var overflowRebalancePendingRequest: OverflowRebalanceRequest?

    /// Prevents a failed physical layout apply from being committed by a later
    /// cache pass. A new apply or an explicit user Command-drag clears it.
    var suppressSpatialOrderPersistenceAfterFailedApply = false

    /// Whether the user has taken menu bar arrangement into their own hands (MenuBarArrangementMode.manual).
    /// Every automatic path reads this; the explicit Layout edit path reads arrangementForbidsMoves instead.
    var arrangementIsManual: Bool {
        appState?.settings.advanced.menuBarArrangementMode == .manual
    }

    /// Whether Manual refuses a move asked for by the current task: all but an explicit Layout edit.
    /// Only the guards a Layout drop, keyboard move, or sort passes through read this.
    var arrangementForbidsMoves: Bool {
        ExplicitLayoutEdit.manualArrangementForbidsMoves(
            arrangementIsManual: arrangementIsManual,
            isExplicitLayoutEdit: ExplicitLayoutEdit.isActive
        )
    }

    /// Cached domain-access probe. The probe is a cheap open(), but it sits
    /// on the hottest move paths, so it is sampled at most once per TTL. The
    /// value only changes when the user flips access in System Settings.
    ///
    /// Ignored by Observation deliberately: this is memoization, not state a
    /// view should track. Observed, a body that reads
    /// menuBarAgentIgnoresPreferredPositions would write this property
    /// during view update and invalidate itself once per TTL, forever.
    @ObservationIgnored
    var positionsDomainAccessCache: (value: Bool, at: ContinuousClock.Instant)?
    static let positionsDomainAccessTTL: Duration = .seconds(2)

    static let preferredPositionsIgnoredKey = "MenuBarItemManager.menuBarAgentIgnoresPreferredPositions"
    static let preferredPositionsIgnoredBuildKey = "MenuBarItemManager.menuBarAgentIgnoresPreferredPositionsOSBuild"

    /// Verified-write failures counted toward the store-inert verdict this
    /// session. In-memory only: a restart must re-earn the evidence rather
    /// than inherit a stale count.
    var preferredPositionsIgnoredEvidence = 0

    /// Items whose own writes the agent keeps ignoring. Session-scoped; never
    /// persisted.
    var ignoredPreferredWrites = IgnoredPreferredWrites()

    /// Debounced physical application of a layout-pane visible-order edit.
    private var authoredVisibleOrderApplyTask: Task<Void, Never>?

    /// Whether a layout-pane visible-order edit is awaiting physical
    /// application. While set, reveal reconciliation enforces the authored
    /// controller order; otherwise it enforces the live mirror. A ⌘-drag on
    /// the real bar needs no reconciliation (the agent adopts it), but a pane
    /// edit exists only on paper until a physical pass runs, and meanwhile a
    /// cache tick re-mirrors the unchanged bar and contradicts it. Cleared
    /// after a reveal ordering pass runs with the authored order.
    var authoredVisibleOrderPendingPhysicalApply = false

    /// The Visible items that were live when the order was last mirrored, so
    /// the next mirror can tell an arrival from a ⌘-drag.
    var lastMirroredLiveVisibleIdentifiers: Set<String>?

    /// How many ordering passes an authored pane edit gets before Thaw reports
    /// that the pane and the bar disagree. More than one because a pass can be
    /// interrupted, a reveal, an assertion reflow, and fewer than the move
    /// path's own retry budget because each pass is already several seconds.
    static let authoredVisibleOrderApplyAttempts = 3

    /// Visible members MenuBarAgent did not republish in time, stamped when
    /// each was last missing.
    ///
    /// The ordering pass waits up to three seconds for every authored member
    /// to be live. Without this, each following pass burns the same deadline
    /// on the same absentee. Entries
    /// expire so a member that returns is waited for again.
    var visibleMembersMissingRepublish = [String: ContinuousClock.Instant]()

    /// How long a failed republish is remembered.
    static let missingRepublishMemory: Duration = .seconds(10)

    /// Drops the memo so the next ordering pass waits for every member again.
    /// The memo suppresses waits for automatic passes; a user-initiated change
    /// inheriting one drops members the pass never waited for.
    func forgetMissingRepublishMemory() {
        guard !visibleMembersMissingRepublish.isEmpty else { return }
        MenuBarItemManager.diagLog.debug(
            "authored visible apply: clearing \(self.visibleMembersMissingRepublish.count) " +
                "missing-republish memo entr(ies) for a user-initiated layout change"
        )
        visibleMembersMissingRepublish.removeAll()
    }

    // MARK: Convergence budget

    /// How long one authored pane edit may keep spending automatic ordering
    /// passes. Each pass on the macOS 27 drag channel is a visible drag on
    /// the real bar, and every cache cycle can re-plan a boundary move whose
    /// verification flaps against neighbours that have not moved yet, so one
    /// edit could otherwise cascade drags for minutes.
    static let convergenceBudget: Duration = .seconds(90)

    /// After the budget runs out, automatic passes pause for this long
    /// instead of resuming immediately (whose first re-plan is the same
    /// boundary move the budget just gave up on). A new authored edit, a
    /// reveal, or a restriction repair resets everything.
    static let convergencePostExpirySuppression: Duration = .seconds(600)

    /// When the current authored edit's convergence budget expires.
    var convergenceBudgetDeadline: ContinuousClock.Instant?

    /// How long automatic passes stay suppressed after a budget expiry.
    var convergenceSuppressedUntil: ContinuousClock.Instant?

    /// Debounced structural re-write after bar-changing activity settles.
    /// See MenuBarItemManager.scheduleStructuralNormalization(after:).
    var structuralNormalizationTask: Task<Void, Never>?

    /// Persisted per-section item order. Maps section key to an ordered list of
    /// uniqueIdentifier strings (right-to-left, matching cache array order).
    var savedSectionOrder = [String: [String]]()

    /// One-shot guard: the saved-order ghost prune runs once, on the first
    /// completed cache pass, when a live walk exists to compare against.
    var didPruneSavedSectionOrderGhosts = false

    /// Placement preference for newly detected menu bar items.
    var newItemsPlacement = NewItemsPlacement.defaultValue

    /// Drops the pending-relocation ledger persisted by older builds.
    ///
    /// The ledger belonged to the temporary-show reveal path, which is gone:
    /// the entries only made the setup pass try to move items to destinations
    /// that no longer mean anything. Reading and clearing the keys once removes
    /// them from the user's defaults.
    private func purgeLegacyPendingRelocations() {
        let defaults = UserDefaults.standard
        let relocationKey = "MenuBarItemManager.pendingRelocations"
        let destinationKey = "MenuBarItemManager.pendingReturnDestinations"
        let relocationCount = (defaults.dictionary(forKey: relocationKey) as? [String: String])?.count ?? 0
        let destinationCount = (defaults.dictionary(forKey: destinationKey) as? [String: [String: String]])?.count ?? 0
        defaults.removeObject(forKey: relocationKey)
        defaults.removeObject(forKey: destinationKey)
        if relocationCount > 0 || destinationCount > 0 {
            MenuBarItemManager.diagLog.info(
                """
                Dropped \(relocationCount) pending relocation(s) and \
                \(destinationCount) return destination(s) left by an older build
                """
            )
        }
    }

    /// Visible items that proved physically unrepairable after an assertion
    /// reflow. Keeping them eligible makes every later restriction change pulse
    /// the whole menu bar even though the synthetic move cannot succeed. Pairing
    /// stable identity with the owning process keeps assertion-driven synthetic
    /// ID churn from re-arming the loop, while naturally retrying after the app
    /// relaunches with a new PID.
    var postRestrictionUnrepairableItemIDs = Set<PostRestrictionRepairItemID>()

    /// How many passes in a row an item was attempted as a visible-boundary
    /// strand and still failed its boundary check afterwards.
    ///
    /// A single failure is ordinary: a weight write needs a beat before
    /// MenuBarAgent re-seats the item, and a display reflow can strand an item
    /// once legitimately. An item that fails this many passes running is one
    /// the ladder cannot place at all, and retrying it forever is what keeps
    /// the repair pass, and the item cache and capture pipeline behind it,
    /// awake on an otherwise idle machine.
    var boundaryRepairStrandTrips: [PostRestrictionRepairItemID: Int] = [:]

    /// Items whose visible-boundary repair has been given up on for this
    /// session. Cleared when the item's owner quits (the prune below), when the
    /// display topology changes, when the cooldown below expires, or on
    /// relaunch.
    var suppressedBoundaryRepairItemIDs = Set<PostRestrictionRepairItemID>()

    /// When each suppression was issued, so a strand caught in a transient
    /// fight (a respace writing against the repair during a restart's login
    /// window) gets a fresh ladder after the cooldown instead
    /// of staying buried until the user drags it by hand.
    var suppressedBoundaryRepairAt: [PostRestrictionRepairItemID: Date] = [:]

    /// Items whose persisted stranded verdict has already seeded this
    /// session's suppression. Seeded once, so the cooldown and display-change
    /// re-arms still apply afterwards.
    var seededStrandedRepairItemIDs = Set<PostRestrictionRepairItemID>()

    /// How long a suppression holds before the strand is re-armed. Long
    /// enough that a structural blocker does not turn the repair pass into a
    /// drag storm; short enough that a transient fight self-heals within a
    /// minute of the fight ending.
    var isBoundaryRepairDeclinedForWrappedMenu = false

    /// Items the layout pane just moved into the visible section that still
    /// owe a physical seat. MenuBarAgent re-allows a concealed item at the
    /// slot it remembers, whatever the weight on file says, and while the
    /// section is collapsed the boundary check cannot see the concealed
    /// neighbours the item is standing among, so it reports the item as
    /// placed and the mix only shows on the next reveal. The strand pass
    /// drags these across the divider unconditionally.
    var pendingPhysicalSeatIDs = Set<String>()

    /// Consecutive failed passes before an item stops being repaired. Each
    /// pass carries its own multi-attempt drag budget, so a third pass means
    /// minutes of visible drags. A strand that two full passes cannot cross
    /// has a structural blocker (a group pulling it back, or the store's
    /// weights), and more drags will not change that.
    static let boundaryRepairTripLimit = 2

    /// Suppressions older than this are cleared on the next repair pass.
    static let boundaryRepairSuppressionCooldown: TimeInterval = 60

    /// The display the last repair pass ran against, so a topology change can
    /// re-arm items that were only stranded by the old arrangement.
    var lastBoundaryRepairDisplayID: CGDirectDisplayID?

    /// Set when Thaw's own press is expected to flip the active display.
    ///
    /// Pressing an item that lives on another display activates that display,
    /// so the display change that follows is ours, not the user switching
    /// displays. Consumed once by the repair above.
    var selfInflictedDisplayChangeUntil: ContinuousClock.Instant?

    /// Mirrors a macOS 27 layout-bar drop into the legacy saved-order gate
    /// immediately. The AX window signature changes as the drop/reveal settles;
    /// without this synchronous mirror, applySavedLayout can run before the
    /// next cache pass and restore the previous order ~100 ms after a valid drop.
    func mirrorSectionOrderNow(
        _ identifiers: [String],
        for section: MenuBarSection.Name
    ) {
        // On macOS 27 RuntimeSectionController.persistOrder() is the single writer to
        // "MenuBarItemManager.savedSectionOrder" defaults; this method only
        // keeps the in-memory dict in sync so LayoutSolver reads fresh data
        // without waiting for the next cache-cycle mirror.
        layoutPublication.invalidate()
        let key = sectionKey(for: section)
        if identifiers.isEmpty {
            savedSectionOrder.removeValue(forKey: key)
        } else {
            savedSectionOrder[key] = identifiers
        }
        MenuBarItemManager.diagLog.debug(
            "Mirrored macOS 27 layout drop into saved order for \(section.logString): \(identifiers.count) item(s)"
        )

        // This callback records what the controller persisted, not a request
        // to move anything; replaying the section here would move an item
        // again after a neighbour was placed. Supersede an older apply;
        // callers with unfulfilled intent schedule a new one after recording.
        if section == .visible {
            cancelPendingSectionOrderApply()
        }
    }

    /// Supersedes an older whole-section request before accepting a new drop.
    func cancelPendingSectionOrderApply() {
        authoredVisibleOrderApplyTask?.cancel()
        authoredVisibleOrderApplyTask = nil
        authoredVisibleOrderPendingPhysicalApply = false
    }

    /// Enacts a recorded layout that has not already been placed and verified.
    /// Concealed sections wait for reveal; completed single-item drops never
    /// call this. Recording and physical application must remain separate.
    func scheduleSectionOrderApply(for section: MenuBarSection.Name) {
        // Manual arrangement refuses every apply but an explicit Layout edit's;
        // any other pass would only burn the convergence budget and log a failure.
        guard !arrangementForbidsMoves else { return }
        writeConcealedOrderForManualEdit(in: section)
        let identifiers = savedSectionOrder[sectionKey(for: section)] ?? []
        if section == .visible, !identifiers.isEmpty {
            authoredVisibleOrderPendingPhysicalApply = true
            noteAuthoredEditCommitted()
        }
        if section == .visible,
           !identifiers.isEmpty,
           let controller = appState?.menuBarManager.sectionController
        {
            authoredVisibleOrderApplyTask?.cancel()
            authoredVisibleOrderApplyTask = Task { @MainActor [weak self] in
                // Debounce successive drops of one pane drag session.
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                defer {
                    // A cancelled predecessor must not clear its replacement.
                    if !Task.isCancelled {
                        authoredVisibleOrderApplyTask = nil
                    }
                }
                // Converge rather than fire once. A single pass can place some
                // of the order and stall on the rest, an anchor that moved
                // under it, a write MenuBarAgent had not yet consumed, and the
                // pane then shows an arrangement the bar does not have. Re-run
                // until the live order satisfies the authored one, and keep
                // authoredVisibleOrderPendingPhysicalApply armed if it never
                // does, so the cache mirror cannot overwrite the user's intent
                // with the arrangement that failed to change.
                for attempt in 1 ... Self.authoredVisibleOrderApplyAttempts {
                    guard !Task.isCancelled else { return }
                    MenuBarItemManager.diagLog.info(
                        "macOS 27: applying authored visible order physically "
                            + "(\(identifiers.count) item(s), attempt \(attempt))"
                    )
                    await applySectionItemOrder(
                        sections: [.visible],
                        controller: controller,
                        whileRevealing: controller.revealedSection,
                        visibleOrderOverride: identifiers,
                        reason: .userReorder
                    )
                    await cacheItemsRegardless(skipRecentMoveCheck: true)
                    guard !Task.isCancelled else { return }
                    let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                    guard !Task.isCancelled else { return }
                    if liveOrderMatches(
                        identifiers,
                        section: .visible,
                        controller: controller,
                        items: liveItems
                    ) {
                        authoredVisibleOrderPendingPhysicalApply = false
                        MenuBarItemManager.diagLog.info(
                            "macOS 27: authored visible order realized on the bar after \(attempt) attempt(s)"
                        )
                        return
                    }
                    if attempt < Self.authoredVisibleOrderApplyAttempts {
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                // Give up and let the bar win. Holding the edit pending would
                // keep the pane showing an arrangement that does not exist and
                // lock the cache mirror out of the real one indefinitely; a
                // pane that snaps back is at least honest about what happened.
                authoredVisibleOrderPendingPhysicalApply = false
                MenuBarItemManager.diagLog.error(
                    "macOS 27: authored visible order still not on the bar after "
                        + "\(Self.authoredVisibleOrderApplyAttempts) attempt(s); "
                        + "releasing it so the pane reflects the bar"
                )
            }
        }
    }

    /// Writes the recorded Visible order back after an arrival disturbed it.
    /// Position writes only and a single attempt; if the bar does not follow, the next mirror records the bar.
    func scheduleArrivalOrderRestore() {
        guard !arrangementIsManual,
              let controller = appState?.menuBarManager.sectionController
        else { return }
        let identifiers = savedSectionOrder[sectionKey(for: .visible)] ?? []
        guard identifiers.count > 1 else { return }
        authoredVisibleOrderPendingPhysicalApply = true
        authoredVisibleOrderApplyTask?.cancel()
        authoredVisibleOrderApplyTask = Task { @MainActor [weak self] in
            // Let the arrival finish laying out before writing around it.
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            defer {
                // A cancelled predecessor must not clear its replacement.
                if !Task.isCancelled {
                    authoredVisibleOrderApplyTask = nil
                    authoredVisibleOrderPendingPhysicalApply = false
                }
            }
            MenuBarItemManager.diagLog.info(
                "macOS 27: restoring recorded visible order after an arrival (\(identifiers.count) item(s))"
            )
            await applySectionItemOrder(
                sections: [.visible],
                controller: controller,
                visibleOrderOverride: identifiers,
                reason: .arrivalRestore
            )
            guard !Task.isCancelled else { return }
            await cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    /// Authored layout inputs for keeping automatic overflow out of the
    /// persisted order.
    ///
    /// Automatic overflow files an authored-Visible item under Hidden in the
    /// effective cache. Persisting that cache verbatim turns a cramped-display
    /// moment into a permanent hide, so the persistence paths reinsert those
    /// concealed items at their recorded Visible slots using the authored
    /// assignment and order.
    struct AuthoredLayoutProjection: Sendable {
        /// Explicit authored assignments, keyed by canonical identifier.
        /// Absence means Visible, matching the runtime's default.
        var sectionAssignment: [String: MenuBarSectionName]
        /// Recorded authored order per section, including overflowed Visible
        /// slots that the effective cache has temporarily filed elsewhere.
        var sectionOrder: [MenuBarSectionName: [String]]

        nonisolated func authoredSection(for identifier: String) -> MenuBarSectionName {
            sectionAssignment[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] ?? .visible
        }
    }

    /// Authored layout state the persistence projection reads from a section
    /// controller. A plain value so tests run the exact production derivation
    /// without a live runtime.
    struct AuthoredLayoutSource: Sendable {
        var sectionAssignment: [String: MenuBarSectionName]
        var sectionItemOrder: [MenuBarSectionName: [String]]
    }

    /// The authored projection to use for persistence, or nil when there is no
    /// runtime to consult (standalone/test configurations keep prior
    /// semantics). The source override lets tests run this same derivation
    /// without a live controller.
    private func authoredLayoutProjection(for cache: ItemCache) -> AuthoredLayoutProjection? {
        let source: AuthoredLayoutSource
        if let override = authoredLayoutSourceOverride {
            source = override
        } else if let controller = appState?.menuBarManager.sectionController {
            source = AuthoredLayoutSource(
                sectionAssignment: controller.sectionAssignment,
                sectionItemOrder: controller.sectionItemOrder
            )
        } else {
            return nil
        }
        return Self.authoredLayoutProjection(for: cache, source: source)
    }

    /// Pure derivation and gate. The projection is only needed while the
    /// effective cache still conceals an authored-Visible item. That also
    /// covers the window after overflow is cleared but before the next
    /// inventory walk publishes the restored membership, so a profile capture
    /// in that window cannot record the item as Hidden. Once the cache catches
    /// up the projection is a no-op and the gate returns nil.
    static nonisolated func authoredLayoutProjection(
        for cache: ItemCache,
        source: AuthoredLayoutSource
    ) -> AuthoredLayoutProjection? {
        let projection = AuthoredLayoutProjection(
            sectionAssignment: source.sectionAssignment,
            sectionOrder: source.sectionItemOrder
        )
        guard hasConcealedAuthoredVisibleItem(in: cache, projection: projection) else {
            return nil
        }
        return projection
    }

    /// Items eligible for savedSectionOrder: app items with a resolved
    /// sourcePID, plus the visible control item, so reconciliation after a
    /// restart can tell when macOS placed an app item on the wrong side of
    /// it. The hidden and always-hidden dividers stay out; they are always
    /// inserted into desiredFlat at the section boundary.
    static nonisolated func isPersistable(_ item: MenuBarItem) -> Bool {
        if item.tag == .visibleControlItem {
            return true
        }
        return !item.isControlItem && item.sourcePID != nil
    }

    /// Whether any persistable, non-transient item the effective cache filed
    /// outside Visible is authored Visible. That is exactly automatic
    /// overflow, or a cache that has not yet caught up with its clearing.
    static nonisolated func hasConcealedAuthoredVisibleItem(
        in cache: ItemCache,
        projection: AuthoredLayoutProjection
    ) -> Bool {
        for section in MenuBarSectionName.allCases where section != .visible {
            for item in cache[section]
                where isPersistable(item) && !item.isTransientControlCenterItem
            {
                if projection.authoredSection(for: item.uniqueIdentifier) == .visible {
                    return true
                }
            }
        }
        return false
    }

    /// Computes the per-section order dict from cache with the same filter and
    /// closed-app preservation saveSectionOrder uses, without writing it.
    ///
    /// ProfileManager.captureCurrentLayout shares this so a profile's
    /// itemOrder matches savedSectionOrder; a raw cache snapshot drifted from
    /// it and made closed apps look unmanaged on re-apply.
    ///
    /// Control items are left out except the chevron, whose position lets
    /// reconciliation spot an app item on the wrong side of it. Items without
    /// a resolved sourcePID and transient Control Center items are left out
    /// because their identifiers churn. planSectionOrder then merges in closed
    /// apps from the previous order, so a slot survives a quit.
    func computeSectionOrder(from cache: ItemCache) -> [String: [String]] {
        computeSectionOrder(from: cache, projection: authoredLayoutProjection(for: cache))
    }

    /// The projection-aware computation. A nil projection keeps the effective
    /// cache bucket as authority; a non-nil projection reinserts concealed
    /// Visible slots at their recorded positions, so automatic overflow is
    /// never written back as a hide. Membership stays cache-driven in every
    /// other case, so a command-drag the controller has not adopted yet is
    /// untouched.
    func computeSectionOrder(
        from cache: ItemCache,
        projection: AuthoredLayoutProjection?
    ) -> [String: [String]] {
        var newOrder = [String: [String]]()

        var allCurrentIdentifiers = Set<String>()
        var allCurrentBaseIdentifiers = Set<String>()
        // Namespaces (app bundle ids / reserved keywords) of every currently
        // cached item, so planSectionOrder can drop stale title-variant saved
        // entries for apps that are still running (title-churning items like
        // MeetingBar / Granola countdowns would otherwise bloat savedSectionOrder
        // without bound and make the O(n²) merge pin a core, the macOS 27
        // reorder "storm").
        var allCurrentNamespaces = Set<String>()
        // Every persistable, non-transient item by identifier, wherever the
        // effective cache filed it. The authored projection uses this to find
        // an overflowed Visible item that the cache has temporarily rebucketed
        // into Hidden.
        var persistableByIdentifier = [String: MenuBarItem]()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where Self.isPersistable(item) {
                // Always track base identifier so stale saved entries for
                // transient items (Live Activities) get pruned by the
                // isStaleInstanceIndex guard below and not re-injected.
                let baseID = "\(item.tag.namespace):\(item.tag.canonicalTitle)"
                allCurrentBaseIdentifiers.insert(baseID)
                allCurrentNamespaces.insert("\(item.tag.namespace)")
                // Exclude transient Control Center items (Live Activities,
                // iPhone Mirroring icons) from the identifier set so their
                // ephemeral UIDs are never written to savedSectionOrder.
                guard !item.isTransientControlCenterItem else { continue }
                allCurrentIdentifiers.insert(item.uniqueIdentifier)
                persistableByIdentifier[item.uniqueIdentifier] = item
            }
        }

        for section in MenuBarSection.Name.allCases {
            // Current identifiers for this section, in cache iteration
            // order (which approximates left-to-right X order). With an
            // authored projection the membership comes from the user's
            // assignment instead, so automatic overflow is not mistaken for a
            // hide; the effective bucket stays authoritative without one.
            let effective = cache[section]
                .filter {
                    Self.isPersistable($0) &&
                        !$0.isTransientControlCenterItem
                }
            let currentInSection: [String] = if let projection {
                Self.authoredCurrentIdentifiers(
                    for: section,
                    effective: effective,
                    persistableByIdentifier: persistableByIdentifier,
                    savedSectionOrder: savedSectionOrder,
                    projection: projection
                )
            } else {
                effective.map(\.uniqueIdentifier)
            }

            let oldSavedForSection = savedSectionOrder[sectionKey(for: section)] ?? []

            // Delegate to planSectionOrder for the position-preserving
            // merge of current items with closed-app entries. This
            // replaces the old "append closed apps to the end" logic
            // that destroyed user-intended positions on every quit.
            let identifiers = LayoutSolver.planSectionOrder(
                currentInSection: currentInSection,
                oldSavedForSection: oldSavedForSection,
                allCurrentIdentifiers: allCurrentIdentifiers,
                allCurrentBaseIdentifiers: allCurrentBaseIdentifiers,
                allCurrentNamespaces: allCurrentNamespaces
            )

            if !identifiers.isEmpty {
                newOrder[sectionKey(for: section)] = identifiers
            }
        }

        return canonicalizingGroups(in: newOrder, cache: cache)
    }

    /// The identifiers for `section`, in persistence order.
    ///
    /// The effective cache is the membership authority everywhere except the
    /// automatic-overflow case: an authored-Visible item the cache filed under
    /// Hidden is reinserted at its recorded Visible slot. Present items keep
    /// the effective cache order, so a within-section reorder is untouched,
    /// and no other section's membership is rewritten (always-hidden remains
    /// governed by the backend's allowsAlwaysHidden mapping). Pure over inputs.
    static nonisolated func authoredCurrentIdentifiers(
        for section: MenuBarSectionName,
        effective: [MenuBarItem],
        persistableByIdentifier: [String: MenuBarItem],
        savedSectionOrder: [String: [String]],
        projection: AuthoredLayoutProjection
    ) -> [String] {
        // Drop authored-Visible items the effective cache filed outside
        // Visible: those are automatic overflow and are reinserted into
        // Visible below. Authored Hidden/Always Hidden membership is left as
        // the backend bucketed it, so the allowsAlwaysHidden mapping stands.
        let present = effective
            .filter { section == .visible || projection.authoredSection(for: $0.uniqueIdentifier) != .visible }
            .map(\.uniqueIdentifier)
        guard section == .visible else { return present }

        let presentSet = Set(present)
        let concealed = persistableByIdentifier.values
            .filter {
                projection.authoredSection(for: $0.uniqueIdentifier) == .visible
                    && !presentSet.contains($0.uniqueIdentifier)
            }
            .map(\.uniqueIdentifier)
        guard !concealed.isEmpty else { return present }

        let reference = projection.sectionOrder[.visible]
            ?? savedSectionOrder[MenuBarSectionName.visible.rawValue]
            ?? []
        let concealedSet = Set(concealed)
        // Recorded entries first so their relative order survives; identifiers
        // the record has never seen keep a deterministic order.
        let orderedConcealed = reference.filter { concealedSet.contains($0) }
            + concealed.filter { !reference.contains($0) }.sorted()
        return reinsertingConcealed(orderedConcealed, into: present, reference: reference)
    }

    /// Reinserts concealed identifiers into their recorded slots: each goes
    /// after the closest identifier that precedes it in `reference` and
    /// survives in `order`, or at the front when no predecessor survives.
    /// Pure over inputs.
    static nonisolated func reinsertingConcealed(
        _ concealed: [String],
        into order: [String],
        reference: [String]
    ) -> [String] {
        var result = order
        for identifier in concealed {
            let insertAt: Int
            if let referenceIndex = reference.firstIndex(of: identifier) {
                let predecessor = reference[..<referenceIndex].last { result.contains($0) }
                insertAt = predecessor.flatMap { result.firstIndex(of: $0).map { $0 + 1 } } ?? 0
            } else {
                insertAt = result.count
            }
            result.insert(identifier, at: min(insertAt, result.count))
        }
        return result
    }

    /// Applies the same group gathering RuntimeSectionController/commitOrder(reason:options:)
    /// applies, so the two writers of savedSectionOrder agree.
    ///
    /// savedSectionOrder is written from two directions, the controller mirror
    /// and the cache cycle's output. The cycle short-circuits on
    /// mirrored != savedSectionOrder, so if only one side gathered the two
    /// would disagree every pass and each write would schedule an overflow
    /// rebalance that re-enters the cycle, a write storm.
    ///
    /// Every section is gathered, including Visible, whose order drives the
    /// MenuBarAgent weight permutation that holds a group's icons together.
    private func canonicalizingGroups(
        in order: [String: [String]],
        cache: ItemCache
    ) -> [String: [String]] {
        let items = MenuBarSection.Name.allCases.flatMap { cache[$0] }
        let groups = Self.groupPolicySet(for: items, appState: appState)
        guard !groups.isEmpty else { return order }

        var result = order
        for section in MenuBarSection.Name.allCases {
            let key = sectionKey(for: section)
            guard let sectionOrder = result[key] else { continue }
            let gathered = MenuBarItemGroupPolicy.gather(groups: groups, in: sectionOrder)
            guard gathered.report.didChange else { continue }
            result[key] = gathered.order
        }
        return result
    }

    /// Returns a persistable string key for the given section name (its raw
    /// value).
    func sectionKey(for section: MenuBarSection.Name) -> String {
        section.rawValue
    }

    /// Returns the section name for the given persisted key, if valid. The
    /// persisted key is the enum's raw value.
    func sectionName(for key: String) -> MenuBarSection.Name? {
        MenuBarSection.Name(rawValue: key)
    }

    /// Returns the effective section for newly detected menu bar items, falling back
    /// to hidden when the always-hidden section is currently disabled.
    var effectiveNewItemsSection: MenuBarSection.Name {
        let preferredSection = sectionName(for: newItemsPlacement.sectionKey) ?? .hidden
        if preferredSection == .alwaysHidden, configuration.isAlwaysHiddenSectionEnabled != true {
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

        // Anchor missing from this section (notch overflow moved it to hidden):
        // walk the saved profile order to the nearest surviving sibling.
        if let nearestIndex = badgeIndexFromNearestProfileSibling(
            in: section,
            itemIdentifiers: itemIdentifiers
        ) {
            return nearestIndex
        }

        return defaultNewItemsBadgeIndex(in: section, itemCount: itemIdentifiers.count)
    }

    /// Walks the active profile's saved item order outward from the badge's
    /// missing anchor and returns an insertion index against the first
    /// sibling still present in itemIdentifiers. It walks in the direction the
    /// saved relation implies first (left for leftOfAnchor, right for
    /// rightOfAnchor), then the other way. Returns nil when no active profile
    /// is loaded, the profile has no order for this section, or no sibling
    /// survives.
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
        // Walk toward the side the badge was relative to first; the first
        // surviving sibling on that side reproduces the saved position.
        if walkLeftFirst {
            for i in stride(from: anchorPos - 1, through: 0, by: -1) {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx + 1
                }
            }
            for i in (anchorPos + 1) ..< profileOrder.count {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx
                }
            }
        } else {
            for i in (anchorPos + 1) ..< profileOrder.count {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx
                }
            }
            for i in stride(from: anchorPos - 1, through: 0, by: -1) {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx + 1
                }
            }
        }
        return nil
    }

    /// Updates the preferred destination for newly detected menu bar items using the
    /// badge position from the layout editor.
    func updateNewItemsPlacement(
        section: MenuBarSection.Name,
        arrangedViews: [LayoutBarArrangedView]
    ) {
        let resolvedSection: MenuBarSection.Name = if section == .alwaysHidden, configuration.isAlwaysHiddenSectionEnabled != true {
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
    /// When clamping from alwaysHidden to hidden, the original anchor won't
    /// resolve in the hidden section. Instead of the default leftmost slot,
    /// re-anchor .leftOfAnchor to the rightmost hidden item so the badge lands
    /// on the clock-side edge, the spot users reach first when they expand
    /// the section.
    func applyNewItemsPlacement(_ placement: NewItemsPlacement) {
        let preferredSection = sectionName(for: placement.sectionKey) ?? .hidden
        let alwaysHiddenDisabled = configuration.isAlwaysHiddenSectionEnabled != true
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
        let liveSectionItems = items.filter { item in
            guard !item.isControlItem else { return false }
            // macOS 27 classifies every live item as visible at this layer.
            return targetSection == .visible
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
            if configuration.isAlwaysHiddenSectionEnabled == true {
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
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
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

    /// Reduces an anchor identifier to the canonical identity that survives a
    /// title rekey. macOS 27's synthetic window IDs churn, so they are excluded.
    private func stableNewItemsAnchorIdentifier(from identifier: String) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(identifier)
    }

    private func defaultNewItemsBadgeIndex(in section: MenuBarSection.Name, itemCount: Int) -> Int {
        switch section {
        case .visible:
            return 0
        case .hidden:
            if configuration.isAlwaysHiddenSectionEnabled == true {
                return 0
            }
            return itemCount
        case .alwaysHidden:
            return itemCount
        }
    }

    private(set) weak var appState: AppState?

    /// Authored layout state for the persistence projection. The app leaves
    /// this nil and derives it from the live section controller; tests set it
    /// to run the exact production derivation without a runtime.
    @ObservationIgnored var authoredLayoutSourceOverride: AuthoredLayoutSource?

    /// The settings this component reads. MenuBarEngineConfiguration states
    /// why the engine holds this rather than AppState.
    private(set) var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults

    func performSetup(with appState: AppState) async {
        MenuBarItemManager.diagLog.debug("performSetup: starting MenuBarItemManager setup")
        self.appState = appState
        configuration = appState.settings
        loadLearnedVolatileTitleOwners()
        loadKnownItemIdentifiers()
        loadPinnedBundleIDs()
        purgeLegacyPendingRelocations()
        loadSavedSectionOrder()
        loadNewItemsPlacementPreference()
        loadPreferredPositionsVerdict()
        MenuBarItemManager.diagLog.debug("performSetup: loaded \(knownItemIdentifiers.count) known identifiers, \(pinnedHiddenBundleIDs.count) pinned hidden, \(pinnedAlwaysHiddenBundleIDs.count) pinned always-hidden, \(savedSectionOrder.values.map(\.count)) saved order entries")
        // On first launch (no known identifiers), avoid auto-relocating the leftmost item
        // so everything remains in the hidden section until the user interacts.
        suppressNextNewLeftmostItemRelocation = knownItemIdentifiers.isEmpty
        configureObservers(with: appState)
        initialCacheTask?.cancel()
        MenuBarItemManager.diagLog.debug("performSetup: scheduling initial cacheItemsRegardless off the startup critical path")
        self.initialCacheTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let initialDelay = Self.startupInitialScanDelay
            MenuBarItemManager.diagLog.debug(
                "performSetup: waiting \(initialDelay) before initial menu bar scan"
            )
            do {
                try await Task.sleep(for: initialDelay)
            } catch is CancellationError {
                return
            } catch {
                return
            }
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
                    "performSetup: fast initial cache missing control items on attempt \(attempt), retrying after \(Self.startupControlItemRetryDelay)"
                )
                do {
                    try await Task.sleep(for: Self.startupControlItemRetryDelay)
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

    /// Subscribes the manager to everything that can invalidate the cache:
    /// group edits, app launches and terminations, space and display changes,
    /// and a slow periodic tick for the changes that announce themselves
    /// through none of those.
    private func configureObservers(with appState: AppState) {
        var registered = Set<AnyCancellable>()

        // Creating, editing or dissolving a group only rewrites
        // sectionItemOrder; the icons do not follow until those identifiers
        // become adjacent MenuBarAgent weights, so a group change must trigger
        // a physical re-order.
        //
        // Debounced because a multi-step edit (materialize, then rename) lands
        // as several mutations, and each re-order costs a plist write plus an
        // agent re-sort. MenuBarItemGroupManager is @Observable; an
        // Observations task dedupes and skips the initial element, then feeds
        // a subject so the Combine debounce keeps its semantics.
        let groupSetChangeSubject = PassthroughSubject<Void, Never>()
        let groupOrderTask = Task { @MainActor [weak self, itemGroupManager = appState.itemGroupManager] in
            let changes = Observations { itemGroupManager.groupSet }
            var previous: MenuBarItemGroupSet?
            var isFirst = true
            for await groupSet in changes {
                guard self != nil else { return }
                defer { isFirst = false }
                guard !isFirst, groupSet != previous else {
                    previous = groupSet
                    continue
                }
                previous = groupSet
                groupSetChangeSubject.send(())
            }
        }
        AnyCancellable { groupOrderTask.cancel() }
            .store(in: &registered)
        groupSetChangeSubject
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    await self?.applyGroupOrderToLiveSections()
                }
            }
            .store(in: &registered)

        // When any app launches, refresh the cache to detect new menu bar items
        // (e.g., apps with "unremembered" icons that need restoration) and restore
        // any items that moved to incorrect sections after their app restarted.
        let (launchEvents, launchContinuation) = AsyncStream<String?>.makeStream()
        let launchTask = Task { @MainActor [weak self] in
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                launchContinuation.yield(
                    (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                        .bundleIdentifier
                )
            }
            defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            for await launchedBundleID in launchEvents.debounce(for: .seconds(1)) {
                guard let self else { return }
                MenuBarItemManager.diagLog.debug(
                    "App launched\(launchedBundleID.map { " (\($0))" } ?? ""), refreshing cache for potential new items"
                )

                // A launched app we already track an item for just relaunched
                // (an in-app update, say), and its status item is about to
                // re-register and churn the bar. Settle on its bundle ID so the
                // move pass (applyProfileLayout waits on
                // waitForStartupSettlingToEnd) holds off until the item
                // re-pairs; otherwise the bulk apply runs on the transient
                // layout and sweeps hidden items into Visible. Settling ends as
                // soon as the bundle ID reappears with a resolved PID. Apps with
                // no tracked item arm nothing.
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
                    // the item already showed up on the first pass.
                    try? await Task.sleep(for: .seconds(2.5))
                    await self?.cacheItemsIfNeeded()
                    try? await Task.sleep(for: .seconds(2.5))
                    await self?.cacheItemsIfNeeded()
                }
            }
        }
        registered.insert(AnyCancellable { launchTask.cancel() })

        // When any app terminates, refresh the cache (items may have disappeared).
        // Undebounced first: drop the terminated process's memoized icon before
        // anything can answer from it, so relaunching an app re-reads the icon
        // rather than serving the dead process's copy.
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )
        .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
        .sink { [weak self] app in
            OverflowFallbackIcon.forgetIcon(forPID: app.processIdentifier)
            // Immediate purge: the terminated app's items
            // leave the cache the moment the workspace reports the exit, so
            // the layout editor's rows vanish with it instead of waiting
            // for the debounced rebuild. NSWorkspace posts on the main
            // thread, so the manager state is safe to touch here.
            MainActor.assumeIsolated {
                self?.purgeItemsOwnedBy(app)
            }
        }
        .store(in: &registered)

        let (terminateEvents, terminateContinuation) = AsyncStream<Void>.makeStream()
        let terminateTask = Task { @MainActor [weak self] in
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { _ in terminateContinuation.yield(()) }
            defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            for await _ in terminateEvents.debounce(for: .seconds(1)) {
                guard let self else { return }
                MenuBarItemManager.diagLog.debug("App terminated, refreshing cache")
                // Unconditional, like the launch path. cacheItemsIfNeeded is
                // gated on the WindowServer menu bar window list, and an item
                // published only as an AXExtrasMenuBar child owns no window, so
                // its app can quit without moving that list and its row would
                // outlive the owner.
                await self.cacheItemsRegardless()
            }
        }
        registered.insert(AnyCancellable { terminateTask.cancel() })

        let (activateEvents, activateContinuation) = AsyncStream<Void>.makeStream()
        let activateTask = Task { @MainActor [weak self] in
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { _ in activateContinuation.yield(()) }
            defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            for await _ in activateEvents.debounce(for: .seconds(0.5)) {
                guard let self else { return }
                await self.cacheItemsIfNeeded()
            }
        }
        registered.insert(AnyCancellable { activateTask.cancel() })

        // Gap-fill the layout pane's images whenever it comes on screen:
        // either the selection changes to it, or Settings reopens with it
        // already selected. AppNavigationState is @Observable, so both
        // flips arrive through one Observations sequence. Gap-fill only,
        // a forced full recapture can replace settled glyphs with native
        // overflow chevron crops.
        navigationStateObservationTask?.cancel()
        navigationStateObservationTask = Task { @MainActor [weak self, navigationState = appState.navigationState] in
            let changes = Observations {
                (navigationState.settingsNavigationIdentifier, navigationState.isSettingsPresented)
            }
            for await (identifier, isPresented) in changes {
                guard let self else { return }
                guard identifier == .menuBarLayout, isPresented else {
                    continue
                }
                guard let imageCache = self.appState?.imageCache else { continue }
                await imageCache.prewarmConcealedImages(
                    sections: MenuBarSection.Name.allCases,
                    onlyMissingImages: true
                )
                await imageCache.recaptureIfWarranted(sections: MenuBarSection.Name.allCases)
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
        cacheTickCancellable = Timer.publish(every: 3, tolerance: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    guard let self else { return }
                    // Liveness first: an exit whose terminate notification never
                    // arrived (macOS 27 does not reliably post it) must still
                    // leave the cache, and the window-list gate below never
                    // sees an AX-only status item withdraw.
                    await self.purgeDepartedOwners()
                    await self.cacheItemsIfNeeded()
                }
            }

        // Control Center posts com.apple.controlcenter.bentoBoxDidChange
        // when the user drags a control in or out of the bento box. The control
        // is hosted by com.apple.controlcenter, whose AXExtrasMenuBar is
        // not readable externally, so Thaw cannot manage it. But the bar
        // reflows, and reacting to the notification keeps the enumerated set in
        // sync within ~1 s instead of the 3 s cache tick. Glow observes the
        // same notification for the same reason.
        let bentoChangeObserver = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            bentoChangeObserver,
            { _, observer, _, _, _ in
                guard let observer else { return }
                // passUnretained above, so takeUnretainedValue() here;
                // a retained transfer would over-release on teardown.
                let manager = Unmanaged<MenuBarItemManager>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    MenuBarItemManager.diagLog.debug(
                        "Control Center bento box changed (com.apple.controlcenter.bentoBoxDidChange); refreshing cache"
                    )
                    // A bento move reflows the bar; give the window server a
                    // beat to settle before the walk, mirroring the launch
                    // path's delay. cacheItemsRegardless is unconditional
                    // because an AX-only item may move no window-list gate.
                    try? await Task.sleep(for: .milliseconds(500))
                    await manager.cacheItemsRegardless()
                    // Late re-check for controls that register their menu
                    // extra after the notification fired, the same shape as
                    // the launch path's +2.5s recheck.
                    try? await Task.sleep(for: .seconds(2.5))
                    await manager.cacheItemsIfNeeded()
                }
            },
            "com.apple.controlcenter.bentoBoxDidChange" as CFString,
            nil,
            .deliverImmediately
        )
        registered.insert(AnyCancellable {
            CFNotificationCenterRemoveEveryObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                bentoChangeObserver
            )
        })

        observers = registered
    }

    /// Whether the bar was disturbed by a move within the last duration, and
    /// is therefore too fresh to snapshot.
    ///
    /// Kept as a manager method for internal call sites; external consumers
    /// hold moveActivity directly.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        moveActivity.occurred(within: duration)
    }

    /// Re-attempts applySavedLayout once delay has passed.
    ///
    /// delay is the full blocking window rather than its remaining time: the
    /// window started before now, so waiting it out from here is never early,
    /// only slightly late, and that is the safe direction.
    func scheduleDeferredLayoutReconcile(after delay: Duration, reason: String) {
        guard deferredLayoutReconcileCount < Self.deferredLayoutReconcileLimit else {
            return
        }
        let due = ContinuousClock.now + delay
        if let pending = deferredLayoutReconcileDue,
           deferredLayoutReconcileTask != nil,
           pending <= due
        {
            return
        }
        deferredLayoutReconcileTask?.cancel()
        deferredLayoutReconcileDue = due
        deferredLayoutReconcileCount += 1
        MenuBarItemManager.diagLog.debug(
            "applySavedLayout: deferring reconcile \(delay) (\(reason))"
        )
        deferredLayoutReconcileTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(until: due, clock: .continuous)
            } catch {
                return
            }
            guard let self else { return }
            deferredLayoutReconcileTask = nil
            deferredLayoutReconcileDue = nil
            await cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    /// Clears the deferral bookkeeping once the reconciler gets to run, so the
    /// next blocked pass starts from a full retry budget.
    func noteLayoutReconcileRan() {
        deferredLayoutReconcileCount = 0
        deferredLayoutReconcileTask?.cancel()
        deferredLayoutReconcileTask = nil
        deferredLayoutReconcileDue = nil
    }

    /// Notes that something moved an item without going through Thaw's own
    /// move(), in practice the user ⌘-dragging an icon. Their placement is
    /// authoritative, so this stamps the settle clock, clears the suppression
    /// left by a failed apply, and schedules the structural write that pins
    /// the arrangement into the preferred-position store. The host keeps user
    /// drags in its own layout memory but never persists them as weights, so
    /// without this the arrangement reverts on the next assertion reflow.
    func recordExternalMoveOperation() {
        moveActivity.noteMoveOperation()
        suppressSpatialOrderPersistenceAfterFailedApply = false
        // The user just placed an icon by hand. That outranks a pane edit Thaw
        // has not managed to enact, and it must, or an edit stuck pending would
        // keep the cache mirror from ever learning their arrangement.
        if authoredVisibleOrderPendingPhysicalApply {
            authoredVisibleOrderApplyTask?.cancel()
            authoredVisibleOrderApplyTask = nil
            authoredVisibleOrderPendingPhysicalApply = false
            MenuBarItemManager.diagLog.info(
                "User ⌘-drag supersedes the pending authored visible order"
            )
        }
        scheduleStructuralNormalization()
    }
}
