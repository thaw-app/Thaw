//
//  MenuBarItemManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import Combine

// @preconcurrency retained: CoreGraphics event types (CGEventSource/CGEvent) are
// still not Sendable-annotated in the macOS 26/27 SDK, yet are used off the main
// actor under OSAllocatedUnfairLock for menu-bar event posting. Removing the shim
// would force @unchecked Sendable wrappers. Drop this once Apple annotates them.
@preconcurrency import CoreGraphics
import MenuBarModel
import os.lock
import PlatformRuntimeKit

/// Manager for menu bar items.
@MainActor
final class MenuBarItemManager: ObservableObject {
    static let layoutWatchdogTimeout: DispatchTimeInterval = .seconds(6)

    /// Delay between relocation/restore moves and the subsequent recache,
    /// giving macOS time to settle menu bar item positions.
    static let uiSettleDelay: Duration = .milliseconds(300)

    /// Minimum time cold-boot settling waits before declaring the bar stable.
    private static var startupMinimumSettlingDuration: Duration {
        if MenuBarBackendProvider.current.preferredMovePath == .preferredPositionsThenCommandDrag {
            Constants.MenuBarTuning.startupMenuBarHostSettleDelay
        } else {
            Constants.MenuBarTuning.startupInitialScanDelay
        }
    }

    /// Delay before the first AX scan after launch.
    private static var startupInitialScanDelay: Duration {
        startupMinimumSettlingDuration
    }

    /// Retry interval when Thaw's control items are not yet visible.
    private static var startupControlItemRetryDelay: Duration {
        if MenuBarBackendProvider.current.preferredMovePath == .preferredPositionsThenCommandDrag {
            Constants.MenuBarTuning.startupMenuBarHostSettleDelay
        } else {
            Constants.MenuBarTuning.startupInitialScanDelay
        }
    }

    /// The current cache of menu bar items.
    @Published private(set) var itemCache = ItemCache(displayID: nil)

    /// On-screen items from the most recent cache refresh AX walk.
    @MainActor var lastOnScreenMenuBarItems: ([MenuBarItem], ContinuousClock.Instant?) = ([], nil)

    /// A Boolean value that indicates whether the control items for the
    /// hidden sections are missing from the menu bar.
    @Published private(set) var areControlItemsMissing = false

    /// Diagnostic logger for the menu bar item manager.
    static nonisolated let diagLog = DiagLog(category: "MenuBarItemManager")

    /// Semaphore to prevent overlapping event operations.
    private let eventSemaphore = SimpleSemaphore(value: 1)

    /// Actor for managing menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Contexts for temporarily shown menu bar items.
    private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    ///
    /// Only ever read or written from `@MainActor` methods and `deinit` —
    /// the class is already `@MainActor`, so no explicit isolation marker is
    /// needed. `deinit` below is `isolated deinit`: `Timer`/`AnyCancellable`
    /// aren't `Sendable`, and a plain (non-isolated) `deinit` can't read a
    /// `@MainActor`-isolated property of non-`Sendable` type.
    private var rehideTimer: Timer?
    private var rehideCancellable: AnyCancellable?

    /// Timestamp of the most recent menu bar item move operation.
    private var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// Timestamp of the most recent assessment-mode restriction reflow.
    /// `applySavedLayout` is suppressed briefly afterward so a transient
    /// post-reflow geometry pass is not mistaken for real layout drift.
    private var lastRestrictionChangeTimestamp: ContinuousClock.Instant?

    /// How long to defer automatic visible-section reorders after a restriction reflow.
    private static let restrictionChangeLayoutSettleWindow: Duration = .seconds(10)

    /// Whether the assessment-mode assertion was rebuilt recently enough that
    /// automatic visible-section reorders should stand down. Internal (not
    /// private) so the image cache's volatility recording can also stand down:
    /// a reflow shifts every item's crop, and pixel-diffing across one marks
    /// unrelated items as changed on the same tick.
    var isWithinRestrictionReflowSettleWindow: Bool {
        guard let lastRestrictionChange = lastRestrictionChangeTimestamp else {
            return false
        }
        return lastRestrictionChange.duration(to: .now) < Self.restrictionChangeLayoutSettleWindow
    }

    private func parkedSetAndBarMidY(in items: [MenuBarItem]) -> (barMidY: CGFloat?, parkedIDs: Set<CGWindowID>) {
        let barMidY = items.first(where: {
            $0.tag.matchesVisibleControlItem && $0.bounds.midY <= MenuBarItemGeometry.maxOnBarMidY
        })?.bounds.midY
            ?? items.first(where: {
                $0.isControlItem && $0.bounds.width > 8 && $0.bounds.midY <= MenuBarItemGeometry.maxOnBarMidY
            })?.bounds.midY

        let parkedIDs = Set(items.compactMap { item -> CGWindowID? in
            guard item.bounds.width > 0, item.bounds.height > 0 else { return item.windowID }
            if item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY {
                return item.windowID
            }
            guard let barMidY else { return nil }
            return abs(item.bounds.midY - barMidY) > MenuBarItemGeometry.maxDistanceFromBarMidY ? item.windowID : nil
        })

        return (barMidY, parkedIDs)
    }

    /// Deferred repair after an assessment-mode reflow. Concealing one bundle
    /// reshuffles the whole bar; visible-assigned neighbours (notably iStat's
    /// multi-item bundle) can land in the overflow/parked band and never recover
    /// because the layout-bar move cooldown blocks `applySavedLayout`.
    private var postRestrictionRepairTask: Task<Void, Never>?

    /// Timestamps of recent macOS 27 section-order move failures, keyed by
    /// `"<item identity>|<destination>"`. An anchored system item (e.g.
    /// Sound, Control Center) can sit between two items that a saved order
    /// wants adjacent, making the move permanently unachievable via the
    /// synthetic Command-drag. Without this backoff, applySavedLayout's
    /// layout-divergence check re-detects the never-resolved divergence
    /// every cache cycle (~2s) and re-dispatches the same doomed move
    /// forever, hijacking the cursor on a tight loop and disrupting the
    /// dragged item's own AX/rendering state.
    private var recentMacOS27MoveFailures = [String: ContinuousClock.Instant]()

    /// How long to suppress retrying a macOS 27 section-order move after it
    /// fails, before giving the achievable-order solver another chance.
    private static let macOS27MoveFailureBackoff: Duration = .seconds(30)

    /// When the ambient `applySavedLayout` pass last *attempted* to restore the
    /// macOS 27 visible control's order, regardless of the planned destination or
    /// outcome. See ``restoreMacOS27VisibleControlOrder`` and
    /// ``visibleControlRestoreCooldown``.
    private var lastVisibleControlRestoreAttempt: ContinuousClock.Instant?

    /// How long to leave the visible control alone after an ambient restore
    /// attempt. The restore runs on every cache tick, and when MenuBarAgent
    /// refuses the placement (the move never verifies) or immediately reverts a
    /// move that did land, the destination-scoped ``macOS27MoveFailureBackoff``
    /// does not suppress the retries — ``RuntimeLayoutCoordinator/visibleControlRestoreMove``
    /// keeps proposing a different on-bar neighbour and the mirrored saved order
    /// keeps shifting, so every pass mints a fresh backoff key. That turns into a
    /// visible tug-of-war: Thaw re-nudges its own icon several times a second
    /// (issue #687). Rate-limiting *attempts* on the control itself caps that at
    /// one nudge per window, so a placement Thaw cannot win settles quietly
    /// instead of churning. A genuinely-needed one-shot restore still runs: once
    /// it sticks, the next pass sees the order satisfied and never re-attempts,
    /// so the cooldown only ever bites during a thrash.
    private static let visibleControlRestoreCooldown: Duration = .seconds(30)

    /// Nominal width used for the macOS 27 overflow budget when an item's AX
    /// bounds have collapsed to an untrusted sliver (see `minimumTrustedGlyphWidth`).
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

    /// Builds the backoff key for a planned macOS 27 section-order move.
    ///
    /// Uses `uniqueIdentifier` rather than `logString` for both items: the
    /// latter embeds the item's transient windowID, which would defeat the
    /// backoff the moment either item's synthetic windowID churns between
    /// cycles even though the logical move being retried hasn't changed.
    private static func macOS27MoveFailureKey(
        item: MenuBarItem,
        destination: MoveDestination,
        desiredOrder: [String]
    ) -> String {
        let side = switch destination {
        case .leftOfItem: "leftOf"
        case .rightOfItem: "rightOf"
        }
        return "\(desiredOrder.joined(separator: ">"))|\(item.uniqueIdentifier)|\(side)|\(destination.targetItem.uniqueIdentifier)"
    }

    /// The single record of which items have been failing, and how.
    let failureLedger = MenuBarItemFailureLedger()

    /// How long a failed item stays excluded from bulk-apply moves.
    ///
    /// Kept as a forwarding shim so callers and tests do not have to reach
    /// through to the ledger for a value that reads as a property of the
    /// manager's retry policy.
    nonisolated static func moveFailureBackoffInterval(failureCount: Int) -> Duration {
        MenuBarItemFailureLedger.backoffInterval(failureCount: failureCount)
    }

    /// How the failure ledger should file an arbitrary error thrown by a
    /// move. Only `EventError` carries enough detail to blame the owner.
    nonisolated static func failureKind(of error: any Error) -> MenuBarItemFailureLedger.FailureKind {
        (error as? EventError)?.failureKind ?? .other
    }

    /// Cached timeouts for move operations.
    private var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// Cached timeouts for click operations (adaptive per app).
    private var clickOperationTimeouts = [MenuBarItemTag: Duration]()
    /// Serialization gate for cache operations.
    private let cacheGate = CacheGate()

    /// Pending self-terminating coalesced cache rerun (see ``scheduleCoalescedCacheRerun()``).
    private var coalescedCacheRerunTask: Task<Void, Never>?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The currently running "is any menu open" probe, reused so concurrent
    /// smart-rehide callers do not all trigger their own full menu-bar scan.
    private var menuOpenCheckTask: Task<Bool, Never>?

    /// The most recent open-menu probe result and its timestamp.
    private var menuOpenCheckCachedResult: Bool?
    private var menuOpenCheckCachedAt: ContinuousClock.Instant?

    /// Timer for lightweight periodic cache checks.
    ///
    /// Only ever read or written from `@MainActor` methods; see the note
    /// above `rehideTimer` for why no explicit isolation marker is needed.
    private var cacheTickCancellable: AnyCancellable?

    /// Last menu-bar window-list read by the periodic `cacheItemsIfNeeded` cheap
    /// gate (macOS 27). While this is unchanged tick-to-tick the bar is stable,
    /// so the full identity-signature AX walk is skipped entirely. `nil` until
    /// the first gated tick.
    private var periodicWindowListSignature: [CGWindowID]?

    /// Persisted identifiers of menu bar items we've already seen.
    var knownItemIdentifiers = Set<String>()
    /// Suppresses the next automatic relocation of newly seen leftmost items.
    private var suppressNextNewLeftmostItemRelocation = false

    /// Signature of the last macOS 27 divider move that failed. While the layout
    /// is unchanged, `enforceControlItemOrder` skips re-attempting the identical
    /// (unachievable) move so it doesn't loop every cache cycle — the source of
    /// the idle "cursor pulled to the menu bar / icons shuffling" thrash.
    private var lastFailedDividerSignature: String?

    /// A candidate item signature seen to differ from the cache but not yet
    /// confirmed. `cacheItemsIfNeeded` requires a differing signature to persist,
    /// unchanged, for ``Constants/MenuBarTuning/signatureStabilityGrace`` before
    /// recaching, so a transient enumeration blip (a dynamic-title app
    /// momentarily dropping its AX subtree, a marker/clone window flickering
    /// during a reflow) does not trigger a full recache + assertion re-apply.
    /// Genuine changes hold past the grace window and confirm; a flap reverts to
    /// the cached signature and clears the gate. See ``signatureRecacheDecision``.
    private var pendingItemSignatureCandidate: [String]?

    /// When ``pendingItemSignatureCandidate`` was first observed. The candidate
    /// only confirms once it has held continuously since this instant for the
    /// stability grace; a changed difference resets both fields.
    private var pendingItemSignatureFirstSeen: ContinuousClock.Instant?

    isolated deinit {
        rehideTimer?.invalidate()
        rehideCancellable?.cancel()
        cacheTickCancellable?.cancel()
        menuOpenCheckTask?.cancel()
        coalescedCacheRerunTask?.cancel()
    }

    /// Continuation to signal when background cache task completes.
    private var backgroundCacheContinuation: CheckedContinuation<Void, Never>?

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
    var pinnedHiddenBundleIDs = Set<String>()
    /// Persisted bundle identifiers explicitly placed in always-hidden section.
    var pinnedAlwaysHiddenBundleIDs = Set<String>()

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

    /// Debounce for macOS 27 overflow rebalance (assignment backends skip legacy Phase 4).
    private var lastMacOS27OverflowRebalance: Date?

    /// In-flight overflow rebalance task. Coalesces repeated post-cache rebalance
    /// triggers so the assertion reflow from one rebalance cannot immediately
    /// kick another, preventing the move→reflow→recache→move thrash cycle.
    private var overflowRebalanceTask: Task<Void, Never>?

    /// Whether a coalesced-away schedule requested `force: true`.
    ///
    /// `scheduleMacOS27OverflowRebalance` cancels and replaces its in-flight
    /// task on every call, so a `force: true` request (e.g. a native-overflow
    /// probe transition) that arrives just before a `force: false` cache-driven
    /// request would otherwise lose its force intent to the replacement task —
    /// and `rebalanceMacOS27OverflowIfNeeded`'s 2-second debounce would then
    /// silently no-op the rebalance the probe was counting on. OR-ing every
    /// request into this flag, and only clearing it once a rebalance actually
    /// runs with it set, preserves that intent across coalescing.
    private(set) var overflowRebalanceForcePending = false

    /// Prevents a failed physical layout apply from being committed by a later
    /// cache pass. A new apply or an explicit user Command-drag clears it.
    private var suppressSpatialOrderPersistenceAfterFailedApply = false

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
    var savedSectionOrder = [String: [String]]()

    /// Placement preference for newly detected menu bar items.
    @Published var newItemsPlacement = NewItemsPlacement.defaultValue

    /// Loads persisted pending relocations for temporarily shown items
    /// whose apps quit before they could be rehidden.
    private func loadPendingRelocations() {
        let key = "MenuBarItemManager.pendingRelocations"
        if let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            pendingRelocations = stored
        }
        let destKey = "MenuBarItemManager.pendingReturnDestinations"
        if let stored = UserDefaults.standard.dictionary(forKey: destKey) as? [String: [String: String]] {
            pendingReturnDestinations = stored
        }
    }

    /// Persists pending relocations.
    private func persistPendingRelocations() {
        let key = "MenuBarItemManager.pendingRelocations"
        UserDefaults.standard.set(pendingRelocations, forKey: key)
        let destKey = "MenuBarItemManager.pendingReturnDestinations"
        UserDefaults.standard.set(pendingReturnDestinations, forKey: destKey)
    }

    private struct PostRestrictionRepairItemID: Hashable {
        let uniqueIdentifier: String
        let ownerPID: pid_t
    }

    /// Visible items that proved physically unrepairable after an assertion
    /// reflow. Keeping them eligible makes every later restriction change pulse
    /// the whole menu bar even though the synthetic move cannot succeed. Pairing
    /// stable identity with the owning process keeps assertion-driven synthetic
    /// ID churn from re-arming the loop, while naturally retrying after the app
    /// relaunches with a new PID.
    private var postRestrictionUnrepairableItemIDs = Set<PostRestrictionRepairItemID>()

    private func postRestrictionRepairItemID(for item: MenuBarItem) -> PostRestrictionRepairItemID {
        PostRestrictionRepairItemID(
            uniqueIdentifier: item.uniqueIdentifier,
            ownerPID: item.ownerPID
        )
    }

    /// Records that the assessment-mode assertion was torn down and rebuilt.
    /// The OS reflows the whole bar; defer saved-layout re-apply until geometry settles.
    func noteRestrictionChange() {
        lastRestrictionChangeTimestamp = .now
        guard #available(macOS 27, *) else { return }
        postRestrictionRepairTask?.cancel()
        postRestrictionRepairTask = Task { @MainActor [weak self] in
            // Let assertion reflow settle before touching geometry. Nudging
            // MenuBarAgent during this window parks collateral items at y≈1413.
            // 1.2s also absorbs rapid multi-hide bursts so repair runs once the
            // user finishes, not between consecutive assertion rebuilds.
            do {
                try await Task.sleep(for: .milliseconds(1200))
            } catch {
                return
            }
            guard let self else { return }
            var stillParked = await self.repairVisibleLayoutAfterRestrictionChange()
            var poll = 0
            while stillParked, poll < 4 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                stillParked = await self.repairVisibleLayoutAfterRestrictionChange()
                poll += 1
            }
        }
    }

    /// Re-composites allowed menu bar items after assertion reflow collateral.
    /// On-band AX ghosts (tooltip works, icon missing) are fixed by pulsing the
    /// assertion; only truly parked items (y≈1400+) get a synthetic unpark.
    @available(macOS 27, *)
    @discardableResult
    private func repairVisibleLayoutAfterRestrictionChange() async -> Bool {
        if appState?.menuBarManager.shouldDeferMacOS27MenuBarMutation == true {
            MenuBarItemManager.diagLog.debug(
                "post-restriction repair: deferred; native menu bar unavailable/transitioning"
            )
            return true
        }

        guard let appState,
              let controller = appState.menuBarManager.sectionController
        else {
            MenuBarItemManager.diagLog.debug(
                "post-restriction repair: skipped, missing app state or section controller"
            )
            return false
        }

        var liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard !Task.isCancelled else { return false }

        // Pre-pulse check: determine whether a recomposite is actually necessary.
        // Hiding-unsupported apps can self-recover after assertion reflows.
        // Pulsing the assertion again can trigger another reflow and re-blank
        // them, so only pulse when supported visible items are parked off-band
        // or still rendering blank.
        let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        let liveItemIDs = Set(liveItems.map(postRestrictionRepairItemID(for:)))
        postRestrictionUnrepairableItemIDs.formIntersection(liveItemIDs)
        let pulseCandidates = liveItems.filter {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                !postRestrictionUnrepairableItemIDs.contains(postRestrictionRepairItemID(for: $0)) &&
                !failureLedger.cannotCompleteMarked($0) &&
                controller.section(for: $0) == .visible
        }
        var liveParkedIDs = parkedSetAndBarMidY(in: liveItems).parkedIDs
        let prePulseParked = pulseCandidates.filter { liveParkedIDs.contains($0.windowID) }
        let prePulseOnBand = pulseCandidates.filter { !liveParkedIDs.contains($0.windowID) }
        let prePulseBlank = await appState.imageCache.itemsRenderingBlank(
            among: prePulseOnBand,
            displayID: displayID
        )
        guard !Task.isCancelled else { return false }
        let needsPulse = !prePulseParked.isEmpty || !prePulseBlank.isEmpty

        if needsPulse, !Task.isCancelled, controller.pulseRestrictionAfterReflow(liveItems: liveItems) {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: pulsed assertion for MenuBarAgent re-composite " +
                    "(prePulseParked=\(prePulseParked.count), prePulseBlank=\(prePulseBlank.count))"
            )
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return false
            }
            liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard !Task.isCancelled else { return false }
            liveParkedIDs = parkedSetAndBarMidY(in: liveItems).parkedIDs
        } else if !needsPulse {
            MenuBarItemManager.diagLog.debug(
                "post-restriction repair: pulse skipped — no non-hiding-unsupported items parked or blank"
            )
        }

        // Denylisted hiding-unsupported items are excluded from synthetic drag
        // and retry signals. Their glyphs may transiently blank on assertion
        // reflows, but repeatedly pulsing can make that worse.
        var failedUnparkIDs = Set<CGWindowID>()
        let parkedVisible = liveItems.filter {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                !postRestrictionUnrepairableItemIDs.contains(postRestrictionRepairItemID(for: $0)) &&
                !failureLedger.cannotCompleteMarked($0) &&
                controller.section(for: $0) == .visible &&
                liveParkedIDs.contains($0.windowID)
        }
        if !parkedVisible.isEmpty, let anchor = unparkAnchorAmong(liveItems: liveItems, controller: controller) {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: unparking \(parkedVisible.count) off-band item(s) " +
                    "using anchor \(anchor.logString)"
            )
            for item in MenuBarItem.sortByVisualCenter(parkedVisible) {
                guard !Task.isCancelled else { return false }
                let freshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                guard !Task.isCancelled else { return false }
                guard let currentAnchor = unparkAnchorAmong(liveItems: freshItems, controller: controller) else {
                    break
                }
                do {
                    try await unparkVisibleItemAfterRestrictionReflow(item: item, anchor: currentAnchor)
                } catch EventError.itemNotMovable {
                    guard !Task.isCancelled else { return false }
                    failedUnparkIDs.insert(item.windowID)
                    postRestrictionUnrepairableItemIDs.insert(postRestrictionRepairItemID(for: item))
                    // Persist the "won't move" verdict so it survives relaunch
                    // (the in-memory set above is keyed by a per-session PID).
                    failureLedger.recordFailure(for: item, kind: .cannotComplete)
                    MenuBarItemManager.diagLog.warning(
                        "post-restriction repair: suppressing future repair pulses for unmovable \(item.logString)"
                    )
                } catch EventError.cannotComplete {
                    guard !Task.isCancelled else { return false }
                    failedUnparkIDs.insert(item.windowID)
                    postRestrictionUnrepairableItemIDs.insert(postRestrictionRepairItemID(for: item))
                    failureLedger.recordFailure(for: item, kind: .cannotComplete)
                    MenuBarItemManager.diagLog.warning(
                        "post-restriction repair: suppressing future repair pulses after move could not complete for \(item.logString)"
                    )
                } catch is CancellationError {
                    return false
                } catch {
                    guard !Task.isCancelled else { return false }
                    failedUnparkIDs.insert(item.windowID)
                    postRestrictionUnrepairableItemIDs.insert(postRestrictionRepairItemID(for: item))
                    // A one-off error is only session backoff, not a persisted
                    // verdict — it may not mean the item is unmovable.
                    failureLedger.recordFailure(for: item, kind: .other)
                    MenuBarItemManager.diagLog.warning(
                        "post-restriction repair: suppressing future repair pulses after move failed for \(item.logString): \(error)"
                    )
                }
            }
        } else if parkedVisible.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "post-restriction repair: no off-band parked items to pulse"
            )
        }

        await cacheItemsRegardless(skipRecentMoveCheck: true, skipSavedLayoutApply: true)
        guard !Task.isCancelled else { return false }
        await appState.imageCache.refreshAfterReorder()
        guard !Task.isCancelled else { return false }
        appState.hidEventManager.refreshMenuBarItemBoundsLookup()

        let afterItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard !Task.isCancelled else { return false }
        let (_, afterParkedIDs) = parkedSetAndBarMidY(in: afterItems)
        // Exclude denylisted hiding-unsupported items from stillParked and
        // blank-glyph checks: counting transient assertion-reflow side effects
        // as broken drives repeated pulses that can compound the problem.
        let onBandVisibleItems = afterItems.filter {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                controller.section(for: $0) == .visible &&
                !afterParkedIDs.contains($0.windowID)
        }

        // If the pre-pulse check found nothing requiring a recomposite, the
        // post-pulse check would also find nothing — items haven't changed.
        // Skip the second screenshot to avoid the extra capture cost.
        guard needsPulse else {
            return false
        }

        // Pulse fired: a fresh screenshot confirms whether the recomposite
        // actually resolved the blanks. If not, returning true re-enters the
        // retry loop so the next iteration can pulse again.
        let blankTags = await appState.imageCache.itemsRenderingBlank(
            among: onBandVisibleItems,
            displayID: displayID
        )
        if !blankTags.isEmpty {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: \(blankTags.count) on-band item(s) still blank after pulse, will retry"
            )
        }

        let stillParked = afterItems.contains {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                !postRestrictionUnrepairableItemIDs.contains(postRestrictionRepairItemID(for: $0)) &&
                !failureLedger.cannotCompleteMarked($0) &&
                !failedUnparkIDs.contains($0.windowID) &&
                controller.section(for: $0) == .visible &&
                afterParkedIDs.contains($0.windowID)
        }

        return stillParked || !blankTags.isEmpty
    }

    @available(macOS 27, *)
    private func unparkAnchorAmong(
        liveItems: [MenuBarItem],
        controller: MenuBarSectionController
    ) -> MenuBarItem? {
        if let control = liveItems.first(where: {
            $0.tag.matchesVisibleControlItem && !$0.isParkedOffMenuBarBand(among: liveItems)
        }) {
            return control
        }
        return liveItems
            .filter {
                !$0.isControlItem &&
                    controller.section(for: $0) == .visible &&
                    !$0.isParkedOffMenuBarBand(among: liveItems)
            }
            .max(by: { $0.bounds.midX < $1.bounds.midX })
    }

    @available(macOS 27, *)
    private func unparkVisibleItemAfterRestrictionReflow(
        item: MenuBarItem,
        anchor: MenuBarItem
    ) async throws {
        MenuBarItemManager.diagLog.info(
            "post-restriction repair: recovering \(item.logString) to left of \(anchor.logString)"
        )
        try await move(
            item: item,
            to: .leftOfItem(anchor),
            skipInputPause: true,
            watchdogTimeout: Self.layoutWatchdogTimeout,
            maxMoveAttempts: 4,
            allowParkedOffMenuBarSource: true,
            skipPreferredPositionMove: true
        )
    }

    /// Mirrors a macOS 27 layout-bar drop into the legacy saved-order gate
    /// immediately. The AX window signature changes as the drop/reveal settles;
    /// without this synchronous mirror, `applySavedLayout` can run before the
    /// next cache pass and restore the previous order ~100 ms after a valid drop.
    func mirrorMacOS27SectionOrder(
        _ identifiers: [String],
        for section: MenuBarSection.Name
    ) {
        guard !MenuBarBackendProvider.current.supportsLegacySectionHiding else { return }
        // On macOS 27 MenuBarSectionController.persistOrder() is the single writer to
        // "MenuBarItemManager.savedSectionOrder" defaults; this method only
        // keeps the in-memory dict in sync so LayoutSolver reads fresh data
        // without waiting for the next cache-cycle mirror.
        let key = sectionKey(for: section)
        if identifiers.isEmpty {
            savedSectionOrder.removeValue(forKey: key)
        } else {
            savedSectionOrder[key] = identifiers
        }
        MenuBarItemManager.diagLog.debug(
            "Mirrored macOS 27 layout drop into saved order for \(section.logString): \(identifiers.count) item(s)"
        )
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

        var allCurrentIdentifiers = Set<String>()
        var allCurrentBaseIdentifiers = Set<String>()
        // Namespaces (app bundle ids / reserved keywords) of every currently
        // cached item, so planSectionOrder can drop stale title-variant saved
        // entries for apps that are still running (title-churning items like
        // MeetingBar / Granola countdowns would otherwise bloat savedSectionOrder
        // without bound and make the O(n²) merge pin a core — the macOS 27
        // reorder "storm").
        var allCurrentNamespaces = Set<String>()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where isPersistable(item) {
                guard !pendingRehideTagIDs.contains(item.tag.tagIdentifier) else { continue }
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
            }
        }

        for section in MenuBarSection.Name.allCases {
            // Current identifiers for this section, in cache iteration
            // order (which approximates left-to-right X order).
            let currentInSection = cache[section]
                .filter {
                    isPersistable($0) &&
                        !$0.isTransientControlCenterItem &&
                        !pendingRehideTagIDs.contains($0.tag.tagIdentifier)
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
                allCurrentBaseIdentifiers: allCurrentBaseIdentifiers,
                allCurrentNamespaces: allCurrentNamespaces
            )

            if !identifiers.isEmpty {
                newOrder[sectionKey(for: section)] = identifiers
            }
        }

        return canonicalizingGroups(in: newOrder, cache: cache)
    }

    /// Applies the same group gathering ``MenuBarSectionController/commitOrder(reason:options:)``
    /// applies, so the two writers of `savedSectionOrder` agree.
    ///
    /// This is not cosmetic. `savedSectionOrder` is written from two directions:
    /// `mirrorMacOS27SectionOrder` pushes the controller's already-gathered
    /// order in, and the cache cycle pushes this function's output in. The cycle
    /// short-circuits on `mirrored != savedSectionOrder`, so if only one side
    /// gathered, the two would disagree on every pass, the guard would never
    /// fire, and each write would schedule an overflow rebalance that re-enters
    /// the cycle — the same write-storm shape as commit `2e38d6c6`.
    ///
    /// Every section is gathered, including `.visible` — the two sides must
    /// cover exactly the same sections or they diverge again. Visible matters
    /// most of all here: its order is what drives the MenuBarAgent weight
    /// permutation that physically holds a group's icons together.
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

    /// Extracts the current per-section item order from the given cache
    /// and persists it to savedSectionOrder. Skips the write when the
    /// order has not changed. Delegates the dict construction to
    /// computeSectionOrder so the "what does the curated section order
    /// look like?" question has a single answer used by both periodic
    /// save and profile capture.
    private func saveSectionOrder(from cache: ItemCache) {
        let newOrder = computeSectionOrder(from: cache)
        guard newOrder != savedSectionOrder else { return }
        savedSectionOrder = newOrder
        persistSavedSectionOrder()
        MenuBarItemManager.diagLog.debug("Saved section order: \(newOrder.mapValues(\.count))")
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
        if preferredSection == .alwaysHidden, appState?.settings.advanced.isAlwaysHiddenSectionEnabled != true {
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
        let resolvedSection: MenuBarSection.Name = if section == .alwaysHidden, appState?.settings.advanced.isAlwaysHiddenSectionEnabled != true {
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
        let alwaysHiddenDisabled = appState?.settings.advanced.isAlwaysHiddenSectionEnabled != true
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
            if appState?.settings.advanced.isAlwaysHiddenSectionEnabled == true {
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
            if appState?.settings.advanced.isAlwaysHiddenSectionEnabled == true {
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
            let settlingStartedAt = ContinuousClock.now
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
                let minimumElapsed = settlingStartedAt.duration(to: .now) >= Self.startupMinimumSettlingDuration
                let hostReady = menuBarHostItemsReady(in: itemCache)

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
                    if stillMissing.isEmpty,
                       pidsOK,
                       minimumElapsed,
                       hostReady
                    {
                        MenuBarItemManager.diagLog.debug(
                            "\(reason): all \(waitingFor.count) expected bundle ID(s) reattached, ending early"
                        )
                        break
                    }
                    MenuBarItemManager.diagLog.debug(
                        "\(reason): \(stillMissing.count) bundle ID(s) still missing: \(stillMissing.sorted().joined(separator: ", "))"
                    )
                } else {
                    if pidsOK,
                       managedCount == lastSeenCount,
                       minimumElapsed,
                       hostReady
                    {
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
                        } else if !minimumElapsed {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): count stable but minimum settle \(Self.startupMinimumSettlingDuration) not elapsed yet"
                            )
                        } else if !hostReady {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): waiting for menu bar host modules (MenuBarAgent / BentoBox)"
                            )
                        }
                        stablePolls = 0
                        lastSeenCount = managedCount
                    }
                }

                // Short sleep before next poll; exit immediately if cancelled.
                do {
                    try await Task.sleep(
                        for: Constants.MenuBarTuning.startupSettlingPollInterval,
                        tolerance: .milliseconds(100)
                    )
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
            await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: false)
            // Final authoritative recache that resolves source PIDs so items used later
            // (which read item.sourcePID ?? item.ownerPID) reflect the true source PID.
            // skipRecentMoveCheck: true ensures this pass is never suppressed by the
            // 1-second recent-move cooldown stamped by the fast restore above.
            await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)

            if reason == "performSetup" {
                scheduleStartupLateItemRecheck()
            }
        }
    }

    /// Re-checks for status items that register after the cold-boot settling
    /// window (already-running apps with late NSStatusItem attachment).
    private func scheduleStartupLateItemRecheck() {
        Task { @MainActor [weak self] in
            // Mirror the post-didLaunch recheck cadence: many apps attach
            // their status item 2–5 s after process start with no launch
            // notification because they were already running.
            try? await Task.sleep(for: .seconds(2.5))
            await self?.cacheItemsIfNeeded()
            try? await Task.sleep(for: .seconds(2.5))
            await self?.cacheItemsIfNeeded()
        }
    }

    /// Whether menu bar host modules (MenuBarAgent / BentoBox on macOS 27,
    /// Control Center on earlier releases) have appeared in the cache.
    private func menuBarHostItemsReady(in cache: ItemCache) -> Bool {
        if MenuBarBackendProvider.current.usesAssertionHiding {
            return cache.managedItems.contains {
                $0.tag.namespace == .menuBarAgent || $0.tag.isBentoBox
            }
        }
        return cache.managedItems.contains { $0.tag.isBentoBox }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        // Creating, editing, or dissolving a group changes the *desired* order
        // but moves nothing on screen. Gathering only rewrites
        // `sectionItemOrder`; the icons do not follow until those identifiers
        // are turned into adjacent MenuBarAgent weights, and the only path that
        // does that for Visible previously ran on explicit profile apply. So a
        // group made from the layout bar stayed visually scattered.
        //
        // Debounced because a multi-step edit (materialize, then rename) lands
        // as several mutations, and each physical re-order costs a plist write
        // plus an agent re-sort.
        appState.itemGroupManager.$groupSet
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    await self?.applyGroupOrderToLiveSections()
                }
            }
            .store(in: &c)

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
            // and the virtual-display provoke (guarded by isSettling) both hold
            // off until the item has re-paired. Without this the bulk apply ran
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
                // the item already showed up on the first pass.
                try? await Task.sleep(for: .seconds(2.5))
                await self?.cacheItemsIfNeeded()
                try? await Task.sleep(for: .seconds(2.5))
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

        appState.navigationState.$settingsNavigationIdentifier
            .sink { [weak self] identifier in
                guard let self, identifier == .menuBarLayout else {
                    return
                }
                Task {
                    guard let imageCache = self.appState?.imageCache else { return }
                    if #available(macOS 27, *) {
                        // Gap-fill only: a forced full recapture can replace
                        // settled glyphs with native overflow chevron crops.
                        await imageCache.prewarmConcealedImagesMacOS27(
                            sections: MenuBarSection.Name.allCases,
                            onlyMissingImages: true
                        )
                    }
                    await imageCache.updateCache(sections: MenuBarSection.Name.allCases)
                }
            }
            .store(in: &c)

        // When Settings reopens with Menu Bar Layout already selected,
        // settingsNavigationIdentifier does not change, so the subscriber
        // above does not fire. Observe isSettingsPresented to catch this case.
        appState.navigationState.$isSettingsPresented
            .removeDuplicates()
            .sink { [weak self] isPresented in
                guard
                    let self,
                    isPresented,
                    appState.navigationState.settingsNavigationIdentifier == .menuBarLayout
                else {
                    return
                }
                Task {
                    guard let imageCache = self.appState?.imageCache else { return }
                    if #available(macOS 27, *) {
                        await imageCache.prewarmConcealedImagesMacOS27(
                            sections: MenuBarSection.Name.allCases,
                            onlyMissingImages: true
                        )
                    }
                    await imageCache.updateCache(sections: MenuBarSection.Name.allCases)
                }
            }
            .store(in: &c)

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

    /// Records that a move operation occurred outside of Thaw's own `move()` function
    /// (e.g. the user cmd+dragged an item directly on the menu bar).
    func recordExternalMoveOperation() {
        lastMoveOperationTimestamp = .now
        suppressSpatialOrderPersistenceAfterFailedApply = false
    }
}

// MARK: - Cache Gate

extension MenuBarItemManager {
    /// Serializes cache operations to prevent races between concurrent
    /// `cacheItemsRegardless` calls. When a relocation move is in flight,
    /// a concurrent call could snapshot item positions before the move
    /// completes, caching them in the wrong section.
    ///
    /// Concurrent calls are dropped; the next trigger (space change,
    /// periodic refresh, app launch notification) will pick up changes.
    private actor CacheGate {
        private var isInProgress = false
        private var rerunRequested = false

        /// Returns `true` if the caller may run a cache pass now. Returns `false`
        /// if one is already in flight — and records that a rerun is needed, so
        /// the in-flight pass can schedule one more pass when it finishes. This
        /// coalesces requests that arrive mid-cycle (e.g. a layout-bar drag on
        /// macOS 27) instead of silently dropping them.
        func begin() -> Bool {
            guard !isInProgress else {
                rerunRequested = true
                return false
            }
            isInProgress = true
            return true
        }

        /// Ends the current pass and returns whether a rerun was requested while
        /// it was in flight (cleared on read).
        func end() -> Bool {
            isInProgress = false
            let rerun = rerunRequested
            rerunRequested = false
            return rerun
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

        /// Stable per-item identities (owner + title) from the most recent
        /// cache cycle, ordered as enumerated. Used **only on macOS 27**, where
        /// the menu bar items are re-composited inside MenuBarAgent and their
        /// AX-derived windowIDs change on every enumeration even when nothing
        /// moved — comparing windowIDs there recaches in a tight loop. The
        /// identity signature changes only on a real add/remove/reorder.
        private(set) var cachedItemSignature = [String]()

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

        /// Updates the stable per-item identity signature (macOS 27).
        func updateCachedItemSignature(_ signature: [String]) {
            cachedItemSignature = signature
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
            cachedItemSignature.removeAll()
        }
    }

    /// Cache for menu bar items. Extracted to `MenuBarModel.MenuBarItemCache`.
    typealias ItemCache = MenuBarModel.MenuBarItemCache

    /// A pair of control items, taken from a list of menu bar items during a
    /// menu bar item cache operation. Extracted to `MenuBarModel.ControlItemPair`.
    typealias ControlItemPair = MenuBarModel.ControlItemPair

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
            if !item.sectionManagementPolicy.isVisibleInLayout {
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
            // macOS 27 does not support divider-position section classification:
            // dividers stay collapsed, and assignment-backed hiding rebuckets
            // items later via MenuBarSectionController. Treat live managed items as
            // visible at this legacy geometry layer.
            guard MenuBarBackendProvider.current.classifiesSectionByDividerGeometry else {
                return .visible
            }

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

        // Track which items have already been cached to avoid duplicates.
        // macOS can briefly report two windows for the same item during
        // or shortly after a move operation (e.g. layout reset), each with
        // a different windowID. We dedupe on uniqueIdentifier (which
        // excludes windowID) rather than the full tag, since on macOS 27
        // windowIDs are synthetic and churn even within a single
        // enumeration pass; keying on the full tag would let both
        // windowIDs through and double-cache the same logical item. We
        // keep the first occurrence, which is the rightmost (items are
        // reversed from the Window Server order).
        var seenIdentifiers = Set<String>()

        for item in items where context.isValidForCaching(item) {
            guard seenIdentifiers.insert(item.uniqueIdentifier).inserted else {
                MenuBarItemManager.diagLog.debug("uncheckedCacheItems: skipping duplicate tag \(item.logString)")
                continue
            }

            validCount += 1
            if item.sourcePID == nil {
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
                    "Couldn't find section for caching \(item.logString) bounds=\(NSStringFromRect(item.bounds)), assigning fallback section"
                )
                let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
                if item.canBeHidden(experimentalSystemItemHiding: experimentalSystemItemHiding) {
                    context.cache[.hidden].append(item)
                } else {
                    context.cache[.visible].append(item)
                }
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

        let backend = MenuBarBackendProvider.current
        context.cache = backend.rebucket(
            context.cache,
            hider: appState?.menuBarManager.sectionController,
            allowsAlwaysHidden: appState?.settings.advanced.isAlwaysHiddenSectionEnabled ?? false
        )

        guard itemCache != context.cache else {
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

        let shouldPersistLayoutSnapshot = !suppressSpatialOrderPersistenceAfterFailedApply && LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: isRestoringItemOrder,
            isResettingLayout: isResettingLayout,
            isInStartupSettling: isInStartupSettling,
            isApplyingProfileLayout: isApplyingProfileLayout,
            temporarilyShownItemContextsIsEmpty: temporarilyShownItemContexts.isEmpty
        )

        switch MenuBarBackendProvider.current.persistLayoutSnapshot(shouldPersist: shouldPersistLayoutSnapshot) {
        case .none:
            break
        case .mirrorSectionOrder:
            // Repair before mirroring: a group split across sections by an older
            // build must be consolidated first, or this cycle would mirror the
            // split state straight back into savedSectionOrder. Reaching here
            // already means `shouldPersistSavedOrder` passed, so no move is in
            // flight, and the call is a no-op (no write, no refresh) whenever the
            // persisted state is already healthy.
            appState?.menuBarManager.sectionController?.repairGroupInvariantIfNeeded()

            // macOS 27 persists section membership through MenuBarSectionController, not
            // the position-derived savedSectionOrder. Mirror the curated section
            // order from itemCache so profiles, defaults, and applySavedLayout
            // stay in sync with the layout bars without fighting the assignment
            // model.
            let mirrored = computeSectionOrder(from: context.cache)
            if mirrored != savedSectionOrder {
                savedSectionOrder = mirrored
                persistSavedSectionOrder()
                MenuBarItemManager.diagLog.debug(
                    "Mirrored macOS 27 section order: \(mirrored.mapValues(\.count))"
                )
            }
        case .saveSpatialOrder:
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
            let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            let itemCenters = MenuBarSection.Name.allCases.flatMap { section in
                context.cache[section].map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
            }
            let spansDisplays = LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: itemCenters,
                screenFrames: screenFrames
            )
            if hasBlockedItems {
                MenuBarItemManager.diagLog.debug(
                    "Skipping saveSectionOrder; blocked items detected (x=-1), will retry on next cache tick"
                )
            } else if spansDisplays {
                MenuBarItemManager.diagLog.debug(
                    "Skipping saveSectionOrder; menu bar items span multiple displays (relocation in progress)"
                )
            } else if appState?.menuBarManager.sectionController?.overflowHiddenIdentifiers.isEmpty == false {
                // Automatic overflow is presentation state. Persisting this
                // effective cache would turn temporary Hidden membership into
                // authored layout and make it survive after space returns.
                MenuBarItemManager.diagLog.debug(
                    "Skipping saveSectionOrder while automatic overflow is active"
                )
            } else {
                saveSectionOrder(from: context.cache)
            }
        }
        MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")

        // Spawner-style floods arrive outside profile apply. Assignment backends
        // never hit legacy Phase 4, so rebalance here when overflow is enabled.
        // Coalesce behind a single in-flight task so the assertion reflow from
        // one rebalance cannot immediately re-enter another (thrash fix).
        if MenuBarBackendProvider.current.profileLayoutStrategy == .assignmentApply,
           appState?.settings.advanced.enableMenuBarItemOverflow == true
        {
            scheduleMacOS27OverflowRebalance()
        }
    }

    /// Coalesces environment-driven overflow rebalances behind the same task
    /// used by cache updates so assertion reflow cannot feed back into another
    /// immediate rebalance.
    ///
    /// A `force: true` request must survive being coalesced away by a later
    /// `force: false` call (see `overflowRebalanceForcePending`), so the flag
    /// — not the parameter captured by this particular call — decides what
    /// the task that ultimately runs passes to `rebalanceMacOS27OverflowIfNeeded`.
    func scheduleMacOS27OverflowRebalance(force: Bool = false) {
        overflowRebalanceForcePending = Self.nextOverflowRebalanceForcePending(
            currentlyPending: overflowRebalanceForcePending,
            requestedForce: force
        )
        overflowRebalanceTask?.cancel()
        overflowRebalanceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let effectiveForce = self.overflowRebalanceForcePending
            self.overflowRebalanceForcePending = false
            if await self.rebalanceMacOS27OverflowIfNeeded(force: effectiveForce) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await self.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
        }
    }

    /// Pure OR logic behind the force-preservation fix above, split out so it
    /// is unit-testable without spinning up the debounce task's timing.
    static nonisolated func nextOverflowRebalanceForcePending(
        currentlyPending: Bool,
        requestedForce: Bool
    ) -> Bool {
        currentlyPending || requestedForce
    }

    /// Whether a startup or profile-apply settling period is currently active.
    ///
    /// During settling the menu bar is still converging and items are
    /// transiently unresolved before the spatial AX, marker-pair, and
    /// elimination passes finish. Consumers that react to unresolved items
    /// (VirtualDisplayProvoker) must wait until this is false, otherwise they
    /// would treat normal cold-boot churn as genuinely-stuck orphans.
    ///
    /// Tracks `isInStartupSettling` only: that flag is cleared when the period
    /// ends, whereas `startupSettlingTask` keeps referencing the finished task
    /// and so would report settling forever after the first period.
    var isSettling: Bool {
        isInStartupSettling
    }

    /// The window IDs of currently-cached menu bar items that have no resolved
    /// source PID and are not Thaw control items.
    ///
    /// These are the items that may still need marker-pair resolution. On a
    /// single display the bundle-ID marker windows are absent, so these stay
    /// unresolved; VirtualDisplayProvoker uses this to decide when to briefly
    /// add a virtual display so the markers publish. The caller is expected to
    /// ignore the result while isSettling is true, since cold-boot churn
    /// surfaces transient unresolved items here.
    func unresolvedOrphanWindowIDs() -> Set<CGWindowID> {
        Set(
            itemCache.managedItems
                .filter { $0.sourcePID == nil && !$0.isControlItem }
                .map(\.windowID)
        )
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

    /// Runs a self-terminating coalesced cache rerun.
    ///
    /// The coalesced rerun exists so a drag/reset that arrived mid-pass is still
    /// reflected. But an *unconditional* rerun is self-sustaining during an
    /// assessment-mode restriction reflow (hide / reveal): the bar keeps moving
    /// and observers keep requesting reruns, so the chain runs full AX recaches
    /// for the whole reveal — the reveal-time "recache storm" (~10+ passes) that
    /// makes the bar feel harsh.
    ///
    /// This gates the rerun on the actual item signature (now stable against
    /// MenuBarAgent host-child flicker — see ``RuntimeMenuBarBackend/itemCacheSignature``):
    /// it does the full recache only when the live signature differs from the
    /// cache. A genuine mid-cycle drag/reset moves the signature and still reruns
    /// immediately, but once the reflow settles the signature stops changing and
    /// the chain terminates instead of chasing the bar. A newer request cancels
    /// the pending one.
    private func scheduleCoalescedCacheRerun() {
        coalescedCacheRerunTask?.cancel()
        coalescedCacheRerunTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let backend = MenuBarBackendProvider.current
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard !Task.isCancelled else { return }
            guard let signature = backend.itemCacheSignature(items) else {
                // Non-signature backend (≤26): keep the prior unconditional rerun.
                await self.cacheItemsRegardless(skipRecentMoveCheck: true)
                return
            }
            guard signature != self.cacheActor.cachedItemSignature else {
                // Bar has settled — stop the chain rather than recache no-op work.
                return
            }
            await self.cacheItemsRegardless(items.reversed().map(\.windowID))
        }
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
        skipSavedLayoutApply: Bool = false
    ) async {
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil), resolveSourcePID=\(resolveSourcePID), skipSavedLayoutApply=\(skipSavedLayoutApply))"
        )
        defer {
            backgroundCacheContinuation?.resume()
            backgroundCacheContinuation = nil
        }

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
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, coalescing (will rerun)")
            return
        }
        defer {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let needsRerun = await self.cacheGate.end()
                // macOS 27: a drag/reset that arrived mid-cycle was coalesced —
                // run one more pass so the layout bars reflect the latest section
                // assignment. (≤26 keeps its drop-and-forget behavior to avoid
                // snapshotting positions mid-relocation.)
                if needsRerun, MenuBarBackendProvider.current.shouldCoalesceCacheRerun {
                    self.scheduleCoalescedCacheRerun()
                }
            }
        }

        let previousWindowIDs = cacheActor.cachedItemWindowIDs
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
        }

        lastOnScreenMenuBarItems = (items.filter(\.isOnScreen), .now)

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
                    // Only revert while prevPID's process is still actually
                    // running. If it's gone (e.g. the app quit and a *new*
                    // process now legitimately owns this window), reverting
                    // would freeze the cache on a dead PID forever: every
                    // subsequent cycle persists prevPID again (below), so
                    // previousPIDs never advances and this branch fires on
                    // every single cache cycle from then on — a permanent
                    // tug-of-war between this guard and SourcePIDCache's
                    // correct re-resolution, observed as an unbounded stream
                    // of "SourcePID changed" warnings after any menu-bar-item
                    // helper relaunches mid-session.
                    let prevRunningApp = NSRunningApplication(processIdentifier: prevPID)
                    guard let prevRunningApp, !prevRunningApp.isTerminated else {
                        MenuBarItemManager.diagLog.debug(
                            "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID), previous PID's process is gone, accepting new PID"
                        )
                        continue
                    }

                    MenuBarItemManager.diagLog.warning(
                        "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID), reverting to previous PID"
                    )
                    // Rebuild the namespace from the previous PID.
                    let correctedNamespace: MenuBarItemTag.Namespace = if let prevBundleID = prevRunningApp.bundleIdentifier {
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
                let identifier = item.uniqueIdentifier
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

        // currentItemWindowIDs comes straight from the bridging window
        // list and may still contain clone IDs; items has already been
        // filtered, so strip any clone IDs to keep the stored set in sync
        // with the managed item set. The fallback branch is clone-free
        // because items is filtered.
        let itemWindowIDs = (currentItemWindowIDs ?? items.reversed().map(\.windowID))
            .filter { !cloneWindowIDs.contains($0) }
        if MenuBarBackendProvider.current.shouldRetainLastGoodCache(
            snapshotItems: items,
            previousCachedItems: itemCache.managedItems
        ) {
            MenuBarItemManager.diagLog.warning(
                "cacheItemsRegardless: Thaw visible control item missing from AX snapshot; retaining last-good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count)"
            )
            await MainActor.run { self.areControlItemsMissing = true }
            return
        }
        cacheActor.updateCachedItemWindowIDs(itemWindowIDs)
        cacheActor.updateCachedCloneWindowIDs(cloneWindowIDs)
        if let signature = MenuBarBackendProvider.current.itemCacheSignature(items) {
            // Keep stable-identity signature in sync every recache so
            // cacheItemsIfNeeded does not immediately re-fire after a recache
            // triggered by another path (app launch, etc.).
            cacheActor.updateCachedItemSignature(signature)
        }

        await MainActor.run {
            MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
            self.pruneMoveOperationTimeouts(keeping: Set(items.map(\.tag)))
            self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
        }

        // Obtain window IDs from the actual ControlItem objects so the
        // fallback lookup in ControlItemPair can match by window ID when
        // the tag-based and title-based lookups fail (macOS 26+).
        let hiddenControlItemWID: CGWindowID? = appState?.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenControlItemWID: CGWindowID? = appState?.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        let controlItems: ControlItemPair
        if let discoveredControlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
        ) {
            controlItems = discoveredControlItems
            await MainActor.run {
                self.areControlItemsMissing = false
            }
        } else if MenuBarBackendProvider.current.canSynthesizeControlItems(snapshotItems: items) {
            // macOS 27: the hidden / always-hidden control items are kept
            // "present but invisible" by setting their NSStatusItem length to 0.
            // macOS 27 no longer vends an Accessibility element (or WindowServer
            // window) for a zero-length status item, so AX-based discovery above
            // always fails even though nothing is wrong. Divider-position section
            // classification is unavailable on macOS 27 (findSection classifies
            // every live item as .visible), so rather than clearing the cache and
            // falsely reporting the dividers as "hidden by macOS", synthesize a
            // single-section pair: a hidden divider parked at the display's
            // leading edge (every real item sits to its right => visible) and an
            // always-hidden divider at the leading edge when the section is
            // enabled.
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let leadingX = displayID.map { CGDisplayBounds($0).minX } ?? (NSScreen.main?.frame.minX ?? 0)
            let syntheticHidden = MenuBarItem(
                tag: .hiddenControlItem,
                windowID: hiddenControlItemWID ?? 0,
                ownerPID: ourPID,
                sourcePID: ourPID,
                bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                title: ControlItem.Identifier.hidden.rawValue,
                isOnScreen: false
            )
            let syntheticAlwaysHidden: MenuBarItem? = {
                guard appState?.settings.advanced.isAlwaysHiddenSectionEnabled == true else {
                    return nil
                }
                return MenuBarItem(
                    tag: .alwaysHiddenControlItem,
                    windowID: alwaysHiddenControlItemWID ?? 0,
                    ownerPID: ourPID,
                    sourcePID: ourPID,
                    bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                    title: ControlItem.Identifier.alwaysHidden.rawValue,
                    isOnScreen: false
                )
            }()
            controlItems = ControlItemPair(
                hidden: syntheticHidden,
                alwaysHidden: syntheticAlwaysHidden
            )
            await MainActor.run {
                self.areControlItemsMissing = false
            }
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: control item dividers not enumerable on macOS 27 (zero-width => no AX element); synthesized single-section pair so the layout still populates.")
        } else {
            // Control-item disappearance is normally a short WindowServer or
            // status-item publication gap. Publishing an empty cache here makes
            // every layout/search icon visibly disappear and also destroys the
            // last-known section snapshot needed for recovery. Keep the last
            // good cache, mark the diagnostic state, and let the next scheduled
            // enumeration replace it once the controls return.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: Missing control item for hidden section (expected tag: \(MenuBarItemTag.hiddenControlItem)); retaining last-good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count). hiddenControlItemWID=\(hiddenControlItemWID.map { "\($0)" } ?? "nil"), alwaysHiddenControlItemWID=\(alwaysHiddenControlItemWID.map { "\($0)" } ?? "nil")")
            await MainActor.run {
                self.areControlItemsMissing = true
            }
            return
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after control item discovery")
            return
        }

        // MenuBarAgent repopulates its preferred-position table in waves while
        // login items reattach. Do not even enter structural-order policy during
        // that startup window; after settling, the ambient reason remains
        // observation-only on macOS 27 while legacy backends keep their normal
        // divider enforcement.
        if isInStartupSettling {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsRegardless: startup settling active, deferring structural control order"
            )
        } else {
            await enforceControlItemOrder(
                controlItems: controlItems,
                items: items,
                reason: .ambientCacheRefresh
            )
        }

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
        //
        // macOS 27 gate: this heuristic assumes a windowID change signals an
        // app relaunch, which only holds when windowIDs are CGS-stable. On 27
        // every item's windowID is a synthetic FNV hash that churns on every
        // AX enumeration even when nothing relaunched (see
        // cacheItemsIfNeeded's stable-signature gate). Without this guard, a
        // profile item that's genuinely stuck in the wrong section (its
        // synthetic move keeps failing) gets dropped from
        // profileSortedItemIdentifiers on every tick from the windowID churn
        // alone, which re-arms scheduleProfileResort every tick and retries
        // the same impossible move forever — a perpetual synthetic
        // Command-drag storm that warps/hides the cursor system-wide.
        if MenuBarBackendProvider.current.usesProfileWindowIDRelaunchHeuristic,
           let activeLayout = activeProfileLayout,
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
            previousWindowIDs: previousWindowIDs
        ) {
            MenuBarItemManager.diagLog.debug("Relocated new leftmost items; scheduling recache")
            let continuation = self.backgroundCacheContinuation
            self.backgroundCacheContinuation = nil
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
                continuation?.resume()
            }
            return
        }

        if await relocatePendingItems(items, controlItems: controlItems) {
            MenuBarItemManager.diagLog.debug("Relocated pending temporarily-shown items; scheduling recache")
            let continuation = self.backgroundCacheContinuation
            self.backgroundCacheContinuation = nil
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
                continuation?.resume()
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
                currentDisplayID: displayID
            )
            if didApplySavedLayout {
                backgroundCacheContinuation?.resume()
                backgroundCacheContinuation = nil
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
                let currentIdentifiers = Set(
                    items
                        .filter { !$0.isControlItem }
                        .map(\.uniqueIdentifier)
                )
                let newProfileItems = currentIdentifiers
                    .intersection(activeProfileItemIdentifiers)
                    .subtracting(profileSortedItemIdentifiers)
                if !newProfileItems.isEmpty {
                    MenuBarItemManager.diagLog.info("Profile re-sort: detected \(newProfileItems.count) late-arriving profile item(s): \(newProfileItems.sorted())")
                    scheduleProfileResort()
                }
            }
        }

        await MainActor.run {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: finished, cache now has \(self.itemCache.managedItems.count) managed items")
        }
    }

    /// Decides whether a differing item signature warrants a recache, requiring
    /// the change to hold, unchanged, for a stability grace window first.
    ///
    /// The macOS 27 menu bar enumeration is not perfectly stable: apps with
    /// dynamic AX subtrees can momentarily drop or re-add items between passes,
    /// a restriction reflow can transiently perturb which items enumerate, and a
    /// marker/clone window can blink in and out. The autonomous cache tick runs
    /// several times a second, so a plain "seen twice" gate confirms such a flap
    /// almost immediately — driving a recache → `applySavedLayout` → preferred-
    /// position rewrite that visibly reorders icons (the "items keep moving on
    /// their own" reports). Requiring the same differing signature to persist for
    /// the whole grace window instead lets a transient drop/re-add revert — the
    /// signature returns to the cached value and the gate clears — without ever
    /// recaching, while a genuine add/remove holds past the window and confirms.
    ///
    /// Only the autonomous poll is gated this way; real app-event and drag
    /// triggers call `cacheItemsRegardless` directly, so genuine changes still
    /// recache immediately through those paths regardless of this grace.
    ///
    /// - Parameters:
    ///   - firstSeen: When `pending` was first observed (`nil` if no candidate).
    ///   - now: The current instant, injected for testability.
    ///   - grace: How long a difference must hold before it confirms.
    /// - Returns: `recache` — whether to recache now; `newPending` /
    ///   `newFirstSeen` — the candidate and its first-seen instant to remember
    ///   (both `nil` clears the gate).
    static func signatureRecacheDecision(
        cached: [String],
        current: [String],
        pending: [String]?,
        firstSeen: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        grace: Duration
    ) -> (recache: Bool, newPending: [String]?, newFirstSeen: ContinuousClock.Instant?) {
        // Live state matches the cache: nothing to do, drop any stale candidate.
        guard current != cached else {
            return (recache: false, newPending: nil, newFirstSeen: nil)
        }
        // The same differing signature is still standing. Confirm it only once it
        // has held for the full grace window; otherwise keep waiting, preserving
        // when the streak began so the window measures continuous persistence.
        if let pending, let firstSeen, pending == current {
            if now - firstSeen >= grace {
                return (recache: true, newPending: nil, newFirstSeen: nil)
            }
            return (recache: false, newPending: current, newFirstSeen: firstSeen)
        }
        // First sighting, or the difference itself changed: (re)start the clock.
        return (recache: false, newPending: current, newFirstSeen: now)
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        let backend = MenuBarBackendProvider.current

        // Cheap pre-gate (macOS 27): the assertion backend's synthetic window
        // IDs force a full AX walk just to build a change-detection signature,
        // every tick. First compare a cheap menu-bar window-list read — the same
        // signal the legacy path already uses — and skip the walk entirely while
        // the bar is unchanged. A real add/remove/move (or a reveal/hide, which
        // conceals or exposes owners) shifts the window list, so the walk still
        // runs exactly when it matters.
        if backend.usesAssertionHiding {
            let rawWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
            let cloneIDs = cacheActor.cachedCloneWindowIDs
            let cheap = cloneIDs.isEmpty
                ? rawWindowIDs
                : rawWindowIDs.filter { !cloneIDs.contains($0) }
            if let last = periodicWindowListSignature, last == cheap {
                return
            }
            MenuBarItemManager.diagLog.debug(
                "cacheItemsIfNeeded: cheap window-list gate changed (\(periodicWindowListSignature?.count ?? -1) -> \(cheap.count)); walking"
            )
            periodicWindowListSignature = cheap
        }

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        if let signature = backend.itemCacheSignature(items) {
            // Assertion-backed menu bar items use synthetic window IDs, so
            // compare stable visual-order identity instead of WindowServer IDs.
            let cachedSignature = cacheActor.cachedItemSignature
            let decision = Self.signatureRecacheDecision(
                cached: cachedSignature,
                current: signature,
                pending: pendingItemSignatureCandidate,
                firstSeen: pendingItemSignatureFirstSeen,
                now: .now,
                grace: Constants.MenuBarTuning.signatureStabilityGrace
            )
            pendingItemSignatureCandidate = decision.newPending
            pendingItemSignatureFirstSeen = decision.newFirstSeen
            if decision.recache {
                MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: item identities changed and confirmed (\(cachedSignature.count) cached vs \(signature.count) current), triggering recache")
                await cacheItemsRegardless(items.reversed().map(\.windowID))
            } else if decision.newPending != nil {
                MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: item identities differ (\(cachedSignature.count) cached vs \(signature.count) current); deferring recache until the difference holds for the stability grace")
            }
            return
        }

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
        if cachedIDs != itemWindowIDs {
            MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: window IDs changed (\(cachedIDs.count) cached vs \(itemWindowIDs.count) current), triggering recache")
            await cacheItemsRegardless(itemWindowIDs)
        }
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
            }
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
            case .eventOperationTimeout, .itemResponseTimeout:
                true
            case .cannotComplete, .invalidEventSource, .missingMouseLocation,
                 .eventCreationFailure, .itemNotMovable, .missingItemBounds:
                false
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self {
                return nil
            }
            return "Please try again. If the error persists, please file a bug report."
        }
    }

    /// Returns a Boolean value that indicates whether the user has
    /// paused input for at least the given duration.
    ///
    /// - Parameter duration: The duration that certain types of input
    ///   events must not have occured within in order to return `true`.
    private nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
            !MouseHelpers.isButtonPressed()
    }

    /// Waits asynchronously for the user to pause input.
    private nonisolated func waitForUserToPauseInput() async throws {
        let waitTask = Task {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: .milliseconds(50)) {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        do {
            try await waitTask.value
        } catch {
            throw EventError.cannotComplete
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
        // macOS 27: synthetic window IDs always fail cgsGetScreenRectForWindow
        // (error 1000) and spam the log; skip straight to the AX enumeration,
        // which is the only source of truth for item frames on this OS.
        if MenuBarBackendProvider.current.usesAssertionHiding {
            let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
            if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
                refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
                refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) }) ??
                Self.nearestSameOwnerMatch(for: item, in: refreshed)
            {
                return refreshedItem.bounds
            }
            throw EventError.missingItemBounds(item)
        }

        // First attempt: current windowID.
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            return bounds
        }

        // Fallback: refresh on-screen items and pick the matching tag (prefer same windowID, then non-clone).
        let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
        if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) }) ??
            Self.nearestSameOwnerMatch(for: item, in: refreshed)
        {
            return refreshedItem.bounds
        }

        throw EventError.missingItemBounds(item)
    }

    /// Re-resolves a live-updating item whose tag and window ID both change out
    /// from under us. iStat Menus (and similar) rewrite their status-item title
    /// every second; on macOS 27 the synthetic window ID is derived from that
    /// title (see ``MenuBarItemTag``), so neither the tag nor the window ID
    /// matches a fresh enumeration and the title-based fallbacks miss — yielding
    /// `missingItemBounds`, a failed move, and a cursor warp on every retry.
    ///
    /// The position is the only stable signal: in the sub-second between
    /// enumeration and the drag the item has not visibly moved, so among the
    /// same owning app's items the one nearest the original X is the same
    /// logical item. The tolerance keeps this from grabbing a far neighbor when
    /// the item has genuinely gone (in which case failing is correct).
    ///
    /// Restricted to volatile-title third-party items (iStat & co). System
    /// items (Clock, Control Center, Siri, Spotlight) share one namespace and
    /// owning PID, so `hasSameOwner` matches *all* of them — positional guessing
    /// there would conflate Clock with its neighbours. They also have stable
    /// titles, so the title-based fallbacks already resolve them; this heuristic
    /// is neither needed nor safe for them.
    private static nonisolated func nearestSameOwnerMatch(
        for item: MenuBarItem,
        in refreshed: [MenuBarItem]
    ) -> MenuBarItem? {
        guard !item.tag.isNonConcealableSystemItem else { return nil }
        guard item.bounds.width > 0 else { return nil }
        let tolerance = max(item.bounds.width, 24)
        return refreshed
            .filter { $0.hasSameOwner(as: item) && !$0.isSystemClone }
            .filter { abs($0.bounds.minX - item.bounds.minX) <= tolerance }
            .min { abs($0.bounds.minX - item.bounds.minX) < abs($1.bounds.minX - item.bounds.minX) }
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
        item.sourcePID ?? item.ownerPID
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
            context: context
        ) { tap in
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

    private nonisolated func makeContinuationEventTaps(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) -> [EventTap] {
        var eventTaps = [
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
        } catch {
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
    /// Destinations for menu bar item move operations. Extracted to
    /// `MenuBarModel.MoveDestination`.
    typealias MoveDestination = MenuBarModel.MoveDestination

    /// Extracted to `MenuBarModel.LayoutResetDirection`.
    typealias LayoutResetDirection = MenuBarModel.LayoutResetDirection
}

/// App-only additions to `LayoutResetDirection` that aren't part of the
/// shared package surface (used only by `MenuBarItemManager`'s reset-layout
/// diagnostics, not by the private hiding backend).
extension MenuBarModel.LayoutResetDirection {
    var secondPassLogLabel: String {
        switch self {
        case .toHidden:
            "Layout reset"
        case .toVisible:
            "Reset-to-visible"
        }
    }

    var resetsNewLeftmostRelocationSuppression: Bool {
        switch self {
        case .toHidden:
            true
        case .toVisible:
            false
        }
    }
}

extension MenuBarItemManager {
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

    /// Returns the default timeout for click operations.
    private func getDefaultClickOperationTimeout() -> Duration {
        return .milliseconds(350) // Default
    }

    /// Returns the cached timeout for click operations associated with the given item.
    private func getClickOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = clickOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultClickOperationTimeout()
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

        let start: CGPoint
        let end: CGPoint

        switch destination {
        case .leftOfItem:
            start = CGPoint(x: targetBounds.minX, y: targetBounds.minY)
        case .rightOfItem:
            start = CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
        }

        end = start

        MenuBarItemManager.diagLog.debug(
            "Move points: startX=\(start.x) endX=\(end.x) startY=\(start.y) targetMinX=\(targetBounds.minX) itemMinX=\(itemBounds.minX) targetTag=\(destination.targetItem.tag) itemTag=\(item.tag) display=\(displayID)"
        )
        return (start, end)
    }

    /// Returns a Boolean value that indicates whether the given menu bar
    /// item has the correct position, relative to the given destination.
    private nonisolated func itemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MoveDestination,
        on _: CGDirectDisplayID
    ) async throws -> Bool {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
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
    ) async throws {
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postMoveEvents")
            await eventSemaphore.reset(to: 1)
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

        // Fast-fail if the target process is dead. CGEvent.tapCreateForPid
        // silently produces an invalid Mach port for dead PIDs, causing every
        // scrombleEvent to time out and burn the full 3.5 s semaphore budget.
        let eventPID = getEventPID(for: item)
        if kill(eventPID, 0) == -1, errno == ESRCH {
            MenuBarItemManager.diagLog.error("postMoveEvents: target PID \(eventPID) for \(item.logString) is dead; skipping move")
            throw EventError.cannotComplete
        }

        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination, on: displayID)
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
                location: targetPoints.start
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
        let warpPoint = targetPoints.start
        let warpIsOnScreen = NSScreen.screens.contains { $0.frame.contains(warpPoint) }
        if warpIsOnScreen {
            MouseHelpers.warpCursor(to: warpPoint)
        }
        MouseHelpers.hideCursor()
        if warpIsOnScreen {
            await eventSleep(for: .milliseconds(20))
        }
        // For notched displays, when the target is offscreen, redirect
        // mouseDown's hit-test location into the notch itself. The
        // notch is hardware with no clickable UI, so the OS hit-test
        // there has nothing to dismiss, no menu to open, and no app
        // window to surface a click against. mouseUp keeps its
        // original location (the drop position the receiving app
        // uses to place the item). For non-notched displays the
        // original behaviour is preserved (no override).
        if !warpIsOnScreen {
            let activeScreen = NSScreen.screens.first(where: { $0.displayID == displayID })
                ?? NSScreen.main
            if let activeScreen,
               activeScreen.hasNotch,
               let notch = activeScreen.frameOfNotch
            {
                mouseDown.location = CGPoint(
                    x: notch.midX,
                    y: notch.midY
                )
            }
        }
        defer {
            if let mouseLocation {
                MouseHelpers.warpCursor(to: mouseLocation)
            }
            MouseHelpers.showCursor()
            lastMoveOperationTimestamp = .now
            updateMoveOperationTimeout(timeout, for: item)
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
            timeout -= timeout / 4
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
            timeout += timeout / 2
            throw error
        }
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

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        watchdogTimeout: DispatchTimeInterval? = nil,
        maxMoveAttempts: Int = 8,
        allowSectionBoundaryTargetOnMacOS27: Bool = false,
        allowParkedOffMenuBarSource: Bool = false,
        skipPreferredPositionMove: Bool = false
    ) async throws -> Bool {
        // System clone windows are transient WindowServer duplicates that
        // must never be moved. Refuse here as a final safety net so no
        // planning path can drag a phantom and displace real items. The
        // planners filter clones earlier; this backstops every move caller.
        // A no-op is correct: the clone has no managed position to restore
        // and will vanish on its own, so there's nothing to fail or retry.
        guard !item.isSystemClone else {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - system status item clone")
            return false
        }
        guard let appState else {
            throw EventError.cannotComplete
        }
        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        guard item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) else {
            throw EventError.itemNotMovable(item)
        }

        // Pause automated moves while the user is mid-⌘-drag. The user's
        // drag started outside Thaw (their ``leftMouseDown`` already reached
        // MenuBarAgent before this `move()` was dispatched), and
        // ``MoveInputSuppression`` would swallow the user's subsequent
        // ``leftMouseDragged`` events while our synthetic drag runs at the
        // same coordinates. Two overlapping drag intents on macOS 27 leave
        // MenuBarAgent holding a duplicated or stranded icon (the reported
        // "icons multiply on drag" / Finder-crash symptom). Treat a live
        // user drag as authoritative and bail out: the user's drop will
        // re-publish `itemCache`, and `recordExternalMoveOperation` already
        // arms the 5 s applySavedLayout cooldown so our work is not lost —
        // it is deferred past the user's drag without forcing a re-entrant
        // reorder.
        if appState.isDraggingMenuBarItem {
            MenuBarItemManager.diagLog.info("Skipping move for \(item.logString) - user ⌘-drag in progress")
            throw EventError.cannotComplete
        }

        // Most legacy callers target a section divider to trigger the old
        // over-wide reflow, which no longer works on macOS 27. The explicit
        // section-transition path opts in because it uses the divider as a
        // normal, visible Command-drag anchor before updating the assertion.
        let backend = MenuBarBackendProvider.current
        if !backend.allowsSectionBoundaryDividerTarget(allowExplicitOptIn: allowSectionBoundaryTargetOnMacOS27) {
            let target = destination.targetItem
            if target.isControlItem,
               target.tag != .visibleControlItem,
               !allowSectionBoundaryTargetOnMacOS27
            {
                MenuBarItemManager.diagLog.warning(
                    "Skipping legacy divider hide-move of \(item.logString) to \(destination.logString) on macOS 27"
                )
                return false
            }
        }

        // Allow right-of-item moves to proceed even when the item is at x=-1.
        // validateItemPositionAfterMove uses exactly this path to rescue stuck
        // items. The visible Thaw chevron also recovers via left-of-item when
        // applySavedLayout unparks it from the assertion reflow parking band.
        if await isItemBlocked(item) {
            let allowsBlockedMove = switch destination {
            case .rightOfItem: true
            default: item.tag.matchesVisibleControlItem
            }
            guard allowsBlockedMove else {
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - item is blocked (x=-1)")
                throw EventError.cannotComplete
            }
            MenuBarItemManager.diagLog.debug("Proceeding with move of blocked \(item.logString); recovery to visible")
        }

        let livePeers = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        if !allowParkedOffMenuBarSource,
           item.isParkedOffMenuBarBand(among: livePeers)
        {
            MenuBarItemManager.diagLog.warning(
                "Skipping move for \(item.logString) - item is parked off the menu bar band"
            )
            throw EventError.cannotComplete
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
            return true
        }

        // macOS 27: try the cursor-free preferred-position write first. When it
        // applies *and* verifies, the move is done without ever touching the
        // cursor. Position-only backends report an unfulfilled move below when
        // the write cannot be expressed or fails verification.
        if backend.preferredMovePath == .preferredPositionsThenCommandDrag {
            if #available(macOS 27, *) {
                if !skipPreferredPositionMove,
                   await moveItemViaPreferredPositions(
                       item: item,
                       to: destination,
                       experimentalSystemItemHiding: experimentalSystemItemHiding
                   )
                {
                    return true
                }
            }
        }

        // The preferred-position move path is position-only. A move that path
        // cannot express is left unchanged instead of falling through to
        // the cursor-hiding, pointer-warping synthetic Command-drag.
        if backend.preferredMovePath == .preferredPositionsThenCommandDrag {
            MenuBarItemManager.diagLog.info(
                "Position-only reorder could not fulfill \(item.logString) \(destination.logString)"
            )
            return false
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
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        // Tracks whether any postMoveEvents attempt produced observable
        // displacement. Only consulted on retries when the item being
        // moved is a zero-width control item (section divider), where
        // a position match can coincide with bounds drifting onto the
        // target externally; ordinary items skip this gate.
        var anyMoveEventsSucceeded = false

        let maxAttempts = max(1, maxMoveAttempts)
        for n in 1 ... maxAttempts {
            guard !Task.isCancelled else {
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
                        return true
                    }
                    MenuBarItemManager.diagLog.debug(
                        "Position match without observable displacement on attempt \(n); treating as false positive on a zero-width control item and retrying"
                    )
                }
                try await MoveInputSuppression.withUserMouseInputSuppressed {
                    try await postMoveEvents(
                        item: item,
                        destination: destination,
                        on: resolvedDisplayID,
                        warpCursorAfter: false // move() owns the single warp in its defer
                    )
                }
                // postMoveEvents only returns without throwing when both
                // waitForMoveEventResponse calls observed origin changes,
                // i.e. our drag actually displaced the item.
                anyMoveEventsSucceeded = true
                // Verify the item actually reached the correct position.
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) {
                    MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded and verified, finished with move")
                    failureLedger.recordSuccess(for: item)
                    // Validate that item didn't get stuck when moving to hidden section
                    await validateItemPositionAfterMove(item: item, destination: destination, on: resolvedDisplayID)
                    return true
                }
                MenuBarItemManager.diagLog.debug("Attempt \(n) events succeeded but item not at destination, retrying")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
            } catch {
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
                   failureLedger.isUnresponsive(item) {
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

    // MARK: macOS 27 Command-drag move

    /// Applies the saved structural permutation from the current cache before
    /// the restriction is released. Assigned-item snapshots keep concealed
    /// entries available here, so the menu bar can reveal directly into its
    /// final order instead of first publishing an arbitrary permutation that
    /// moves Thaw's click target.
    func prepareMacOS27RevealedOrder() {
        guard !MenuBarBackendProvider.current.supportsLegacySectionHiding,
              let appState
        else {
            return
        }

        let cachedItems = itemCache.managedItems
        let hiddenControlItemWindowID = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenControlItemWindowID = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        var itemsForControlDiscovery = cachedItems
        let discoveredControlItems = ControlItemPair(
            items: &itemsForControlDiscovery,
            hiddenControlItemWindowID: hiddenControlItemWindowID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
        )
        let controlItems: ControlItemPair
        if let discoveredControlItems {
            controlItems = discoveredControlItems
        } else {
            // Collapsed zero-width dividers have no AX children on macOS 27.
            // Use the same synthetic identities as the cache path; the runtime
            // position store resolves their real preference keys by tag/title.
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let leadingX = itemCache.displayID.map { CGDisplayBounds($0).minX }
                ?? (NSScreen.main?.frame.minX ?? 0)
            let hidden = MenuBarItem(
                tag: .hiddenControlItem,
                windowID: hiddenControlItemWindowID ?? 0,
                ownerPID: ourPID,
                sourcePID: ourPID,
                bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                title: ControlItem.Identifier.hidden.rawValue,
                isOnScreen: false
            )
            let alwaysHidden: MenuBarItem? = if appState.settings.advanced.isAlwaysHiddenSectionEnabled {
                MenuBarItem(
                    tag: .alwaysHiddenControlItem,
                    windowID: alwaysHiddenControlItemWindowID ?? 0,
                    ownerPID: ourPID,
                    sourcePID: ourPID,
                    bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                    title: ControlItem.Identifier.alwaysHidden.rawValue,
                    isOnScreen: false
                )
            } else {
                nil
            }
            controlItems = ControlItemPair(
                hidden: hidden,
                alwaysHidden: alwaysHidden
            )
        }

        if restoreMacOS27StructuralControlOrder(
            controlItems: controlItems,
            items: cachedItems
        ) {
            MenuBarItemManager.diagLog.info(
                "macOS 27: prepared cached structural order before reveal"
            )
        }
    }

    /// Restores the complete persisted order after a hidden section becomes
    /// visible. This deliberately performs only the runtime's batch preferred-
    /// position write. It must not enter the per-assignment boundary loop in
    /// ``reconcileMacOS27SectionBoundaries(revealing:)``: that loop made icons
    /// flash through intermediate permutations and temporarily invalidated the
    /// Thaw control item's click target.
    func synchronizeMacOS27RevealedOrder(
        revealing revealedSection: MenuBarSection.Name
    ) async {
        guard !MenuBarBackendProvider.current.supportsLegacySectionHiding,
              let appState,
              appState.menuBarManager.sectionController?.revealedSection == revealedSection
        else {
            return
        }

        let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard !Task.isCancelled,
              appState.menuBarManager.sectionController?.revealedSection == revealedSection
        else {
            return
        }
        let hiddenControlItemWindowID = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenControlItemWindowID = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        var itemsForControlDiscovery = liveItems
        guard let controlItems = ControlItemPair(
            items: &itemsForControlDiscovery,
            hiddenControlItemWindowID: hiddenControlItemWindowID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
        ) else {
            MenuBarItemManager.diagLog.debug(
                "synchronizeMacOS27RevealedOrder: control items not ready"
            )
            return
        }

        let restored = await enforceControlItemOrder(
            controlItems: controlItems,
            items: liveItems,
            reason: .revealedLayoutRestore
        )
        if !restored {
            MenuBarItemManager.diagLog.debug(
                "synchronizeMacOS27RevealedOrder: live order already matches saved layout"
            )
        }
    }

    /// Repairs assignments written by earlier macOS 27 builds that concealed
    /// items without first moving them across a real divider. Runs only while a
    /// hidden section is revealed, because concealed items have no AX elements.
    func reconcileMacOS27SectionBoundaries(
        revealing revealedSection: MenuBarSection.Name
    ) async {
        guard !MenuBarBackendProvider.current.supportsLegacySectionHiding,
              let appState,
              let controller = appState.menuBarManager.sectionController
        else {
            return
        }

        // The divider is collapsed while sections are hidden and therefore has
        // no AX element to position. It has just been republished for this
        // reveal, so establish the Visible/Hidden boundary before moving any
        // assigned items around it.
        var liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let hiddenControlItemWindowID = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenControlItemWindowID = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        var itemsForControlDiscovery = liveItems
        if let controlItems = ControlItemPair(
            items: &itemsForControlDiscovery,
            hiddenControlItemWindowID: hiddenControlItemWindowID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
        ) {
            await enforceControlItemOrder(
                controlItems: controlItems,
                items: liveItems,
                reason: .explicitLayoutRepair
            )
            // Divider enforcement can mutate geometry. Refresh once only when a
            // move was actually planned; routine no-op reconciliation reuses the
            // original all-app AX snapshot.
            if RuntimeLayoutCoordinator.dividerMoveDestination(
                items: liveItems,
                sectionAssignment: controller.sectionAssignment,
                controlItems: controlItems,
                experimentalSystemItemHiding: appState.settings.advanced.enableExperimentalSystemItemHiding
            ) != nil {
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            }
        }

        let sectionsToReconcile: Set<MenuBarSection.Name> = switch revealedSection {
        case .visible, .hidden:
            [.hidden]
        case .alwaysHidden:
            [.hidden, .alwaysHidden]
        }
        let assignments = controller.sectionAssignment
            .filter { sectionsToReconcile.contains($0.value) }
            .sorted { lhs, rhs in lhs.key < rhs.key }
        let experimentalSystemItemHiding = appState.settings.advanced
            .enableExperimentalSystemItemHiding

        for (identifier, section) in assignments {
            guard !Task.isCancelled,
                  controller.revealedSection == revealedSection
            else {
                return
            }

            guard let liveItem = liveItems.first(where: {
                $0.uniqueIdentifier == identifier
            }) else {
                continue
            }

            var itemsForControlDiscovery = liveItems
            guard let controlItems = ControlItemPair(
                items: &itemsForControlDiscovery,
                hiddenControlItemWindowID: hiddenControlItemWindowID,
                alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
            ),
                !RuntimeLayoutCoordinator.liveOrderSatisfiesSectionBoundary(
                    items: liveItems,
                    item: liveItem,
                    section: section,
                    controlItems: controlItems,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                ),
                let destination = RuntimeLayoutCoordinator.sectionBoundaryDestination(
                    for: section,
                    controlItems: controlItems
                )
            else {
                continue
            }

            // Cursor-free boundary repair: write the item's preferred position
            // to be on the correct side of the divider. No reveal or cursor warp
            // needed — the plist write works regardless of assessment-mode state.
            // If the anchor (the Hidden control item) has no plist key yet, skip
            // silently; the ordering pass below will handle placement once keys
            // exist.
            if #available(macOS 27, *),
               RuntimePositionStore.move(
                   item: liveItem,
                   to: destination,
                   liveItems: liveItems,
                   experimentalSystemItemHiding: experimentalSystemItemHiding
               )
            {
                controller.notePreferredPositionsSelfWrite()
                requestMenuBarAgentPositionRefresh()
                MenuBarItemManager.diagLog.info(
                    "Repaired macOS 27 section boundary for \(liveItem.logString) via preferred positions"
                )
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            } else {
                MenuBarItemManager.diagLog.debug(
                    "Skipping macOS 27 section boundary repair for \(liveItem.logString): no resolvable plist key"
                )
            }
        }

        let sectionsToOrder: [MenuBarSection.Name] = switch revealedSection {
        case .visible, .hidden: [.hidden]
        case .alwaysHidden: [.hidden, .alwaysHidden]
        }
        await applyMacOS27SectionItemOrder(
            sections: sectionsToOrder,
            controller: controller,
            whileRevealing: revealedSection
        )

        await cacheItemsRegardless(skipRecentMoveCheck: true)
    }

    /// Applies persisted order one achievable move at a time. Fixed anchors
    /// partition the requested order into independent segments, preventing an
    /// impossible cross-anchor move from driving reconciliation indefinitely.
    /// Re-gathers the recorded order around the current groups and pushes it
    /// into MenuBarAgent's preferred positions, so a group the user just created
    /// physically closes up instead of only becoming contiguous on paper.
    ///
    /// Visible only. Hidden-style sections have no live AX elements to reorder
    /// while concealed; their recorded order is already gathered by
    /// `commitOrder` and is applied when the section is next revealed.
    @MainActor
    func applyGroupOrderToLiveSections() async {
        guard #available(macOS 27, *),
              !MenuBarBackendProvider.current.supportsLegacySectionHiding,
              let controller = appState?.menuBarManager.sectionController
        else {
            return
        }
        // Re-commit so the order reflects the group set that just changed;
        // gathering runs inside the commit. A no-op commit writes nothing.
        controller.regatherGroups()
        await applyMacOS27SectionItemOrder(sections: [.visible], controller: controller)

        // `applyOrder` above only permutes weights MenuBarAgent already holds,
        // which can order a group correctly while leaving other apps' weights
        // between its members — and the agent sorts purely by weight, so the
        // icons stay scattered. Re-space so the members occupy consecutive
        // weights. Only when a group is genuinely interleaved: re-spacing
        // rewrites the whole segment, which is not worth doing on every edit.
        let desiredOrder = (controller.sectionItemOrder[.visible] ?? [])
            .filter { controller.section(for: $0) == .visible }
        if desiredOrder.count > 1, isAnyGroupInterleaved(in: desiredOrder) {
            let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let respaced = RuntimePositionStore.respaceOrder(
                desiredOrder: desiredOrder,
                liveItems: liveItems,
                experimentalSystemItemHiding: appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
            )
            if !respaced.isEmpty {
                controller.notePreferredPositionsSelfWrite()
                requestMenuBarAgentPositionRefresh()
            }
        }

        await cacheItemsRegardless(skipRecentMoveCheck: true)
    }

    /// Whether any group's members are separated by a non-member's weight.
    ///
    /// Reads the live preference weights rather than the desired order: the
    /// order can be perfectly gathered while the weights that actually drive
    /// MenuBarAgent's sort are still interleaved. That gap is the whole reason
    /// a group looks "spilled" despite the model saying otherwise.
    @available(macOS 27, *)
    private func isAnyGroupInterleaved(in desiredOrder: [String]) -> Bool {
        guard let appState else { return false }
        let items = MenuBarSection.Name.allCases.flatMap { appState.itemManager.itemCache.managedItems(for: $0) }
        let groups = Self.groupPolicySet(for: items, appState: appState)
        guard !groups.isEmpty else { return false }

        let positions = RuntimePositionStore.currentPositions()
        guard !positions.isEmpty else { return false }
        let keys = Array(positions.keys)

        var weightByIdentifier = [String: Int]()
        for item in items {
            guard let key = RuntimePositionStore.resolveKey(
                for: item,
                existingKeys: keys,
                positions: positions,
                liveItems: items
            ), let weight = positions[key] else {
                continue
            }
            weightByIdentifier[item.uniqueIdentifier] = weight
        }

        // Only groups that actually live in the order being applied. A group
        // sitting entirely in Hidden is not this pass's problem, and re-spacing
        // the visible segment would not help it anyway.
        let inScope = Set(desiredOrder)
        for group in groups.groups where group.contains(where: inScope.contains) {
            let memberWeights = group.compactMap { weightByIdentifier[$0] }
            guard memberWeights.count >= 2,
                  let low = memberWeights.min(),
                  let high = memberWeights.max()
            else {
                continue
            }
            let memberSet = Set(group)
            let interloper = weightByIdentifier.contains { identifier, weight in
                !memberSet.contains(identifier) && weight > low && weight < high
            }
            if interloper {
                return true
            }
        }
        return false
    }

    private func applyMacOS27SectionItemOrder(
        sections: [MenuBarSection.Name],
        controller: MenuBarSectionController,
        whileRevealing revealedSection: MenuBarSection.Name? = nil,
        repairAfterRestriction: Bool = false
    ) async {
        if appState?.menuBarManager.shouldDeferMacOS27MenuBarMutation == true {
            MenuBarItemManager.diagLog.debug(
                "Skipping macOS 27 section order: native menu bar unavailable/transitioning"
            )
            return
        }

        // The settle window only defers *automatic* visible-section reorders
        // (see `isWithinRestrictionReflowSettleWindow`'s doc comment) that run
        // opportunistically while idle. The hidden/always-hidden path here is
        // the opposite: it's the direct continuation of the user's own reveal
        // action, which is itself the reflow the window is timed from — so
        // gating on it made every reveal-triggered reorder a guaranteed no-op.
        if !repairAfterRestriction, revealedSection == nil, isWithinRestrictionReflowSettleWindow {
            MenuBarItemManager.diagLog.debug(
                "Skipping macOS 27 section order: within restriction-reflow settle window"
            )
            return
        }

        // Tracks whether any item actually moved this pass, so the layout UI's
        // screen capture is refreshed only when the bar changed — not on every
        // idle reconcile (each macOS 27 capture is a heavy full screenshot).
        var didReorder = false
        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false

        for section in sections {
            let desiredOrder = (controller.sectionItemOrder[section] ?? [])
                .filter { controller.section(for: $0) == section }
            guard desiredOrder.count > 1 else {
                continue
            }

            var liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

            // macOS 27: try to realize the whole section order in one cursor-free
            // preferred-position write before the per-pair loop. When it places
            // every item, the loop below finds nothing to do and breaks; any
            // residual (unresolved items, or a reversed-axis guess) is corrected
            // by the loop. Invalidate MenuBarAgent's live layout once after the
            // write, then wait for it to re-sort before re-reading geometry.
            if #available(macOS 27, *) {
                let reordered = RuntimePositionStore.applyOrder(
                    desiredOrder: desiredOrder,
                    liveItems: liveItems,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                )
                if !reordered.isEmpty {
                    controller.notePreferredPositionsSelfWrite()
                    requestMenuBarAgentPositionRefresh()
                    didReorder = true
                    liveItems = await waitForMenuBarAgentResort(
                        desiredOrder: desiredOrder,
                        section: section,
                        controller: controller
                    )
                }
            }

            // After an assessment-mode reflow, synthetic drags routinely fail
            // (volatile neighbours like iStat, concealed bundles still in AX)
            // and can strand collateral items. Preferred-position writes above
            // are sufficient for repair.
            if repairAfterRestriction {
                continue
            }

            let maximumMoves = max(1, desiredOrder.count * 2)

            for _ in 0 ..< maximumMoves {
                guard !Task.isCancelled else { return }
                if let revealedSection, controller.revealedSection != revealedSection {
                    return
                }

                let sectionItems = liveItems.filter {
                    RuntimeLayoutCoordinator.isEligibleForSectionOrder($0, section: section) &&
                        controller.section(for: $0) == section
                }
                guard let plannedMove = RuntimeLayoutCoordinator.nextAchievableOrderMove(
                    items: sectionItems,
                    desiredOrder: desiredOrder,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                ) else {
                    break
                }

                if !repairAfterRestriction,
                   plannedMove.item.isParkedOffMenuBarBand(among: liveItems)
                {
                    MenuBarItemManager.diagLog.debug(
                        "Deferring macOS 27 section order for parked \(plannedMove.item.logString)"
                    )
                    break
                }

                // Denylisted hiding-unsupported items rewrite their AX title
                // frequently, so getCurrentBounds consistently fails to resolve
                // them during the drag — warping the cursor on every attempt.
                // The preferred-position plist path (applyOrder above) is the
                // only reliable move vector for these items; if it didn't achieve
                // the desired order, treat the remaining divergence as
                // unachievable via drag and record the failure key so the 30s
                // backoff suppresses future attempts.
                if plannedMove.item.tag.isHidingUnsupported ||
                    plannedMove.destination.targetItem.tag.isHidingUnsupported
                {
                    let failureKey = Self.macOS27MoveFailureKey(
                        item: plannedMove.item,
                        destination: plannedMove.destination,
                        desiredOrder: desiredOrder
                    )
                    recentMacOS27MoveFailures[failureKey] = .now
                    MenuBarItemManager.diagLog.debug(
                        "Skipping synthetic drag for denylisted hiding-unsupported item in macOS 27 section order: " +
                            "\(plannedMove.item.logString) → \(plannedMove.destination.logString)"
                    )
                    break
                }

                // Some Apple system extras (e.g. Sound) are classified as
                // movable but empirically reject the synthetic Command-drag
                // every time. Without this backoff, the same doomed move gets
                // replanned and retried on every cache cycle (~2s) forever,
                // since the failure never resolves the divergence that
                // triggered it — a perpetual cursor-warp/hide loop that also
                // disrupts the dragged item's own AX state.
                let failureKey = Self.macOS27MoveFailureKey(
                    item: plannedMove.item,
                    destination: plannedMove.destination,
                    desiredOrder: desiredOrder
                )
                if !repairAfterRestriction,
                   let lastFailure = recentMacOS27MoveFailures[failureKey],
                   ContinuousClock.now - lastFailure < Self.macOS27MoveFailureBackoff
                {
                    MenuBarItemManager.diagLog.debug(
                        "Skipping recently-failed macOS 27 section order move for \(plannedMove.item.logString) \(plannedMove.destination.logString)"
                    )
                    break
                }

                do {
                    // Non-concealable Apple system items are ordered best-effort:
                    // they often resist the synthetic drag, so cap them at a single
                    // attempt rather than the default budget — otherwise one pass
                    // would hijack the cursor retrying each stuck system item.
                    // Concealable third-party items keep the normal attempt budget.
                    let fulfilled = try await move(
                        item: plannedMove.item,
                        to: plannedMove.destination,
                        skipInputPause: true,
                        watchdogTimeout: Self.layoutWatchdogTimeout,
                        maxMoveAttempts: plannedMove.item.isNonConcealableSystemItem ? 1 : 8,
                        allowParkedOffMenuBarSource: repairAfterRestriction
                    )
                    guard fulfilled else {
                        recentMacOS27MoveFailures[failureKey] = .now
                        MenuBarItemManager.diagLog.debug(
                            "Could not fulfill macOS 27 section order move via preferred positions: " +
                                "\(plannedMove.item.logString) → \(plannedMove.destination.logString)"
                        )
                        break
                    }
                    recentMacOS27MoveFailures.removeValue(forKey: failureKey)
                    didReorder = true
                    MenuBarItemManager.diagLog.info(
                        "Applied macOS 27 achievable order in \(section.logString) for \(plannedMove.item.logString)"
                    )
                } catch {
                    recentMacOS27MoveFailures[failureKey] = .now
                    MenuBarItemManager.diagLog.error(
                        "Failed to apply macOS 27 section order for \(plannedMove.item.logString): \(error)"
                    )
                    break
                }

                // A drag attempt can change the bar even when verification fails
                // (MenuBarAgent may accept a partial displacement). Let it settle,
                // then refresh once so the next pair is planned from current
                // geometry. No-op pairs above keep sharing the existing snapshot.
                try? await Task.sleep(for: .milliseconds(120))
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            }
        }

        // The bar settled into a new arrangement. The image cache's capture key
        // deliberately ignores position, and its live-refresh loop skips ticks
        // near a move, so without an explicit poke the layout UI keeps showing
        // the pre-reorder screenshot until the next tab switch. Refresh now.
        if didReorder {
            await appState?.imageCache.refreshAfterReorder()
        }
    }

    /// Waits for MenuBarAgent to observe a synchronized preferred-position write
    /// and re-sort, returning the latest geometry. Stops as soon as `isSatisfied`
    /// holds or the poll budget elapses.
    @available(macOS 27, *)
    private func waitForMenuBarAgentLayout(
        maxAttempts: Int? = nil,
        interval: Duration = Constants.MenuBarTuning.menuBarAgentResortPollInterval,
        enumerate: () async -> [MenuBarItem] = { await MenuBarItem.getMenuBarItems(option: .activeSpace) },
        isSatisfied: ([MenuBarItem]) -> Bool
    ) async -> [MenuBarItem] {
        var liveItems = await enumerate()
        let maxAttempts = maxAttempts ?? Self.menuBarAgentResortAttemptCount(
            timeout: appState?.settings.advanced.menuBarOrderFulfillmentTimeout
                ?? Defaults.DefaultValue.menuBarOrderFulfillmentTimeout,
            interval: interval
        )
        for _ in 0 ..< maxAttempts {
            try? await Task.sleep(for: interval)
            liveItems = await enumerate()
            if isSatisfied(liveItems) {
                break
            }
        }
        return liveItems
    }

    /// Converts the user-facing fulfillment window into a poll budget while
    /// clamping malformed persisted values to the Layout control's range.
    static nonisolated func menuBarAgentResortAttemptCount(
        timeout: TimeInterval,
        interval: Duration
    ) -> Int {
        let clampedTimeout = min(max(timeout, 1), 15)
        let intervalMilliseconds = max(1, Double(interval.milliseconds))
        return max(1, Int(ceil((clampedTimeout * 1000) / intervalMilliseconds)))
    }

    /// Waits for MenuBarAgent to re-sort after a batch
    /// ``RuntimePositionStore/applyOrder(desiredOrder:liveItems:environment:)``
    /// write, returning the latest geometry. Polls until `section` satisfies
    /// `desiredOrder` (nothing left to move) or a short budget elapses, so the
    /// caller's per-pair loop reads settled geometry — converged after a clean
    /// batch (it breaks immediately) or current enough to mop up any residual.
    @available(macOS 27, *)
    private func waitForMenuBarAgentResort(
        desiredOrder: [String],
        section: MenuBarSection.Name,
        controller: MenuBarSectionController
    ) async -> [MenuBarItem] {
        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        let orderSatisfied: ([MenuBarItem]) -> Bool = { items in
            let sectionItems = items.filter {
                RuntimeLayoutCoordinator.isEligibleForSectionOrder($0, section: section) &&
                    controller.section(for: $0) == section
            }
            return RuntimeLayoutCoordinator.nextAchievableOrderMove(
                items: sectionItems,
                desiredOrder: desiredOrder,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) == nil
        }
        let liveItems = await waitForMenuBarAgentLayout(isSatisfied: orderSatisfied)
        if orderSatisfied(liveItems) {
            MenuBarItemManager.diagLog.info(
                "Batch preferred-position order satisfied for \(section.logString)"
            )
        }
        return liveItems
    }

    /// Moves a menu bar item on macOS 27 by rewriting MenuBarAgent's own
    /// `TrailingItemPreferredPositions` weight — the cursor-free reorder path.
    ///
    /// Returns `true` only when the write was applied *and* the resulting live
    /// order satisfies `destination`; on any other outcome it returns `false` so
    /// the caller falls back to ``moveItemViaCommandDrag(item:to:on:maxAttempts:)``.
    /// See ``RuntimePositionStore`` for the preference format and the
    /// empirically-uncertain key spelling this verification guards against.
    @available(macOS 27, *)
    private func moveItemViaPreferredPositions(
        item: MenuBarItem,
        to destination: MoveDestination,
        experimentalSystemItemHiding: Bool
    ) async -> Bool {
        let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard RuntimePositionStore.move(
            item: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) else {
            return false
        }
        appState?.menuBarManager.sectionController?.notePreferredPositionsSelfWrite()
        requestMenuBarAgentPositionRefresh()
        // Stamp at issue time, not only on verification: MenuBarAgent starts
        // re-sorting and animating the bar the moment the write lands, and
        // stamping late left that whole window unguarded — the live-refresh
        // loop and itemCache observers screenshotted the bar mid-animation and
        // cached garbled neighbour slices for the entire visible row (#687).
        // A write the agent applies after the poll budget is covered too.
        // Verification below re-stamps, so "since move completed" consumers
        // (e.g. applySavedLayout's cooldown) still see the later time.
        lastMoveOperationTimestamp = .now

        // Poll the live order until MenuBarAgent observes the synchronized write.
        let destinationSatisfied: ([MenuBarItem]) -> Bool = { items in
            RuntimeLayoutCoordinator.liveOrderSatisfiesDestination(
                items: items,
                item: item,
                destination: destination,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        }
        let updated = await waitForMenuBarAgentLayout(isSatisfied: destinationSatisfied)
        if destinationSatisfied(updated) {
            lastMoveOperationTimestamp = .now
            MenuBarItemManager.diagLog.info(
                "Preferred-position move verified for \(item.logString) \(destination.logString)"
            )
            return true
        }

        // A single live icon can have both a stale AX-title preference key and
        // the internal key MenuBarAgent actually sorts. The first write changes
        // the stale candidate enough for positional resolution to identify the
        // active alternate. Retry once from refreshed geometry so one UI drag
        // completes that self-correction without synthetic input or restarting
        // the compositor.
        if let refreshedItem = updated.first(where: {
            $0.tag.matchesIgnoringWindowID(item.tag)
        }),
            RuntimePositionStore.move(
                item: refreshedItem,
                to: destination,
                liveItems: updated,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        {
            appState?.menuBarManager.sectionController?.notePreferredPositionsSelfWrite()
            requestMenuBarAgentPositionRefresh()
            // Same issue-time stamp as the first write above.
            lastMoveOperationTimestamp = .now
            MenuBarItemManager.diagLog.debug(
                "Retrying preferred-position move after refreshed key resolution for \(item.logString)"
            )
            let retried = await waitForMenuBarAgentLayout(isSatisfied: destinationSatisfied)
            if destinationSatisfied(retried) {
                lastMoveOperationTimestamp = .now
                MenuBarItemManager.diagLog.info(
                    "Preferred-position move verified after key-resolution retry for \(item.logString) \(destination.logString)"
                )
                return true
            }
        }

        MenuBarItemManager.diagLog.warning(
            "Preferred-position move did not verify for \(item.logString)"
        )
        return false
    }

    /// Makes MenuBarAgent consume a preferred-position write without restarting
    /// its compositor. Thaw's visible status item provides a safe layout seam.
    private func requestMenuBarAgentPositionRefresh() {
        appState?.menuBarManager.requestMenuBarAgentPositionRefresh()
    }

    /// Moves a menu bar item on macOS 27 by synthesizing the system's own
    /// Command-drag gesture. Fallback for items
    /// ``moveItemViaPreferredPositions(item:to:)`` cannot express as a
    /// preference write.
    ///
    /// macOS 27 hosts every status item inside `MenuBarAgent`'s single
    /// compositor window, so items no longer have individual `CGWindowID`s and
    /// the windowID-addressed move events used on earlier systems do nothing.
    /// The system still honors a manual ⌘-drag to reorder items, hit-tested by
    /// cursor location, so this reproduces that exact gesture: grab the item at
    /// its own center, drag to the target edge, drop. Reverse-engineering
    /// confirmed that the `.maskCommand` flag on the mouse events alone is
    /// sufficient (no system-wide ⌘ keypress is required).
    ///
    /// Verification is by *relative AX order* rather than the exact-pixel
    /// adjacency the windowID path checks, because the bar repacks items
    /// contiguously after a drop, so the dragged item lands flush against its
    /// new neighbor at a position the caller cannot predict to the pixel.
    @available(macOS 27, *)
    private func moveItemViaCommandDrag(
        item: MenuBarItem,
        to destination: MoveDestination,
        on _: CGDirectDisplayID,
        maxAttempts: Int = 2,
        experimentalSystemItemHiding: Bool
    ) async throws {
        let engine = SyntheticMoveEngine(
            eventSemaphore: eventSemaphore,
            makeEventSource: { try self.getEventSource() },
            enumerateItems: {
                await MenuBarItem.getMenuBarItems(option: .activeSpace)
            }
        )
        // postMoveEvents (the legacy windowID-addressed path) stamps
        // lastMoveOperationTimestamp itself; this synthetic-drag path is the
        // only mover on macOS 27, so without this, applySavedLayout's 5s
        // re-apply cooldown never arms here and divergence re-dispatches on
        // every cache cycle instead.
        defer { lastMoveOperationTimestamp = .now }
        try await engine.move(
            item: item,
            to: destination,
            maxAttempts: maxAttempts,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
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
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postClickEvents for \(item.logString)")
            await eventSemaphore.reset(to: 1)
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
            MouseHelpers.warpCursor(to: mouseLocation)
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

        /// The PID of the application that owns this item, used to detect
        /// nonstandard popup windows that ``shownInterfaceWindow`` may miss.
        let sourcePID: pid_t

        /// The display identifier where the item was shown.
        let displayID: CGDirectDisplayID

        /// The destination to return the item to (captured at show-time).
        /// This is the preferred destination, but may become stale if the
        /// target item has moved or disappeared by the time we rehide.
        let returnDestination: MoveDestination

        /// The tag of the neighbor on the opposite side of
        /// ``returnDestination``, used as a secondary fallback to preserve
        /// relative ordering when the primary target is gone.
        let fallbackNeighborTag: MenuBarItemTag?

        /// The PID of the neighbor on the opposite side.
        let fallbackNeighborPID: pid_t?

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

        /// Timestamp for when the item was first shown so we can honor
        /// a short grace period for menus that use nonstandard windows.
        private let firstShownDate = Date.now

        /// Minimum time to treat the item as "showing" even if we can't
        /// detect a popup window (helps apps with unusual window levels).
        private let graceInterval: TimeInterval = 2

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
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
                    return current.isOnScreen
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
                    if app.activationPolicy == .accessory || current.bounds.height > 40 {
                        return current.isOnScreen
                    }
                    return app.isActive && current.isOnScreen
                }
                return current.isOnScreen
            }

            // The tracked window is gone or was never captured. During the
            // grace period, assume the interface is still showing to give
            // apps with nonstandard windows time to create them.
            if Date.now.timeIntervalSince(firstShownDate) < graceInterval {
                return true
            }

            // Grace period expired and no tracked window. Check whether the
            // app has any visible popup or overlay window that we missed.
            return appHasVisiblePopup()
        }

        /// Checks whether the item's owning application has any visible
        /// menu window on screen.
        ///
        /// Matches the pop-up menu level (the level macOS uses for menus opened
        /// from menu bar items). Some apps (e.g. DisplayLink) instead draw their
        /// menu as a status- or main-menu-level window owned by the app rather
        /// than at pop-up level, so those levels are also matched, but only when
        /// the window is taller than a menu bar item, so the status item itself
        /// (which sits in the menu bar) is not mistaken for an open menu. A
        /// liberal "above normal" match was previously used as a catch-all, but
        /// it matched floating panels, modal levels, and other unrelated app
        /// windows, keeping `isShowingInterface` true indefinitely and
        /// preventing rehide.
        private func appHasVisiblePopup() -> Bool {
            let windows = WindowInfo.createWindows(option: .onScreen)
            let popUpLevel = CGWindowLevelForKey(.popUpMenuWindow)
            let statusLevel = CGWindowLevelForKey(.statusWindow)
            let mainMenuLevel = CGWindowLevelForKey(.mainMenuWindow)
            return windows.contains { window in
                guard window.ownerPID == sourcePID else {
                    return false
                }
                let level = CGWindowLevel(Int32(window.layer))
                if level == popUpLevel || level == popUpLevel - 1 {
                    return true
                }
                // Menu bar items are at most ~menu-bar height; a real menu drawn
                // at status/main-menu level is taller, which distinguishes it.
                if level == statusLevel || level == mainMenuLevel {
                    return window.bounds.height > 40
                }
                return false
            }
        }

        init(
            tag: MenuBarItemTag,
            sourcePID: pid_t,
            displayID: CGDirectDisplayID,
            returnDestination: MoveDestination,
            fallbackNeighborTag: MenuBarItemTag?,
            fallbackNeighborPID: pid_t?,
            originalSection: MenuBarSection.Name
        ) {
            self.tag = tag
            self.sourcePID = sourcePID
            self.displayID = displayID
            self.returnDestination = returnDestination
            self.fallbackNeighborTag = fallbackNeighborTag
            self.fallbackNeighborPID = fallbackNeighborPID
            self.originalSection = originalSection
        }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown, along with the tag and PID of the neighbor on the
    /// opposite side (if any) for fallback ordering.
    private func getReturnDestination(
        for item: MenuBarItem,
        in items: [MenuBarItem]
    ) -> (destination: MoveDestination, fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?)? {
        guard let index = items.firstIndex(matching: item.tag) else {
            return nil
        }
        // Prefer anchoring to the item on the right (lower index = further
        // right in macOS menu bar coordinates). The fallback is the item on
        // the opposite side.
        if items.indices.contains(index + 1) {
            let neighbor = items[index + 1]
            let fallback: (MenuBarItemTag, pid_t)? = if items.indices.contains(index - 1) {
                (items[index - 1].tag, items[index - 1].sourcePID ?? items[index - 1].ownerPID)
            } else {
                nil
            }
            return (.leftOfItem(neighbor), fallback)
        }
        if items.indices.contains(index - 1) {
            let neighbor = items[index - 1]
            return (.rightOfItem(neighbor), nil)
        }
        return nil
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

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        let interval = interval ?? appState?.settings.general.tempShowInterval ?? Defaults.DefaultValue.tempShowInterval
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
        // Debounce so rapid app switches (Cmd-Tab spam) collapse to one
        // rehide attempt instead of queuing a separate Task per change ;
        // each rehide call can do an expensive on-screen window enumeration.
        rehideCancellable = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    self.runRehideTimer()
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
    /// The item is returned to its original location after approximately the
    /// configured temporary-show interval, though it may be sooner (e.g. when
    /// switching apps) or later due to the smart rehide logic.
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

        guard let returnInfo = getReturnDestination(for: item, in: items) else {
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
            displayID: resolvedDisplayID,
            returnDestination: returnInfo.destination,
            fallbackNeighborTag: returnInfo.fallbackNeighbor?.tag,
            fallbackNeighborPID: returnInfo.fallbackNeighbor?.pid,
            originalSection: originalSection
        )
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
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
                refreshedItems.first { $0.hasSameIdentity(as: item) } ?? item
        } else {
            // Wait for the item's position to stabilize after the move. Some
            // apps need time to process the window relocation before they can
            // correctly position their popup in response to a click.
            await waitForItemPositionToSettle(item: item)

            // Re-fetch the item from the live window list specifically for this display.
            // Prefer an exact windowID match, then fall back to namespace+title with PID matching.
            let refreshedItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
            clickItem = refreshedItems.first(where: { $0.windowID == item.windowID }) ??
                refreshedItems.first { $0.hasSameIdentity(as: item) } ?? item

            // Give the owning app a little extra time to finish processing the
            // move internally. Some apps (e.g. OneDrive) need more than just a
            // stable window position before they can respond to clicks.
            await eventSleep(for: .milliseconds(25))
        }

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))
        let clickPID = clickItem.sourcePID ?? clickItem.ownerPID

        // Electron/Chromium tray items ignore the synthetic click, so open their
        // menu via an Accessibility press once revealed, mirroring the on-screen
        // path. Other apps (and right-clicks) use the synthetic click below. The
        // popup window capture that follows is unaffected by which path opened it.
        //
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
                    fallbackItems.first { $0.hasSameIdentity(as: clickItem) } ?? clickItem

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
        if let observedInterfaceWindowID {
            context.shownInterfaceWindow = WindowInfo(windowID: observedInterfaceWindowID)
        } else {
            await eventSleep(for: .milliseconds(100))
            let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)

            context.shownInterfaceWindow = windowsAfterClick.first { window in
                window.ownerPID == clickPID && !idsBeforeClick.contains(window.windowID)
            }
        }

        return .movedAndClicked
    }

    /// macOS 27 click path for the Thaw Bar.
    ///
    /// Concealed items live at their real menu-bar position behind the system
    /// visibility assertion, so they can't be clicked while hidden — but unlike
    /// the legacy ``temporarilyShow`` flow they don't need to be *moved* either.
    /// Left clicks press the item's AX element directly (no assertion change, no
    /// flicker); anything that can't take an AX press reveals just that one item,
    /// clicks it at its real location, then re-conceals. No synthetic ⌘-drag,
    /// which is the unreliable part on 27.
    @available(macOS 27, *)
    @MainActor
    func clickConcealedItem(
        item: MenuBarItem,
        with mouseButton: CGMouseButton,
        on displayID: CGDirectDisplayID
    ) async {
        guard let controller = appState?.menuBarManager.sectionController else {
            return
        }

        let section = controller.section(for: item)
        guard section != .visible else {
            // Already visible (e.g. a forced-visible system item) — just click.
            try? await click(item: item, with: mouseButton)
            return
        }

        // Flicker-free fast path (left click). The item's AX element stays in the
        // app's menu-bar-extras tree even while the icon is concealed, so we can
        // open its menu by pressing that element directly — without relaxing the
        // visibility assertion. Relaxing it re-applies the system restriction,
        // which reflows the whole menu bar and momentarily flickers every hidden
        // icon. AXPress maps to the item's default action, so right-clicks (which
        // want a different menu) fall through to the synthetic path below.
        let identifier = item.uniqueIdentifier
        if mouseButton == .left, pressItemViaAccessibility(item) {
            MenuBarItemManager.diagLog.info(
                "clickConcealedItem: opened \(item.logString) via AX press"
            )
            return
        }

        // Fallback: reveal only the touched item, not its whole section, so a
        // click never flashes every hidden icon into the menu bar. This path
        // still re-applies the assertion, so a brief flicker is expected.
        controller.revealItemTemporarily(identifier)

        // Let MenuBarAgent recomposite the revealed item before clicking. This
        // is the same settle the prewarm uses to capture correct glyphs, so the
        // AX bounds are valid by the time it elapses. We deliberately do NOT
        // gate on `Bridging.isWindowOnScreen`: macOS 27 status items carry
        // synthetic window IDs, so that check always fails and would abandon an
        // otherwise-clickable item.
        await eventSleep(for: Constants.MenuBarTuning.iceBarRevealSettle)

        // Re-fetch live AX bounds for an accurate click target. Prefer an exact
        // identity match; fall back to same-owner (a transient "Item-N" title
        // can change between enumerations), then to the original cached item.
        let liveItems = await MenuBarItem.getMenuBarItems(on: displayID, option: .onScreen)
        let liveItem = liveItems.first { $0.hasSameIdentity(as: item) }
            ?? liveItems.first { $0.hasSameOwner(as: item) }
            ?? item

        do {
            try await click(item: liveItem, with: mouseButton)
        } catch {
            MenuBarItemManager.diagLog.error(
                "clickConcealedItem: click failed for \(item.logString): \(error)"
            )
        }

        // Let the opened menu/popup settle before scheduling the delayed
        // re-conceal; menu-open time does not count toward the delay.
        await eventSleep(for: Constants.MenuBarTuning.iceBarPostClickSettle)
        controller.scheduleTemporaryItemConceal(identifier)
    }

    /// Resolves the best move destination for returning a temporarily shown
    /// item to its original section.
    ///
    /// Tries destinations in order of preference:
    /// 1. The captured ``TemporarilyShownItemContext/returnDestination``
    ///    (primary neighbor, refreshed with current bounds).
    /// 2. The ``TemporarilyShownItemContext/fallbackNeighborTag`` (the
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
        if let fallbackTag = context.fallbackNeighborTag,
           let fallbackPID = context.fallbackNeighborPID,
           let freshFallback = items.first(where: {
               $0.tag.matchesIgnoringWindowID(fallbackTag) &&
                   ($0.sourcePID ?? $0.ownerPID) == fallbackPID
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
        switch context.originalSection {
        case .hidden:
            if let controlItem = items.first(matching: .hiddenControlItem) {
                return .leftOfItem(controlItem)
            }
        case .alwaysHidden:
            if let controlItem = items.first(matching: .alwaysHiddenControlItem) {
                return .leftOfItem(controlItem)
            }
            // If the always-hidden section was disabled, fall back to hidden.
            if let controlItem = items.first(matching: .hiddenControlItem) {
                return .leftOfItem(controlItem)
            }
        case .visible:
            // Should not happen (we don't temporarily show items that are
            // already visible), but handle it gracefully.
            return nil
        }

        MenuBarItemManager.diagLog.error("No control items found to resolve return destination for \(context.tag)")
        return nil
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
            guard !temporarilyShownItemContexts.contains(where: \.isShowingInterface) else {
                MenuBarItemManager.diagLog.debug("Menu bar item interface is shown, so waiting to rehide")
                runRehideTimer()
                return
            }
            guard hasUserPausedInput(for: .milliseconds(250)) else {
                MenuBarItemManager.diagLog.debug("Found recent user input, so waiting to rehide")
                runRehideTimer()
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

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
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
                runRehideTimer()
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
        previousWindowIDs: [CGWindowID]
    ) async -> Bool {
        guard appState != nil else { return false }

        if suppressNextNewLeftmostItemRelocation {
            // Seed known identifiers so these baseline items won't be treated as "new"
            // on subsequent cache passes, then clear the suppression flag.
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map(\.uniqueIdentifier)
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
                .map(\.uniqueIdentifier)
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()
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
                previousWindowIDs: previousWindowIDs
            ),
            savedSectionOrder: savedSectionOrder,
            knownItemIdentifiers: knownItemIdentifiers,
            hiddenTags: hiddenTags,
            alwaysHiddenTags: alwaysHiddenTags,
            effectiveNewItemsSection: effectiveNewItemsSection,
            supportsLegacySectionHiding: MenuBarBackendProvider.current.supportsLegacySectionHiding
        )

        switch decision {
        case let .thawIcon(thawIcon):
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
            let backend = MenuBarBackendProvider.current
            let windowServerBounds = backend.supportsLegacySectionHiding
                ? Bridging.getWindowBounds(for: candidate.windowID)
                : nil
            guard backend.relocationBounds(
                itemBounds: candidate.bounds,
                windowServerBounds: windowServerBounds
            ) != nil else {
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
            if let neighbor = context.fallbackNeighborTag {
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

    /// Enforces the spatial section boundaries represented by control items.
    /// A stable, **order-independent** signature of the current item *set* plus
    /// the divider's intended destination. Sorted alphabetically on purpose: a
    /// failed synthetic drag often still shuffles items, so an order-based
    /// signature would change every pass and defeat the thrash guard. Only a
    /// genuine layout change (item added or removed, or a different destination
    /// target) alters this signature and clears the guard.
    private static func dividerSignature(
        items: [MenuBarItem],
        destination: MoveDestination
    ) -> String {
        let ids = items
            .filter { !$0.isSystemClone }
            .map { "\($0.tag.namespace):\($0.tag.title)" }
            .sorted()
            .joined(separator: "|")
        let target = destination.targetItem.tag
        return "\(ids)→\(target.namespace):\(target.title)"
    }

    /// Runtime-host keys for status items that are known to be visible but do
    /// not publish an AX extras-menu-bar child. They remain unmanaged, yet
    /// must occupy a visible structural slot so a divider cannot be sorted to
    /// their right. Keep this list intentionally narrow: stale preference keys
    /// must never influence the live section layout.
    private static func opaqueVisibleRuntimePositionKeys() -> [String] {
        let littleSnitchAgentBundleID = "at.obdev.littlesnitch.agent"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: littleSnitchAgentBundleID).isEmpty else {
            return []
        }
        return ["status:\(littleSnitchAgentBundleID)::Item-0"]
    }

    enum StructuralControlOrderReason {
        case ambientCacheRefresh
        case revealedLayoutRestore
        case explicitLayoutRepair
    }

    static func shouldEnforceMacOS27StructuralControlOrder(
        for reason: StructuralControlOrderReason
    ) -> Bool {
        switch reason {
        case .ambientCacheRefresh:
            false
        case .revealedLayoutRestore, .explicitLayoutRepair:
            true
        }
    }

    /// Visible-section structural sequence for macOS 27 preferred-position
    /// repair. Inserts the Visible Thaw control at its saved layout slot so
    /// enforcement cannot shove it to the far-right edge after a user ⌘-drag.
    ///
    /// When saved order omits the control (fresh install / pre-persist drag),
    /// `ordinaryVisibleItems`' existing order (already resolved by the caller
    /// via `controller.ordered` / `overflowOrderedVisibleItems`) is preserved
    /// as-is; only the control's insertion point is derived from live
    /// geometry. A blanket re-sort here would discard that resolved order for
    /// every other item just because the control's slot was unknown.
    static func structuralVisibleSegment(
        ordinaryVisibleItems: [MenuBarItem],
        visibleControl: MenuBarItem,
        savedOrder: [String]
    ) -> [MenuBarItem] {
        let canonicalOrder = MenuBarItemTag.canonicalPersistentIdentifiers(savedOrder)
        let visibleCanonical = MenuBarItemTag.canonicalPersistentIdentifier(
            visibleControl.uniqueIdentifier
        )
        let liveSegment = MenuBarItem.sortByVisualCenterThenIdentifier(
            ordinaryVisibleItems + [visibleControl]
        )
        guard !canonicalOrder.isEmpty,
              canonicalOrder.contains(visibleCanonical)
        else {
            return liveSegment
        }
        let canonicalSet = Set(canonicalOrder)
        let newlyForcedVisible = liveSegment.filter {
            !canonicalSet.contains(
                MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier)
            )
        }
        let authoredVisible = MenuBarSectionController.overflowOrderedVisibleItems(
            liveSegment.filter {
                canonicalSet.contains(
                    MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier)
                )
            },
            using: savedOrder
        )
        // Newly forced-visible MenuBarAgent children had no authored slot in
        // older layouts. Put them before the authored Visible sequence so its
        // trailing item (normally Thaw beside Control Center) stays trailing.
        return newlyForcedVisible + authoredVisible
    }

    /// Complete left-to-right structural sequence for the runtime position
    /// store. The Always Hidden divider is optional: macOS 27 can omit that
    /// zero-width control from AX even while Hidden and Visible controls remain
    /// available. Hidden -> Visible ordering must still be enforced in that
    /// two-control layout.
    static func macOS27StructuralOrder(
        alwaysHiddenItems: [MenuBarItem],
        alwaysHiddenControlItem: MenuBarItem?,
        hiddenItems: [MenuBarItem],
        hiddenControlItem: MenuBarItem,
        visibleSegment: [MenuBarItem]
    ) -> [MenuBarItem] {
        alwaysHiddenItems
            + (alwaysHiddenControlItem.map { [$0] } ?? [])
            + hiddenItems
            + [hiddenControlItem]
            + visibleSegment
    }

    private func restoreMacOS27StructuralControlOrder(
        controlItems: ControlItemPair,
        items: [MenuBarItem]
    ) -> Bool {
        guard #available(macOS 27, *),
              let visible = items.first(where: { $0.tag.matchesVisibleControlItem }),
              let controller = appState?.menuBarManager.sectionController
        else {
            return false
        }

        let ordinaryItems = items.filter { !$0.isControlItem }
        let alwaysHiddenItems = controller.ordered(
            ordinaryItems.filter { controller.authoredSection(for: $0.uniqueIdentifier) == .alwaysHidden },
            in: .alwaysHidden
        )
        let hiddenItems = controller.ordered(
            ordinaryItems.filter { controller.authoredSection(for: $0.uniqueIdentifier) == .hidden },
            in: .hidden
        )
        let visibleItems = controller.ordered(
            ordinaryItems.filter { controller.authoredSection(for: $0.uniqueIdentifier) == .visible },
            in: .visible
        )
        let recordedVisibleOrder = controller.sectionItemOrder[.visible]
            ?? savedSectionOrder[sectionKey(for: .visible)]
            ?? []
        let visibleSegment = Self.structuralVisibleSegment(
            ordinaryVisibleItems: visibleItems,
            visibleControl: visible,
            savedOrder: recordedVisibleOrder
        )
        let desiredOrder = Self.macOS27StructuralOrder(
            alwaysHiddenItems: alwaysHiddenItems,
            alwaysHiddenControlItem: controlItems.alwaysHidden,
            hiddenItems: hiddenItems,
            hiddenControlItem: controlItems.hidden,
            visibleSegment: visibleSegment
        )
        let reordered = RuntimePositionStore.applyControlItemOrder(
            desiredOrder: desiredOrder,
            opaqueVisibleKeys: Self.opaqueVisibleRuntimePositionKeys(),
            liveItems: items
        )
        guard !reordered.isEmpty else { return false }

        controller.notePreferredPositionsSelfWrite()
        requestMenuBarAgentPositionRefresh()
        MenuBarItemManager.diagLog.info(
            "macOS 27: restored structural divider order for \(reordered.count) control item(s)"
        )
        return true
    }

    private func enforceControlItemOrder(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        reason: StructuralControlOrderReason
    ) async -> Bool {
        // Ambient cache passes observe layout; they must not rewrite the whole
        // preferred-position permutation. Doing so after restriction changes,
        // unlock, and app churn moved the Visible Thaw control away from its
        // saved slot and made unrelated third-party icons oscillate. Explicit
        // reset/migration repair remains allowed to rebuild section boundaries.
        if #available(macOS 27, *),
           !MenuBarBackendProvider.current.supportsLegacySectionHiding,
           !Self.shouldEnforceMacOS27StructuralControlOrder(for: reason)
        {
            MenuBarItemManager.diagLog.debug(
                "enforceControlItemOrder: skipping ambient structural position rewrite"
            )
            return false
        }

        let hidden = controlItems.hidden
        var didRestoreOrder = false

        // macOS 27's runtime host owns the actual control-item order. This
        // must run independently of the legacy/assertion enforcement strategy:
        // collapsed dividers are structural anchors, not draggable items.
        if restoreMacOS27StructuralControlOrder(
            controlItems: controlItems,
            items: items
        ) {
            didRestoreOrder = true
        }

        switch MenuBarBackendProvider.current.controlItemEnforcementStrategy {
        case .assertionDividerReorder:
            let experimentalSystemItemHiding = appState?.settings.advanced
                .enableExperimentalSystemItemHiding ?? false
            guard hidden.isPhysicallyOrderable(
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) else {
                // Zero-width section dividers are not ⌘-draggable on macOS 27;
                // concealment is assignment-driven instead of divider-relative.
                lastFailedDividerSignature = nil
                return didRestoreOrder
            }

            let sectionAssignment = appState?.menuBarManager.sectionController?
                .sectionAssignment ?? [:]
            guard let destination = RuntimeLayoutCoordinator.dividerMoveDestination(
                items: items,
                sectionAssignment: sectionAssignment,
                controlItems: controlItems,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) else {
                // Nothing to enforce — clear the thrash guard so a future genuine
                // divergence is allowed to retry.
                lastFailedDividerSignature = nil
                return didRestoreOrder
            }

            // Divider-thrash guard: when a divider move can't be achieved (e.g.
            // anchored system items sit between the divider and its target), the
            // destination keeps coming back every cache cycle. Without this guard
            // each cycle re-fires the synthetic drag — that's the runaway loop
            // that pulls the cursor toward the menu bar and shuffles icons while
            // the user is idle. If the same move already failed and nothing about
            // the layout changed since, skip it. Forced callers (reveal/reset)
            // bypass the guard so a deliberate action always re-enforces.
            let signature = Self.dividerSignature(items: items, destination: destination)
            if case .ambientCacheRefresh = reason,
               signature == lastFailedDividerSignature
            {
                return didRestoreOrder
            }

            do {
                MenuBarItemManager.diagLog.info(
                    "macOS 27: moving hidden divider left of the visible section"
                )
                try await move(
                    item: hidden,
                    to: destination,
                    skipInputPause: true,
                    allowSectionBoundaryTargetOnMacOS27: true
                )
                lastFailedDividerSignature = nil
                didRestoreOrder = true
            } catch {
                lastFailedDividerSignature = signature
                MenuBarItemManager.diagLog.error(
                    "Error enforcing macOS 27 hidden divider boundary: \(error)"
                )
            }

            // Enforce always-hidden divider left of hidden divider.
            // Skip synthetic items (off-screen); only enforce when both
            // dividers have real geometry so the relative check is meaningful.
            if let alwaysHidden = controlItems.alwaysHidden,
               hidden.isOnScreen, alwaysHidden.isOnScreen,
               hidden.bounds.maxX <= alwaysHidden.bounds.minX
            {
                do {
                    MenuBarItemManager.diagLog.info(
                        "macOS 27: moving always-hidden divider left of hidden divider"
                    )
                    try await move(
                        item: alwaysHidden,
                        to: .leftOfItem(hidden),
                        skipInputPause: true
                    )
                    didRestoreOrder = true
                } catch {
                    MenuBarItemManager.diagLog.error(
                        "Error enforcing macOS 27 always-hidden divider order: \(error)"
                    )
                }
            }
            return didRestoreOrder

        case .legacyDividerSwap:
            guard
                let alwaysHidden = controlItems.alwaysHidden,
                hidden.bounds.maxX <= alwaysHidden.bounds.minX
            else {
                return didRestoreOrder
            }

            do {
                MenuBarItemManager.diagLog.debug("Control items have incorrect order")
                try await move(item: alwaysHidden, to: .leftOfItem(hidden), skipInputPause: true)
                didRestoreOrder = true
            } catch {
                MenuBarItemManager.diagLog.error("Error enforcing control item order: \(error)")
            }
        }
        return didRestoreOrder
    }

    /// Returns a Boolean value that indicates whether any menu bar item
    /// currently has a menu open.
    func isAnyMenuBarItemMenuOpen() async -> Bool {
        let cacheFreshness: Duration = .milliseconds(250)

        if let cachedAt = menuOpenCheckCachedAt,
           cachedAt.duration(to: .now) <= cacheFreshness,
           menuOpenCheckCachedResult == true
        {
            MenuBarItemManager.diagLog.debug("Menu open check: using cached result true")
            return true
        }

        if let existingTask = menuOpenCheckTask {
            MenuBarItemManager.diagLog.debug("Menu open check: joining in-flight probe")
            return await existingTask.value
        }

        let cachedItems = itemCache.managedItems.filter(\.isOnScreen)
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description

        let task = Task.detached(priority: .utility) { () -> Bool in
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
                return false
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

            let fastPathResult = potentialMenuWindows.contains { window in
                let isMenuOpen = fastPathPIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on fast path: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated)
                        """
                    )
                }
                return isMenuOpen
            }

            if fastPathResult {
                MenuBarItemManager.diagLog.debug("Menu open check result: true (fast path)")
                return true
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
                MenuBarItemManager.diagLog.debug("Menu open check result: false (fast path)")
                return false
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check: precise fallback resolving \(unresolvedWindows.count) unresolved window source PIDs"
            )

            let resolvedPIDs = await MenuBarItemManager.resolveAllSourcePIDs(for: unresolvedWindows)

            let precisePIDs = fastPathPIDs.union(resolvedPIDs)
            let result = potentialMenuWindows.contains { window in
                let isMenuOpen = precisePIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on precise fallback: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated)
                        """
                    )
                }
                return isMenuOpen
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check result: \(result) (precise fallback with \(resolvedPIDs.count) resolved PIDs)"
            )
            return result
        }

        menuOpenCheckTask = task
        let result = await task.value
        menuOpenCheckTask = nil
        if result {
            menuOpenCheckCachedResult = true
            menuOpenCheckCachedAt = .now
        } else {
            menuOpenCheckCachedResult = nil
            menuOpenCheckCachedAt = nil
        }
        return result
    }

    private static nonisolated func resolveAllSourcePIDs(for windows: [WindowInfo]) async -> Set<pid_t> {
        let pids = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows)
        return Set(pids.compactMap(\.self))
    }
}

// MARK: - MenuBarItemEventType

/// Event types for menu bar item events.
nonisolated enum MenuBarItemEventType {
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
        case .move(.mouseDown): .maskCommand
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
        case mouseUp

        var cgEventType: CGEventType {
            switch self {
            case .mouseDown: .leftMouseDown
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

        var errorDescription: String? {
            switch self {
            case .missingAppState:
                "Unable to access app state"
            case .missingControlItems:
                "Couldn't find section dividers in the menu bar"
            }
        }

        var recoverySuggestion: String? {
            "Make sure \(Constants.displayName) is running and try again."
        }
    }

    static nonisolated func macOS27OverflowControlUIDs(
        in items: [MenuBarItem]
    ) -> ControlUIDs {
        // ControlItemPair extracts the Hidden divider before managed items are
        // cached. Overflow rebalances commonly consume that managed cache, so
        // use the divider's stable tag identifier when no live item is present.
        let hiddenUID = items.first(where: { $0.tag == .hiddenControlItem })?.uniqueIdentifier
            ?? MenuBarItemTag.hiddenControlItem.tagIdentifier
        return ControlUIDs(
            visible: items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier,
            hidden: hiddenUID,
            alwaysHidden: items.first(where: { $0.tag == .alwaysHiddenControlItem })?.uniqueIdentifier
        )
    }

    /// The groups the overflow planner must treat as indivisible.
    ///
    /// Resolved against the same item list the planner is budgeting, so member
    /// identifiers line up with the uids in `desiredFiltered`.
    private static func groupPolicySet(
        for items: [MenuBarItem],
        appState: AppState?
    ) -> MenuBarItemGroupPolicy.GroupSet {
        guard !MenuBarBackendProvider.current.supportsLegacySectionHiding,
              let appState,
              !items.isEmpty
        else {
            return .empty
        }
        let resolved = MenuBarItemGroupResolver.resolve(
            tags: items.map(\.tag),
            groupSet: appState.itemGroupManager.groupSet
        )
        return MenuBarItemGroupPolicy.GroupSet(
            groups: resolved.map { group in
                group.memberIndices.compactMap { index in
                    items.indices.contains(index) ? items[index].uniqueIdentifier : nil
                }
            }
        )
    }

    /// Surfaces what the (pure, non-logging) overflow planner reported.
    ///
    /// A group too wide for the display, or a uid with no measured width, both
    /// change the outcome silently otherwise.
    private static func logOverflowDiagnostics(_ result: LayoutSolver.NotchOverflowResult) {
        if !result.groupsOverflowedWhole.isEmpty {
            diagLog.info(
                "macOS 27 overflow: moved \(result.groupsOverflowedWhole.count) group(s) to hidden as one unit"
            )
        }
        for group in result.oversizedGroups {
            diagLog.warning(
                "macOS 27 overflow: group \(group.joined(separator: ", ")) is wider than the whole " +
                    "budget and can never fit; moved to hidden without ejecting the rest of the bar"
            )
        }
        if !result.missingWidthUIDs.isEmpty {
            diagLog.warning(
                "macOS 27 overflow: \(result.missingWidthUIDs.count) item(s) had no measured width " +
                    "and were budgeted as zero: \(result.missingWidthUIDs.joined(separator: ", "))"
            )
        }
    }

    /// Moves visible items into Hidden when they exceed the app-menu→Control
    /// Center budget on macOS 27.
    ///
    /// The legacy Phase 4 overflow path never runs on `.assignmentApply`
    /// backends (`applyProfileLayout` returns early), so without this helper
    /// `enableMenuBarItemOverflow` is a no-op: Hidden stays empty and ThawBar
    /// opens with `items=0`.
    @MainActor
    @discardableResult
    func rebalanceMacOS27OverflowIfNeeded(
        items liveItems: [MenuBarItem]? = nil,
        force: Bool = false
    ) async -> Bool {
        guard MenuBarBackendProvider.current.profileLayoutStrategy == .assignmentApply else {
            return false
        }
        guard let appState,
              let controller = appState.menuBarManager.sectionController
        else {
            return false
        }

        guard appState.settings.advanced.enableMenuBarItemOverflow else {
            lastMacOS27OverflowRebalance = nil
            return controller.setOverflowHiddenIdentifiers([])
        }

        if !force,
           let last = lastMacOS27OverflowRebalance,
           Date().timeIntervalSince(last) < 2.0
        {
            return false
        }

        let items: [MenuBarItem] = if let liveItems {
            liveItems.filter { !$0.isSystemClone }
        } else if !itemCache.managedItems.isEmpty {
            itemCache.managedItems.filter { !$0.isSystemClone }
        } else {
            await (MenuBarItem.getMenuBarItems(option: .activeSpace))
                .filter { !$0.isSystemClone }
        }
        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return false
        }

        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        func isProfileItem(_ item: MenuBarItem) -> Bool {
            !item.isControlItem
                && MenuBarSectionController.canAssign(
                    item,
                    to: .hidden,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                )
        }

        let transientTags: [MenuBarItemTag] = [
            .audioVideoModule,
            .faceTime,
            .screenCaptureUI,
            .gameMode,
        ]
        let permanentNonProfileBounds = items.compactMap { item -> CGRect? in
            guard !isProfileItem(item),
                  item.tag != .controlCenter,
                  item.tag != .visibleControlItem
            else { return nil }
            if transientTags.contains(where: {
                $0.namespace == item.tag.namespace && $0.title == item.tag.title
            }) || item.isTransientControlCenterItem {
                return nil
            }
            return item.bounds
        }

        let overflowControlBounds = controller.nativeOverflowControlBounds(on: screen.displayID)
        let capacity = MenuBarCapacitySnapshot.capture(
            on: screen,
            items: items,
            overflowControlBounds: overflowControlBounds
        )
        let availableWidth = capacity.availableWidth(
            in: .trailing,
            applicationMenus: .visible,
            reserving: permanentNonProfileBounds
        )

        let controlUIDs = Self.macOS27OverflowControlUIDs(in: items)
        let visibleCtrl = items.first(where: { $0.tag == .visibleControlItem })
        let ahCtrl = items.first(where: { $0.tag == .alwaysHiddenControlItem })

        let authoredVisibleByGeometry = items
            .filter { item in
                !item.isControlItem
                    && controller.authoredSection(for: item.uniqueIdentifier) == .visible
                    && isProfileItem(item)
            }
            .sorted { lhs, rhs in
                if lhs.bounds.midX == rhs.bounds.midX {
                    return lhs.uniqueIdentifier < rhs.uniqueIdentifier
                }
                return lhs.bounds.midX < rhs.bounds.midX
            }
        let recordedVisibleOrder = controller.sectionItemOrder[.visible]
            ?? savedSectionOrder[MenuBarSection.Name.visible.rawValue]
            ?? []
        let visibleLive = MenuBarSectionController.overflowOrderedVisibleItems(
            authoredVisibleByGeometry,
            using: recordedVisibleOrder
        )

        let hiddenLive = items.filter {
            controller.authoredSection(for: $0.uniqueIdentifier) == .hidden && !$0.isControlItem
        }
        let alwaysHiddenLive = items.filter {
            controller.authoredSection(for: $0.uniqueIdentifier) == .alwaysHidden && !$0.isControlItem
        }

        let visibleSegment: [MenuBarItem] = if let visibleCtrl {
            Self.structuralVisibleSegment(
                ordinaryVisibleItems: visibleLive,
                visibleControl: visibleCtrl,
                savedOrder: recordedVisibleOrder
            )
        } else {
            visibleLive
        }
        var desiredFiltered = visibleSegment.map(\.uniqueIdentifier)
        let hiddenCtrlUID = controlUIDs.hidden
        desiredFiltered.append(hiddenCtrlUID)
        desiredFiltered.append(contentsOf: hiddenLive.map(\.uniqueIdentifier))
        if let ahCtrlUID = ahCtrl?.uniqueIdentifier {
            desiredFiltered.append(ahCtrlUID)
            desiredFiltered.append(contentsOf: alwaysHiddenLive.map(\.uniqueIdentifier))
        }

        var sectionMap = [String: String]()
        for item in visibleSegment {
            sectionMap[item.uniqueIdentifier] = MenuBarSection.Name.visible.rawValue
        }
        for item in hiddenLive {
            sectionMap[item.uniqueIdentifier] = MenuBarSection.Name.hidden.rawValue
        }
        for item in alwaysHiddenLive {
            sectionMap[item.uniqueIdentifier] = MenuBarSection.Name.alwaysHidden.rawValue
        }

        let savedVisible = Set(
            MenuBarItemTag.canonicalPersistentIdentifiers(recordedVisibleOrder)
        )
        let unmanagedUIDs = visibleLive
            .map(\.uniqueIdentifier)
            .filter { !savedVisible.contains(MenuBarItemTag.canonicalPersistentIdentifier($0)) }

        // macOS 27 collapses hidden/overflowed item AX bounds to a sliver
        // (~2pt), so trusting `bounds.width` verbatim deflates the budget's
        // profile baseline and the planner wrongly concludes everything fits —
        // leaving the native overflow control visible. Floor any implausibly
        // narrow non-control item to a nominal status-item width so the budget
        // reflects the real rendered bar. Control items keep their true (thin)
        // width; `visibleLive` never contains control items.
        var uidWidths = [String: CGFloat]()
        var collapsedWidthCount = 0
        for item in visibleLive {
            let measured = item.bounds.width
            if measured < MenuBarItemImageCache.minimumTrustedGlyphWidth {
                collapsedWidthCount += 1
            }
            uidWidths[item.uniqueIdentifier] = Self.budgetWidth(forMeasuredWidth: measured)
        }
        if let visibleCtrl {
            uidWidths[visibleCtrl.uniqueIdentifier] = visibleCtrl.bounds.width
        }
        let trailingLaneItemWidth = uidWidths.values.reduce(0, +)

        MenuBarItemManager.diagLog.debug(
            """
            macOS 27 overflow budget: display=\(screen.displayID) \
            trailingBoundary=\(String(describing: capacity.trailingBoundary)) \
            availableWidth=\(String(describing: availableWidth)) \
            visibleCount=\(visibleLive.count) unmanagedCount=\(unmanagedUIDs.count) \
            trailingLaneItemWidth=\(trailingLaneItemWidth) collapsedWidthCount=\(collapsedWidthCount)
            """
        )

        // A zero/negative/non-finite budget means screen geometry is unsettled,
        // not that every automatically overflowed item suddenly fits.
        guard let availableWidth, availableWidth.isFinite, availableWidth > 0 else {
            return false
        }

        // Ground-truth safety net: if the system's own overflow control is
        // active, the bar is overflowing even when the modeled budget still
        // shows headroom. Trim the effective budget by the observed control
        // width (plus one nominal item) so the planner ejects the leftmost
        // item(s); the debounced probe re-measures each cycle and converges as
        // the bar shrinks. Kept modest to avoid Visible↔Hidden ping-ponging.
        var effectiveAvailableWidth = availableWidth
        if controller.isNativeOverflowActive(on: screen.displayID) {
            let controlWidth = controller.nativeOverflowControlBounds(on: screen.displayID)
                .map(\.width).max() ?? 0
            let deficit = controlWidth + Self.nominalStatusItemWidth
            effectiveAvailableWidth = max(1, availableWidth - deficit)
        }

        let overflowResult = LayoutSolver.planNotchOverflow(
            desiredFiltered: desiredFiltered,
            unmanagedUIDs: unmanagedUIDs,
            controlUIDs: controlUIDs,
            sectionMap: sectionMap,
            uidWidths: uidWidths,
            availableWidth: effectiveAvailableWidth,
            groups: Self.groupPolicySet(for: visibleLive, appState: appState)
        )
        Self.logOverflowDiagnostics(overflowResult)

        lastMacOS27OverflowRebalance = Date()
        let overflowSet = Set(overflowResult.overflowUIDs)
        let overflowItems = visibleLive.filter { overflowSet.contains($0.uniqueIdentifier) }
        if overflowItems.count != overflowSet.count {
            // `setOverflowHiddenIdentifiers` filters again by authored section,
            // so a mismatch here is silently narrowed twice. The upstream
            // invariant should make this unreachable.
            MenuBarItemManager.diagLog.warning(
                "macOS 27 overflow: \(overflowSet.count) planned but only \(overflowItems.count) resolved to live items"
            )
        }
        let didChange = controller.setOverflowHiddenItems(overflowItems)
        if didChange {
            MenuBarItemManager.diagLog.info(
                "macOS 27 overflow: temporarily concealing \(overflowSet.count) authored-visible item(s)"
            )
        }
        return didChange
    }

    /// macOS 27 profile/saved-order apply: writes section membership and order
    /// through ``MenuBarSectionController`` instead of the legacy bulk-move pipeline.
    private func applyProfileLayoutMacOS27(
        appState: AppState,
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        source: ApplySource
    ) async {
        guard let controller = appState.menuBarManager.sectionController else {
            MenuBarItemManager.diagLog.error("applyProfileLayout (macOS 27): missing MenuBarSectionController")
            return
        }

        // On macOS 27 the section controller's `sectionAssignment` is the authority for section
        // membership (it drives the assertion and self-persists via
        // Thaw.simpleSectionAssignment). Only an explicit profile apply should
        // overwrite it. The `.savedOrder` re-apply — fired on every windowID change,
        // e.g. when an item reappears after a layout-bar drag moved it
        // hidden→visible — must NOT push the lagging `savedSectionOrder` back onto
        // the section controller, or the just-dragged item bounces straight back to its old
        // section. The cache-cycle mirror keeps `savedSectionOrder` in sync FROM the
        // section controller instead.
        if source == .profile {
            controller.applyProfileLayout(
                itemSectionMap: itemSectionMap,
                itemOrder: itemOrder
            )

            savedSectionOrder = itemOrder
            persistSavedSectionOrder()
        }

        // Visible items always have live AX elements. Only an explicit profile
        // apply should run synthetic reconciliation; saved-order re-apply is
        // disabled on macOS 27 and assignment mirroring owns section membership.
        if source == .profile {
            await applyMacOS27SectionItemOrder(sections: [.visible], controller: controller)
        }

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // Assignment backends return before legacy Phase 4 overflow; rebalance
        // here so "Move items that don't fit into Hidden" fills Hidden/ThawBar.
        _ = await rebalanceMacOS27OverflowIfNeeded(items: items, force: true)

        MenuBarItemManager.diagLog.info(
            "applyProfileLayout (macOS 27): applied \(controller.sectionAssignment.count) assignment(s)"
        )

        updateProfileSortedSnapshot(source: source, items: items)
        persistProfileStateOnSuccess(source: source)
        clearProfileState(source: source, items: items)
        scheduleDeferredCacheRefresh()
    }

    /// macOS 27 layout reset: sweeps every movable, hideable item (except the
    /// Thaw control item) into the Hidden section via the ``MenuBarSectionController``
    /// assignment model — the 27 equivalent of the legacy control-item move
    /// reset. Items that can't be hidden (Clock, Control Center, …) stay visible
    /// unless experimental system-item hiding is enabled.
    ///
    /// - Returns: Always 0 — there are no physical moves that can "fail" on 27.
    private func resetLayoutMacOS27(to target: MenuBarSection.Name = .hidden) async -> Int {
        isResettingLayout = true
        defer { isResettingLayout = false }

        guard let appState, let controller = appState.menuBarManager.sectionController else {
            MenuBarItemManager.diagLog.warning("macOS 27 reset: no MenuBarSectionController; nothing to do")
            return 0
        }

        // Drop any stale legacy persisted order so the two models never fight.
        savedSectionOrder.removeAll()
        persistSavedSectionOrder()

        // Fresh inventory before the sweep so layout-anchored system items are
        // present in the cache when experimental system-item hiding is on.
        await cacheItemsRegardless(skipRecentMoveCheck: true)

        // Build the "fresh install" assignment from the items currently in the
        // cache (the set the layout bars show): everything hideable → Hidden.
        var assignment = [String: MenuBarSection.Name]()
        var skippedProtectedItems = [String]()
        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        for item in itemCache.managedItems
            where MenuBarSectionController.canAssign(
                item,
                to: target,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        {
            guard !MenuBarSectionController.isProtectedAssignmentItem(
                item,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) else {
                skippedProtectedItems.append(item.uniqueIdentifier)
                continue
            }
            assignment[item.uniqueIdentifier] = target
        }

        controller.resetAssignment(to: assignment)
        if !skippedProtectedItems.isEmpty {
            MenuBarItemManager.diagLog.info("macOS 27 reset: skipped \(skippedProtectedItems.count) protected item(s): \(skippedProtectedItems)")
        }
        MenuBarItemManager.diagLog.info("macOS 27 reset: swept \(assignment.count) item(s) to \(target.rawValue)")

        // Rebuild the cache so the layout bars reflect the new assignment now.
        await cacheItemsRegardless(skipRecentMoveCheck: true)

        // Clock / Control Center / Siri only leave the bar after an assertion
        // teardown→reactivate cycle. The first apply above can leave them
        // assigned-but-still-visible; a forced pulse matches the manual
        // second Reset that users were needing.
        if experimentalSystemItemHiding,
           assignment.contains(where: { identifier, _ in
               itemCache.managedItems.contains {
                   $0.uniqueIdentifier == identifier && $0.tag.isLayoutAnchoredSystemItem
               }
                   || controller.snapshot(for: identifier)?.tag.isLayoutAnchoredSystemItem == true
           })
        {
            MenuBarItemManager.diagLog.info("macOS 27 reset: pulsing restriction for layout-anchored system items")
            controller.refresh(forceRestrictionPulse: true)
            await cacheItemsRegardless(skipRecentMoveCheck: true)
        }

        await MainActor.run {
            appState.imageCache.performCacheCleanup()
        }
        if itemCache.displayID != nil {
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }
        await MainActor.run {
            appState.objectWillChange.send()
        }

        return 0
    }

    /// Resets menu bar layout data to a fresh-install state and moves all
    /// movable, hideable items (except the Thaw icon) to the
    /// Hidden section.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToFreshState() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to fresh state")
        return try await executeReset(for: .freshInstallHidden)
    }

    private func executeReset(for target: SectionResetTarget) async throws -> Int {
        switch MenuBarBackendProvider.current.resetExecution(for: target) {
        case let .assignmentSweep(section):
            if let section {
                return await resetLayoutMacOS27(to: section)
            }
            return await resetLayoutToVisibleMacOS27()
        case .legacyPhysicalMoves:
            switch target {
            case .freshInstallHidden:
                return try await resetLayoutToFreshStateLegacy()
            case .allVisible:
                return try await resetLayoutToVisibleLegacy()
            case .allAlwaysHidden:
                return try await resetLayoutToAlwaysHiddenLegacy()
            }
        }
    }

    private func resetLayoutToFreshStateLegacy() async throws -> Int {
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

        // Reset persisted state so macOS treats section dividers like new.
        if MenuBarBackendProvider.current.usesAssertionHiding {
            ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: ControlItem.Identifier.visible.rawValue)
        } else {
            ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] = 0
        }
        ControlItemDefaults.resetChevronPositions()

        // Forget previously seen/pinned items so we treat everything as new.
        knownItemIdentifiers.removeAll()
        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        pendingRelocations.removeAll()
        pendingReturnDestinations.removeAll()
        savedSectionOrder.removeAll()

        // Clear active profile layout cache.
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        persistKnownItemIdentifiers()
        persistPinnedBundleIDs()
        persistPendingRelocations()
        persistSavedSectionOrder()
        temporarilyShownItemContexts.removeAll()

        // Reset new items placement to default.
        newItemsPlacement = NewItemsPlacement.defaultValue
        Defaults.removeObject(forKey: .newItemsSection)
        Defaults.removeObject(forKey: .newItemsPlacementData)

        // Prevent the first post-reset cache pass from treating the freshly reset items as "new".
        suppressNextNewLeftmostItemRelocation = true

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
                ) {
                    MenuBarItemManager.diagLog.info("Recovered hidden section control item after re-enabling always-hidden section")
                    return try await resetLayoutWithControlItems(controlItems: retryControlItems, items: items)
                }
            }

            throw LayoutResetError.missingControlItems
        }

        await enforceControlItemOrder(
            controlItems: controlItems,
            items: items,
            reason: .explicitLayoutRepair
        )

        return try await resetLayoutWithControlItems(controlItems: controlItems, items: items)
    }

    private func resetLayoutWithControlItems(controlItems: ControlItemPair, items: [MenuBarItem]) async throws -> Int {
        try await resetLayoutWithControlItems(
            controlItems: controlItems,
            items: items,
            direction: .toHidden
        )
    }

    private func resetLayoutWithControlItems(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        direction: LayoutResetDirection
    ) async throws -> Int {
        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        appState.menuBarManager.iceBarPanel.close()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        func controlBounds(for controlItems: ControlItemPair) -> (hidden: CGRect, alwaysHidden: CGRect?) {
            let hiddenBounds = Bridging.getWindowBounds(for: controlItems.hidden.windowID)
                ?? controlItems.hidden.bounds
            let alwaysHiddenBounds = controlItems.alwaysHidden.flatMap {
                Bridging.getWindowBounds(for: $0.windowID) ?? $0.bounds
            }
            return (hiddenBounds, alwaysHiddenBounds)
        }

        func isResetCandidate(_ item: MenuBarItem) -> Bool {
            item.isMovable && item.canBeHidden && !item.isControlItem && item.tag != .visibleControlItem
        }

        func itemsNotInTarget(_ items: [MenuBarItem], controlItems: ControlItemPair) -> [MenuBarItem] {
            let bounds = controlBounds(for: controlItems)
            return items.filter { item in
                guard isResetCandidate(item) else {
                    return false
                }
                let itemBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                return direction.isNotYetInTarget(
                    item: item,
                    bounds: itemBounds,
                    hiddenBounds: bounds.hidden,
                    alwaysHiddenBounds: bounds.alwaysHidden
                )
            }
        }

        func movePass(_ items: [MenuBarItem], controlItems: ControlItemPair) async -> Int {
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
                        to: direction.moveDestination(controlItems: controlItems),
                        skipInputPause: true,
                        watchdogTimeout: Self.layoutWatchdogTimeout
                    )
                } catch {
                    failed += 1
                    MenuBarItemManager.diagLog.error("Failed to move \(item.logString) during \(direction.failureLogLabel): \(error)")
                }
            }
            return failed
        }

        let initialItems = direction.movesAllCandidatesInFirstPass
            ? items
            : itemsNotInTarget(items, controlItems: controlItems)
        _ = await movePass(initialItems, controlItems: controlItems)

        // Give macOS a moment to settle after the first pass.
        try? await Task.sleep(for: .milliseconds(200))

        // Re-fetch and retry only items that are NOT yet in the hidden
        // section. This covers items still in the visible section (to the
        // right of the hidden control item) as well as items stuck in the
        // always-hidden section (to the left of the always-hidden control
        // item) when that section is enabled.
        var refreshedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedMoves = 0
        let refreshHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let refreshAlwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        if let refreshedControls = ControlItemPair(
            items: &refreshedItems,
            hiddenControlItemWindowID: refreshHiddenWID,
            alwaysHiddenControlItemWindowID: refreshAlwaysHiddenWID
        ) {
            let hiddenControlBounds = Bridging.getWindowBounds(for: refreshedControls.hidden.windowID)
                ?? refreshedControls.hidden.bounds
            let alwaysHiddenControlBounds = refreshedControls.alwaysHidden.flatMap {
                Bridging.getWindowBounds(for: $0.windowID) ?? $0.bounds
            }

            let notYetInHidden = refreshedItems.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds

                // Still in the visible section (to the right of hidden control item).
                if bounds.minX >= hiddenControlBounds.maxX {
                    return true
                }
                // Still in the always-hidden section (to the left of always-hidden control item).
                if let ahBounds = alwaysHiddenControlBounds,
                   bounds.maxX <= ahBounds.minX
                {
                    return true
                }
                return false
            }
            let notYetInTarget: [MenuBarItem] = switch direction {
            case .toHidden:
                notYetInHidden
            case .toVisible:
                itemsNotInTarget(refreshedItems, controlItems: refreshedControls)
            }
            if !notYetInTarget.isEmpty {
                MenuBarItemManager.diagLog.debug("\(direction.secondPassLogLabel) pass 2: \(notYetInTarget.count) items not yet in target section")
                failedMoves = await movePass(notYetInTarget, controlItems: refreshedControls)
            }
        }

        cacheActor.clearCachedItemWindowIDs()
        itemCache = ItemCache(displayID: nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.backgroundCacheContinuation = continuation
            Task { [weak self] in
                await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
        }
        if direction.resetsNewLeftmostRelocationSuppression {
            suppressNextNewLeftmostItemRelocation = false
        }

        // Preserve last-good thumbnails while MenuBarAgent reflows the newly
        // visible items. Some assigned-visible items are temporarily absent
        // from the live AX tree (or overflowed), so clearing first leaves no
        // image to retain when the fresh-bounds capture correctly skips them.
        await MainActor.run {
            appState.imageCache.performCacheCleanup()
        }

        if itemCache.displayID != nil {
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }

        await MainActor.run {
            appState.objectWillChange.send()
        }

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

    /// macOS 27 reset-to-visible: clears every section assignment so all
    /// hideable items return to the visible section via ``MenuBarSectionController``.
    ///
    /// - Returns: Always 0 — there are no physical moves that can "fail" on 27.
    private func resetLayoutToVisibleMacOS27() async -> Int {
        isResettingLayout = true
        defer { isResettingLayout = false }

        guard let appState, let controller = appState.menuBarManager.sectionController else {
            MenuBarItemManager.diagLog.warning("macOS 27 reset-to-visible: no MenuBarSectionController; nothing to do")
            return 0
        }

        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        persistPinnedBundleIDs()
        savedSectionOrder.removeAll()
        persistSavedSectionOrder()

        controller.resetAssignment(to: [:])
        MenuBarItemManager.diagLog.info("macOS 27 reset-to-visible: cleared all section assignments")

        await cacheItemsRegardless(skipRecentMoveCheck: true)

        await MainActor.run {
            appState.imageCache.clearAll()
            appState.imageCache.performCacheCleanup()
        }
        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        await MainActor.run {
            appState.objectWillChange.send()
        }

        return 0
    }

    /// Moves every movable, hideable item to the always-hidden section.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToAlwaysHidden() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to always-hidden")
        return try await executeReset(for: .allAlwaysHidden)
    }

    private func resetLayoutToAlwaysHiddenLegacy() async throws -> Int {
        // Legacy path: treat the same as reset-to-visible but then
        // assign to alwaysHidden via MenuBarSectionController.
        let failed = try await resetLayoutToVisibleLegacy()
        guard let appState, let controller = appState.menuBarManager.sectionController else {
            return failed
        }
        var assignment = [String: MenuBarSection.Name]()
        for item in itemCache.managedItems
            where MenuBarSectionController.canAssign(
                item,
                to: .alwaysHidden,
                experimentalSystemItemHiding: appState.settings.advanced.enableExperimentalSystemItemHiding
            )
            && !MenuBarSectionController.isProtectedAssignmentItem(
                item,
                experimentalSystemItemHiding: appState.settings.advanced.enableExperimentalSystemItemHiding
            )
        {
            assignment[item.uniqueIdentifier] = .alwaysHidden
        }
        controller.resetAssignment(to: assignment)
        await cacheItemsRegardless(skipRecentMoveCheck: true)
        return failed
    }

    /// Moves every movable, hideable item to the visible section.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToVisible() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to visible")
        return try await executeReset(for: .allVisible)
    }

    private func resetLayoutToVisibleLegacy() async throws -> Int {
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

        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        persistPinnedBundleIDs()
        savedSectionOrder.removeAll()
        persistSavedSectionOrder()
        temporarilyShownItemContexts.removeAll()

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
            throw LayoutResetError.missingControlItems
        }

        return try await resetLayoutToVisibleWithControlItems(controlItems: controlItems, items: items)
    }

    private func resetLayoutToVisibleWithControlItems(
        controlItems: ControlItemPair,
        items: [MenuBarItem]
    ) async throws -> Int {
        try await resetLayoutWithControlItems(
            controlItems: controlItems,
            items: items,
            direction: .toVisible
        )
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
                itemOrder: layout.itemOrder
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
        suppressSpatialOrderPersistenceAfterFailedApply = false
        guard case .profile = source else { return }
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
            await MainActor.run { appState.objectWillChange.send() }
        }
    }

    /// Executes one full-sort sequence. Used both as the explicit notched
    /// strategy and as the one-shot fallback when an LCS apply fails its final
    /// layout postcondition.
    private func executeFullSortSequence(
        _ sequence: [String],
        hiddenCtrlUID: String,
        ahCtrlUID: String?
    ) async -> Int {
        guard let appState else { return 0 }
        var movedCount = 0

        for uid in sequence {
            guard !Task.isCancelled else { break }
            isRestoringItemOrderTimestamp = Date()

            let freshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let isControlUID = uid == hiddenCtrlUID || uid == ahCtrlUID
            // Control items are the section anchors of the full sort —
            // skipping one would misplace everything after it, so they
            // are exempt from failure backoff.
            if !isControlUID, failureLedger.isUnderBackoff(key: uid) {
                MenuBarItemManager.diagLog.warning(
                    "Profile layout (full sort): \(uid) under move-failure backoff, skipping"
                )
                continue
            }
            guard let item = freshItems.first(where: {
                if isControlUID {
                    return $0.uniqueIdentifier == uid
                }
                return $0.uniqueIdentifier == uid
                    && ($0.canBeHidden || $0.tag == .visibleControlItem)
                    && $0.isMovable
            }) else {
                MenuBarItemManager.diagLog.debug("Profile layout (full sort): \(uid) not found, skipping")
                continue
            }

            guard let controlCenter = freshItems.first(where: { $0.tag == .controlCenter }) else {
                MenuBarItemManager.diagLog.error("Profile layout (full sort): Control Center not found")
                break
            }

            do {
                MenuBarItemManager.diagLog.debug("Profile layout (full sort): \(uid) → .leftOfItem(CC)")
                try await move(item: item, to: .leftOfItem(controlCenter), skipInputPause: true)
                movedCount += 1
                failureLedger.recordSuccess(for: item)
                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                failureLedger.recordFailure(for: item, kind: Self.failureKind(of: error))
                MenuBarItemManager.diagLog.error("Profile layout (full sort): failed \(uid): \(error)")
            }
        }

        guard !Task.isCancelled else { return movedCount }
        try? await Task.sleep(for: .milliseconds(200))
        for section in appState.menuBarManager.sections {
            section.desiredState = .hideSection
            section.controlItem.state = .hideSection
        }
        try? await Task.sleep(for: .milliseconds(200))
        return movedCount
    }

    func applyProfileLayout(
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        source: ApplySource = .profile
    ) async {
        // MARK: Phase 0: gate on startup settling

        //
        // During settling, cacheItemsRegardless skips restore and
        // absorbs every current item into profileSortedItemIdentifiers;
        // a layout applied here has its moves silently shadowed and the
        // late-arrival re-sort path is broken for items that appeared
        // inside the window.
        await waitForStartupSettlingToEnd()

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

        guard let appState else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing appState")
            return
        }
        guard !itemOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applyProfileLayout: no item order, skipping")
            return
        }

        // macOS 27: layout is assignment-backed, not position-based. The legacy
        // bulk-move pipeline below cannot establish section membership on
        // MenuBarAgent-hosted items.
        switch MenuBarBackendProvider.current.profileLayoutStrategy {
        case .assignmentApply:
            await applyProfileLayoutMacOS27(
                appState: appState,
                itemSectionMap: itemSectionMap,
                itemOrder: itemOrder,
                source: source
            )
            return
        case .legacyBulkMove:
            break
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
        guard var itemsCopy = Optional(items),
              let controlItems = ControlItemPair(
                  items: &itemsCopy,
                  hiddenControlItemWindowID: hiddenWID,
                  alwaysHiddenControlItemWindowID: alwaysHiddenWID
              )
        else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing control items")
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

        func liveFlatSequence(from observedItems: [MenuBarItem]) -> (sequence: [String], unresolved: Set<String>)? {
            let liveItems = observedItems.filter { !$0.isSystemClone }
            var workingItems = liveItems
            guard let liveControlItems = ControlItemPair(
                items: &workingItems,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ) else {
                return nil
            }

            var liveContext = CacheContext(
                controlItems: liveControlItems,
                displayID: Bridging.getActiveMenuBarDisplayID()
            )
            var seen = Set<String>()
            var unresolved = Set<String>()
            var sectionUIDs = [MenuBarSection.Name: [String]]()
            for item in liveItems where isProfileItem(item) {
                let uid = item.uniqueIdentifier
                guard uid != hiddenCtrlUID,
                      uid != ahCtrlUID,
                      seen.insert(uid).inserted
                else {
                    continue
                }
                guard let section = liveContext.findSection(for: item) else {
                    unresolved.insert(uid)
                    continue
                }
                sectionUIDs[section, default: []].append(uid)
            }

            return (
                LayoutSolver.flattenCurrentSections(
                    visible: sectionUIDs[.visible] ?? [],
                    hidden: sectionUIDs[.hidden] ?? [],
                    alwaysHidden: sectionUIDs[.alwaysHidden] ?? [],
                    hiddenCtrlUID: hiddenCtrlUID,
                    ahCtrlUID: ahCtrlUID
                ),
                unresolved
            )
        }

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
        // section iteration, once via the explicit append), causing
        // planFullSortSequence's early-return check to fail against a
        // single-divider desiredFiltered and the notched full-sort
        // path to regenerate the entire sequence every cycle.
        var sectionUIDs = [MenuBarSection.Name: [String]]()
        for sectionName in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
            let sectionItems = items.filter { item in
                guard isProfileItem(item) else { return false }
                let uid = item.uniqueIdentifier
                guard uid != hiddenCtrlUID, uid != ahCtrlUID else { return false }
                return sectionByWindowID[item.windowID] == sectionName
            }
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
        let unresolvedGenericCCUIDs = Set(
            items
                .filter { $0.tag.isControlCenterGenericItem && $0.sourcePID == nil }
                .map(\.uniqueIdentifier)
        )
        let unmanagedUIDs = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: desiredSet,
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID,
            visibleCtrlUID: visibleCtrlUID,
            unresolvedGenericCCUIDs: unresolvedGenericCCUIDs
        )
        if !unmanagedUIDs.isEmpty {
            // Build a DesiredLayout for the profile-apply context: the
            // saved layout is the source of truth for previously-seen
            // items; NewItemsPlacement is the fallback for unseen ones.
            // Pinning is left empty here because this code path only
            // positions unmanaged items, not the profile spec items.
            let desiredForUnmanaged = DesiredLayout.fromSavedSectionOrder(
                savedSectionOrder,
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
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: planUnmanagedPlacement \(uid) -> \(placementSummary)"
                )
            }

            let applied = LayoutReconciler.applyUnmanagedPlacementsToDesired(
                placements: placements,
                unmanagedUIDs: unmanagedUIDs,
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap,
                savedSectionOrder: savedSectionOrder,
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
        let activeScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        if appState.settings.advanced.enableMenuBarItemOverflow,
           let screen = activeScreen
        {
            // NSStatusItemSpacing is recorded here for diagnostic logging
            // only. macOS bakes the spacing into each status item's frame
            // (verified empirically: item.bounds.width grows 1:1 with the
            // spacing value), so item.bounds.width and the Control Center
            // item's bounds.minX already account for it. Subtracting a
            // separate (count - 1) * spacing gap here used to double-count
            // the spacing and ejected items into hidden when the bar still
            // had room, most visibly at the macOS default of 16.
            let userSpacing = CGFloat(max(0, 16 + appState.spacingManager.offset))

            // Subtract the layout footprint of items that occupy the
            // visible area but are not profile items: the Clock /
            // date-time display, BentoBox tray on systems that have
            // it, and any immovable accessibility extras. They take
            // real estate in the same way profile items do but are
            // filtered out of visibleUIDs below and would otherwise be
            // invisible to the budget check.
            // Transient system indicators (screen-recording AudioVideoModule,
            // FaceTime call indicator, ScreenCaptureUI overlay) appear and
            // disappear based on system events. Excluding them from the
            // budget keeps the overflow decision tied to the user's
            // permanent layout; otherwise, applying a profile while a
            // recording or call indicator is showing temporarily forces
            // a profile item out of visible, and that item won't come
            // back when the indicator goes away.
            let transientTags: [MenuBarItemTag] = [
                .audioVideoModule,
                .faceTime,
                .screenCaptureUI,
                .gameMode,
            ]
            var nonProfileCount = 0
            var nonProfileBreakdown = [String]()
            let permanentNonProfileBounds = items.compactMap { item -> CGRect? in
                guard !isProfileItem(item),
                      item.tag != .controlCenter,
                      item.tag != .visibleControlItem
                else { return nil }
                if transientTags.contains(where: {
                    $0.namespace == item.tag.namespace && $0.title == item.tag.title
                }) || item.isTransientControlCenterItem {
                    return nil
                }
                nonProfileCount += 1
                nonProfileBreakdown.append("\(item.uniqueIdentifier)=\(item.bounds.width)")
                return item.bounds
            }

            let overflowControlBounds = appState.menuBarManager.sectionController?
                .nativeOverflowControlBounds(on: screen.displayID) ?? []
            let capacity = MenuBarCapacitySnapshot.capture(
                on: screen,
                items: items,
                overflowControlBounds: overflowControlBounds
            )
            let availableWidth = capacity.availableWidth(
                in: .trailing,
                applicationMenus: .visible,
                reserving: permanentNonProfileBounds
            ) ?? 0
            if availableWidth <= 0 {
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: menu bar capacity is unsettled; skipping overflow"
                )
            }

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

            let notchLog = capacity.notchFrame.map { "[\($0.minX)…\($0.maxX)]" } ?? "nil"
            MenuBarItemManager.diagLog.debug(
                """
                Notch overflow budget: display=\(screen.displayID) notch=\(notchLog) \
                trailingBoundary=\(String(describing: capacity.trailingBoundary)) \
                availableWidth=\(availableWidth) userSpacing=\(userSpacing) \
                visibleUIDs.count=\(visibleUIDs.count) \
                nonProfileCount=\(nonProfileCount) \
                nonProfileBreakdown=[\(nonProfileBreakdown.joined(separator: ", "))]
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
                availableWidth: availableWidth,
                groups: Self.groupPolicySet(for: items, appState: appState)
            )
            Self.logOverflowDiagnostics(overflowResult)

            if !overflowResult.overflowUIDs.isEmpty {
                MenuBarItemManager.diagLog.info(
                    "Profile layout: notch overflow; \(overflowResult.overflowUIDs.count) item(s) moved from visible to hidden"
                )
                desiredFiltered = overflowResult.updatedDesiredFiltered
                sectionMap = overflowResult.updatedSectionMap
            }
        }

        // MARK: Phase 5: choose execution strategy (full-sort vs LCS)

        // On notched displays, use a full-section rearrange instead of
        // LCS-based partial moves. LCS leaves "stable" anchors in place,
        // but on notched screens those anchors may sit in or near the
        // notch dead zone, causing subsequent relative moves to fail.
        // A full rearrange places every item explicitly, section by
        // section, using the control items as the starting anchor.
        let useLCSOnNotched = appState.settings.advanced.useLCSSortingOnNotchedDisplays
        let isNotchedDisplay = activeScreen?.hasNotch == true && !useLCSOnNotched

        // Hide cursor for the entire profile apply to avoid visual jitter.
        let savedCursorPosition = NSEvent.mouseLocation
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer { MouseHelpers.showCursor() }
        var shouldPersistAppliedLayout = true

        if isNotchedDisplay {
            // MARK: Phase 6a: full-sort execution (notched)

            let fullSequence = LayoutSolver.planFullSortSequence(
                currentFlat: currentFlat,
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap,
                hiddenCtrlUID: controlItems.hidden.uniqueIdentifier,
                ahCtrlUID: controlItems.alwaysHidden?.uniqueIdentifier
            )
            if fullSequence.isEmpty {
                MenuBarItemManager.diagLog.info("Profile layout (full sort): current order matches desired, skipping")
                concludeProfileApplyWithoutMoves(source: source, items: items)
                scheduleDeferredCacheRefresh()
                return
            }

            let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
            let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

            MenuBarItemManager.diagLog.info(
                "Profile layout (full sort): \(fullSequence.count) item(s) including controls"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout (full sort): sequence = \(fullSequence)"
            )

            let movedCount = await executeFullSortSequence(
                fullSequence,
                hiddenCtrlUID: hiddenCtrlUID,
                ahCtrlUID: ahCtrlUID
            )

            MenuBarItemManager.diagLog.info("Profile layout (full sort): completed with \(movedCount) move(s)")
        } else {
            // MARK: Phase 6b: LCS execution (non-notched)

            // ── Sub-phase 1: Move control items to optimal boundary positions ──
            //
            // Moving a control item reassigns all items on either side to
            // different sections in a single move. Calculate whether moving
            // a control item is cheaper than moving individual items.
            var movedCount = 0

            // Classify items into the two sets Phase 1 actually consults.
            // Read from the sectionByWindowID snapshot built earlier so the
            // classification here matches what the cache-log loop reported
            // above. Calling context.findSection again can return different
            // values for the same windowID if section.show()'s control-item
            // moves landed in between, which surfaces as an empty Phase 1
            // view of currently-occupied hidden / always-hidden sections.
            var currentHiddenSet = Set<String>()
            var currentAHSet = Set<String>()
            for item in items where isProfileItem(item) {
                switch sectionByWindowID[item.windowID] {
                case .hidden:
                    currentHiddenSet.insert(item.uniqueIdentifier)
                case .alwaysHidden:
                    currentAHSet.insert(item.uniqueIdentifier)
                case .visible, nil:
                    break
                }
            }

            let desiredHiddenSet = Set(itemOrder["hidden"] ?? [])
            let desiredAHSet = Set(itemOrder["alwaysHidden"] ?? [])
            // Logged for the log-replay harness so the desired visible set is
            // captured rather than inferred from current visible minus control
            // items and unresolved orphans. Not consulted by Phase 1's section
            // arithmetic, which only crosses hidden and always-hidden.
            let desiredVisibleSet = Set(itemOrder["visible"] ?? [])

            // Check if AH_ctrl needs to move: items changing between hidden↔alwaysHidden.
            let wrongInHidden = currentHiddenSet.subtracting(desiredHiddenSet).intersection(desiredAHSet)
            let wrongInAH = currentAHSet.subtracting(desiredAHSet).intersection(desiredHiddenSet)
            let crossSectionMoves = wrongInHidden.count + wrongInAH.count

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
            let totalSectionMismatch = needsHiddenMove.count + needsAHMove.count

            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: ahCtrlUID=\(ahCtrlUID ?? "nil"), crossSectionMoves=\(crossSectionMoves), totalSectionMismatch=\(totalSectionMismatch)"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: currentHidden=\(currentHiddenSet.sorted())"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: currentAH=\(currentAHSet.sorted())"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: desiredHidden=\(desiredHiddenSet.sorted())"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: desiredAH=\(desiredAHSet.sorted())"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: desiredVisible=\(desiredVisibleSet.sorted())"
            )

            if crossSectionMoves > 0 || totalSectionMismatch > 0, let ahCtrlUID {
                // Moving AH_ctrl to the correct position is 1 move that
                // fixes all hidden↔alwaysHidden assignments.
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: \(crossSectionMoves) items would change hidden↔alwaysHidden, moving AH_ctrl instead"
                )

                let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

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
                if let ahItem = allFreshItems.first(where: { $0.uniqueIdentifier == ahCtrlUID }) {
                    let dest: MoveDestination? = if let firstHiddenUID = desiredHiddenUIDs.first,
                                                    let firstHidden = allFreshItems.first(where: { $0.uniqueIdentifier == firstHiddenUID && $0.isMovable })
                    {
                        // Place AH_ctrl to the LEFT of the rightmost hidden
                        // item. This puts AH_ctrl between AH items and
                        // hidden items.
                        .leftOfItem(firstHidden)
                    } else if let hItem = allFreshItems.first(where: { $0.uniqueIdentifier == hiddenCtrlUID }) {
                        // Hidden is empty; AH_ctrl goes next to H_ctrl.
                        .leftOfItem(hItem)
                    } else {
                        nil
                    }

                    if let dest, !Task.isCancelled {
                        MenuBarItemManager.diagLog.debug("Profile layout: moving AH_ctrl → \(dest.logString)")
                        do {
                            try await move(item: ahItem, to: dest, skipInputPause: true)
                            movedCount += 1
                            try? await Task.sleep(for: .milliseconds(200))
                        } catch {
                            MenuBarItemManager.diagLog.error("Profile layout: failed to move AH_ctrl: \(error)")
                        }
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
                ),
                    let ahItem = freshItems.first(where: { $0.uniqueIdentifier == ahCtrlUID })
                {
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
            if movedCount > 0 {
                // Re-fetch items and rebuild section assignments after
                // the control item move changed section boundaries.
                items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                var itemsCopy2 = items
                guard let freshControl = ControlItemPair(
                    items: &itemsCopy2,
                    hiddenControlItemWindowID: hiddenWID,
                    alwaysHiddenControlItemWindowID: alwaysHiddenWID
                ) else {
                    MenuBarItemManager.diagLog.error("applyProfileLayout: lost control items after phase 1")
                    scheduleDeferredCacheRefresh()
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
            let desiredNoControls = desiredFiltered.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }
            let plannedMoves = LayoutSolver.planLCSMoveSequence(
                currentNoControls: currentNoControls,
                desiredNoControls: desiredNoControls,
                sectionMap: sectionMap
            )

            if plannedMoves.isEmpty {
                if movedCount > 0 {
                    MenuBarItemManager.diagLog.info("Profile layout: completed with \(movedCount) control item move(s), no item reordering needed")
                } else {
                    MenuBarItemManager.diagLog.info("Profile layout: LCS planned no item moves; verifying final layout")
                }
            } else {
                MenuBarItemManager.diagLog.info(
                    "Profile layout: \(plannedMoves.count) item move(s) needed (\(movedCount) control move(s) preceded)"
                )

                for planned in plannedMoves {
                    guard !Task.isCancelled else { break }

                    if failureLedger.isUnderBackoff(key: planned.uid) {
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
                    ) else {
                        break
                    }

                    guard let item = allFreshItems.first(where: {
                        $0.uniqueIdentifier == planned.uid && isProfileItem($0)
                    }) else {
                        continue
                    }

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
                        failureLedger.recordSuccess(for: item)
                        try? await Task.sleep(for: .milliseconds(200))
                    } catch {
                        failureLedger.recordFailure(for: item, kind: Self.failureKind(of: error))
                        MenuBarItemManager.diagLog.error(
                            "Profile layout: failed to move \(planned.uid): \(error)"
                        )
                    }
                }
            }

            if !Task.isCancelled {
                try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            }
            if !Task.isCancelled {
                let observedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                if let observation = liveFlatSequence(from: observedItems) {
                    let observedFlat = observation.sequence
                    let unresolvedTargets = observation.unresolved.intersection(desiredFiltered)
                    let comparison = LayoutSolver.comparePresentLayout(
                        currentFlat: observedFlat,
                        desiredFiltered: desiredFiltered
                    )
                    if comparison.matches, unresolvedTargets.isEmpty {
                        MenuBarItemManager.diagLog.info(
                            "Profile layout: LCS verified after \(movedCount) move(s)"
                        )
                    } else {
                        MenuBarItemManager.diagLog.warning(
                            "Profile layout: LCS postcondition failed; actual=\(comparison.actual) desired=\(comparison.desired); running one full-sort fallback"
                        )
                        let fallbackSequence = LayoutSolver.planFullSortSequence(
                            currentFlat: observedFlat,
                            desiredFiltered: comparison.desired,
                            sectionMap: sectionMap,
                            hiddenCtrlUID: hiddenCtrlUID,
                            ahCtrlUID: ahCtrlUID
                        )
                        let fallbackMoves = await executeFullSortSequence(
                            fallbackSequence,
                            hiddenCtrlUID: hiddenCtrlUID,
                            ahCtrlUID: ahCtrlUID
                        )
                        movedCount += fallbackMoves

                        if !Task.isCancelled {
                            let finalItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                            if let finalObservation = liveFlatSequence(from: finalItems) {
                                let finalFlat = finalObservation.sequence
                                let finalComparison = LayoutSolver.comparePresentLayout(
                                    currentFlat: finalFlat,
                                    desiredFiltered: desiredFiltered
                                )
                                let finalUnresolvedTargets = finalObservation.unresolved.intersection(desiredFiltered)
                                shouldPersistAppliedLayout = finalComparison.matches && finalUnresolvedTargets.isEmpty
                                if !finalComparison.matches {
                                    MenuBarItemManager.diagLog.error(
                                        "Profile layout: full-sort fallback did not converge; actual=\(finalComparison.actual) desired=\(finalComparison.desired)"
                                    )
                                }
                            } else {
                                shouldPersistAppliedLayout = false
                            }
                        }
                    }
                } else {
                    shouldPersistAppliedLayout = false
                    MenuBarItemManager.diagLog.error(
                        "Profile layout: unable to verify LCS because control items disappeared"
                    )
                }
            }
        }

        // MARK: Phase 7: finalize (cursor, snapshot, cache, UI refresh)

        // Restore cursor to its original position.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(savedCursorPosition) })
            ?? NSScreen.main
        if let screen {
            let cgY = screen.frame.origin.y + screen.frame.height - savedCursorPosition.y
            MouseHelpers.warpCursor(to: CGPoint(x: savedCursorPosition.x, y: cgY))
        }

        // Re-fetch items after moves and update the snapshot so the
        // late-arrival detection doesn't re-trigger for items we just sorted.
        // Profile-only: the profile-sorted snapshot and
        // isApplyingProfileLayout flag are only meaningful when a
        // profile is active; the savedOrder source leaves them alone.
        items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // Commit profile state to disk only if we weren't cancelled
        // mid-Phase-6. The in-loop cancellation guards break out of the
        // move loop but execution still flows into Phase 7; without
        // this check we'd persist a profile that was only partially
        // applied to the bar.
        if !Task.isCancelled, shouldPersistAppliedLayout {
            persistProfileStateOnSuccess(source: source)
        }
        suppressSpatialOrderPersistenceAfterFailedApply = !Task.isCancelled && !shouldPersistAppliedLayout
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
    /// section show/hide animations. Multi-instance baseIDs use
    /// "last write wins" in the expected-section map; this can
    /// false-positive when a single app has instances split across
    /// sections in `savedSectionOrder`, but the bulk apply
    /// early-returns when no moves are needed, so the cost is minor.
    private func currentLayoutDivergesFromSaved(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        controller: MenuBarSectionController?
    ) -> Bool {
        var savedSectionByBaseID = [String: MenuBarSection.Name]()
        for (sectionKey, ids) in savedSectionOrder {
            guard let section = sectionName(for: sectionKey) else { continue }
            for id in ids {
                let parts = id.split(separator: ":", maxSplits: 2)
                let baseID = parts.prefix(2).joined(separator: ":")
                savedSectionByBaseID[baseID] = section
            }
        }
        guard !savedSectionByBaseID.isEmpty else { return false }

        // The per-OS classification (spatial bounds on legacy, assignment via
        // MenuBarSectionController on the assertion backend) lives in the backend.
        return MenuBarBackendProvider.current.layoutMembershipDiverged(
            savedSectionByBaseID: savedSectionByBaseID,
            items: items,
            controlItems: controlItems,
            hider: controller
        )
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
    /// divergence check still runs and catches genuine section drift. The
    /// per-OS policy now lives in ``MenuBarBackend/windowIDsChanged(previous:current:previousDisplayID:currentDisplayID:)``.
    func applySavedLayout(
        items: [MenuBarItem],
        previousWindowIDs: [CGWindowID],
        controlItems: ControlItemPair,
        previousDisplayID: CGDirectDisplayID? = nil,
        currentDisplayID: CGDirectDisplayID? = nil
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
        guard !lastMoveOperationOccurred(within: .seconds(5)) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, within 5s move cooldown")
            return false
        }
        // Bail out if the user is currently ⌘-dragging an item. Running a
        // bulk synthetic-drag apply while the user is dragging would post our
        // synthetic events on top of the user's in-flight drag
        // (`MoveInputSuppression` swallows the user's `leftMouseDragged` but
        // not their already-delivered `leftMouseDown`), producing the
        // duplicate-icon / Finder-crash symptom reported on macOS 27. The
        // user's drop re-publishes `itemCache` (see
        // `recordExternalMoveOperation` + the 5 s cooldown above) so the
        // deferred apply runs naturally once the drag settles.
        if appState?.isDraggingMenuBarItem ?? false {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, user ⌘-drag in progress")
            return false
        }
        if let lastRestrictionChange = lastRestrictionChangeTimestamp,
           lastRestrictionChange.duration(to: .now) < Self.restrictionChangeLayoutSettleWindow
        {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, within restriction-reflow settle window"
            )
            return false
        }
        // savedSectionOrder is mirrored FROM the section controller each cache cycle, not
        // restored TO it. Spatial layout-divergence falsely fired bulk visible-
        // section reorders after assertion reflow (items left of the hidden
        // control are still visible-assigned), which collided with volatile
        // neighbours like iStat and stranded them off the bar.
        switch MenuBarBackendProvider.current.savedLayoutRestoreStrategy {
        case .visibleControlOrderOnly:
            return await restoreMacOS27VisibleControlOrder(items: items)
        case .spatialBulkApply:
            break
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
        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousWindowIDs)
        let windowIDsChanged = MenuBarBackendProvider.current.windowIDsChanged(
            previous: previousWindowIDSet,
            current: currentWindowIDSet,
            previousDisplayID: previousDisplayID,
            currentDisplayID: currentDisplayID
        )
        let layoutDiverged = windowIDsChanged
            ? false
            : currentLayoutDivergesFromSaved(
                items: items,
                controlItems: controlItems,
                controller: appState?.menuBarManager.sectionController
            )
        guard windowIDsChanged || layoutDiverged else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no windowID change and saved layout matches current")
            return false
        }

        // Geometry-readiness gate. On a notched display, if Control Center is
        // reported at or left of the notch's right edge the menu bar geometry
        // has not settled: a stale off-screen position reported transiently
        // during a display reconnect or Control Center widget churn. Dispatching
        // the bulk apply now runs the control-item placement against that
        // geometry and mis-positions the Thaw visible icon to the far left (the
        // notch-overflow budget guard alone only suppresses the eject, not the
        // moves). Skip; the cache cycle falls through to a plain recache and a
        // later tick retries once the geometry settles.
        if let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main,
           screen.hasNotch,
           let notch = screen.frameOfNotch
        {
            let rightBoundary = items.first(where: { $0.tag == .controlCenter })?.bounds.minX
                ?? screen.frame.maxX
            guard LayoutSolver.isMenuBarGeometryReady(rightBoundary: rightBoundary, notchMaxX: notch.maxX) else {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, menu bar geometry not settled (rightBoundary=\(rightBoundary), notch.maxX=\(notch.maxX))"
                )
                return false
            }
        }

        // Display-spread gate. While the active menu bar is relocating to
        // another display macOS migrates the status item windows between
        // screens asynchronously, so the items transiently straddle two
        // displays. A bulk apply dispatched now resolves each item's move
        // against whichever display its window currently occupies and cannot
        // converge, stranding items on the wrong screen where they read as
        // un-hidden. Skip; a later tick retries once the items collapse back
        // onto the active display. Frames come from CGDisplayBounds so they
        // share the top-left origin coordinate space of the item bounds.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        let itemCenters = items.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
        if LayoutSolver.itemsSpanMultipleDisplays(itemCenters: itemCenters, screenFrames: screenFrames) {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, menu bar items span multiple displays (relocation in progress)"
            )
            return false
        }

        // Saved-tags intersection: skip if none of the saved items are
        // currently present. Matches the legacy restore's guard;
        // protects against running the bulk apply on a menu bar that
        // shares no widgets with the persisted layout.
        let currentTags = Set(items.map(\.uniqueIdentifier))
        let savedTags = Set(savedSectionOrder.values.flatMap { MenuBarItemTag.canonicalPersistentIdentifiers($0) })
        guard !savedTags.isDisjoint(with: currentTags) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no saved items currently present")
            return false
        }

        // Build itemSectionMap from savedSectionOrder. Each identifier
        // points back at its persisted section key.
        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in savedSectionOrder {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }

        let trigger = windowIDsChanged ? "windowID change" : "layout divergence"
        MenuBarItemManager.diagLog.info("applySavedLayout: dispatching bulk apply (\(trigger))")

        // The shared body uses itemOrder as the per-section ordered
        // identifier list, which is structurally identical to
        // savedSectionOrder. Pass the saved order through unchanged.
        // Pinning is preserved from existing state, not derived from
        // savedSectionOrder (savedSectionOrder has no pinning concept).
        await applyProfileLayout(
            pinnedHidden: pinnedHiddenBundleIDs,
            pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
            sectionOrder: savedSectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: savedSectionOrder,
            source: .savedOrder
        )
        return true
    }

    private func restoreMacOS27VisibleControlOrder(items: [MenuBarItem]) async -> Bool {
        let desiredOrder = savedSectionOrder[sectionKey(for: .visible)] ?? []
        guard let plannedMove = RuntimeLayoutCoordinator.visibleControlRestoreMove(
            items: items,
            desiredOrder: desiredOrder,
            experimentalSystemItemHiding: appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        ) else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, macOS 27 visible control order already matches saved layout"
            )
            return false
        }

        // Rate-limit ambient restore *attempts* on the control itself. The
        // destination-scoped `macOS27MoveFailureBackoff` cannot suppress this
        // loop: each pass may plan a different on-bar neighbour and the mirrored
        // saved order keeps shifting, so every retry mints a fresh key. Gating on
        // the last attempt (any destination, any outcome) is what actually caps a
        // placement Thaw cannot win — including a move that lands and is then
        // reverted by MenuBarAgent — at one nudge per window instead of several a
        // second. A restore that succeeds and holds needs no repeat: the next
        // pass finds the order satisfied above and returns early.
        if let lastAttempt = lastVisibleControlRestoreAttempt,
           ContinuousClock.now - lastAttempt < Self.visibleControlRestoreCooldown
        {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping macOS 27 visible control restore; within attempt cooldown"
            )
            return false
        }

        lastVisibleControlRestoreAttempt = .now
        do {
            let fulfilled = try await move(
                item: plannedMove.item,
                to: plannedMove.destination,
                skipInputPause: true,
                watchdogTimeout: Self.layoutWatchdogTimeout,
                allowParkedOffMenuBarSource: true
            )
            guard fulfilled else {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: could not fulfill macOS 27 visible control restore via preferred positions " +
                        "\(plannedMove.item.logString) \(plannedMove.destination.logString)"
                )
                return false
            }
            MenuBarItemManager.diagLog.info(
                "applySavedLayout: restored macOS 27 visible control order for \(plannedMove.item.logString)"
            )
            scheduleDeferredCacheRefresh()
            return true
        } catch {
            MenuBarItemManager.diagLog.error(
                "applySavedLayout: failed macOS 27 visible control restore \(plannedMove.item.logString): \(error)"
            )
            return false
        }
    }

    @MainActor
    func restoreBlockedItemsToVisible() async -> Int {
        // macOS 27: items are composited inside MenuBarAgent and can't be moved
        // off-screen, so none can ever be stuck "blocked" at x=-1. Skip the AX
        // enumeration and move attempts entirely so quitting is instant instead
        // of stalling on this teardown work (and its termination timeout).
        if !MenuBarBackendProvider.current.supportsLegacySectionHiding {
            return 0
        }

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
        ) else {
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
