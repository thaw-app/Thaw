//
//  VirtualDisplayProvoker.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation

/// Briefly creates a virtual display when, on a single physical display, menu
/// bar items remain unresolved (nil sourcePID), so the window server publishes
/// the bundle-ID marker windows that marker-pair resolution needs. Once the
/// orphans resolve, their windowID -> PID mappings persist in the cache (and
/// the elimination sticky map), so the display only has to be present long
/// enough to resolve once, then it is torn down.
///
/// Extensive timing is logged so the settle latency (display created -> markers
/// published -> orphans resolved) can be measured from the field.
@MainActor
final class VirtualDisplayProvoker {
    private let diagLog = DiagLog(category: "VirtualDisplayProvoke")
    private weak var appState: AppState?

    private var display: VirtualDisplay?
    private var isProvoking = false
    /// Whether the one-time support log has been emitted.
    private var hasLoggedSupport = false
    /// Rate-limits the per-call decision trace.
    private var lastDecisionLog = Date.distantPast
    /// Whether a grace-expiry re-check is already scheduled.
    private var recheckScheduled = false

    /// While a provoke runs and for a short window after teardown, creating
    /// and removing the virtual display each post a
    /// didChangeScreenParametersNotification. Those fire even though the phantom
    /// is excluded from display enumeration, and subscribers debounce them
    /// (DisplaySettingsManager coalesces for 1s), so they land after teardown
    /// when excludedDisplayID is already nil. Display-change subscribers read
    /// this to ignore the self-inflicted churn instead of reacting to it: a
    /// screen-parameters reaction was observed cancelling the in-flight item
    /// cache cycle mid-resolution, surfacing a whole bar of orphans for several
    /// seconds until the next recache. The window extends past teardown so the
    /// debounced notifications are still covered when they arrive.
    @MainActor static var displayReactionsSuppressedUntil: Date?

    /// When each currently-unresolved orphan windowID was first observed.
    private var firstSeenUnresolved = [CGWindowID: Date]()
    /// Last provoke attempt per windowID, for the cooldown.
    private var lastAttempt = [CGWindowID: Date]()

    /// How long an orphan must stay unresolved before provoking, so we do not
    /// fire for items the normal AX / marker pass resolves within a cycle.
    private let unresolvedGrace: TimeInterval = 3
    /// Minimum time between provoke attempts for the same windowID, so an
    /// orphan that cannot resolve even with a display does not flicker-loop.
    private let attemptCooldown: TimeInterval = 300
    /// Maximum time to keep the virtual display up waiting for resolution.
    private let maxHold: TimeInterval = 12
    /// Poll cadence while waiting for markers to publish and orphans to resolve.
    private let pollInterval: Duration = .milliseconds(250)

    init(appState: AppState) {
        self.appState = appState
        startPeriodicEvaluation()
    }

    /// Re-evaluates on a steady cadence so a stuck orphan is provoked even when
    /// menu bar item-cache changes (the other trigger) are sparse once the bar
    /// is idle. considerProvoking is cheap and early-returns unless a single
    /// display has an unresolved orphan, so a short interval is inexpensive.
    private func startPeriodicEvaluation() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else {
                    return
                }
                self.considerProvoking()
            }
        }
    }

    /// Re-evaluates whether to run a provoke cycle. Cheap and safe to call
    /// after every cache cycle; it pulls the current orphan set and display
    /// count itself and no-ops unless the conditions hold.
    func considerProvoking() {
        // Log support state once so an absent CGVirtualDisplay (which otherwise
        // makes this method return silently) is visible in the field log.
        if !hasLoggedSupport {
            hasLoggedSupport = true
            diagLog.info("VirtualDisplayProvoke: CGVirtualDisplay supported=\(VirtualDisplay.isSupported)")
        }

        guard !isProvoking, VirtualDisplay.isSupported, let appState else {
            return
        }

        let displayCount = NSScreen.managedScreens.count
        let orphans = appState.itemManager.unresolvedOrphanWindowIDs()
        let settling = appState.itemManager.isSettling
        let now = Date()
        let shouldLogDecision = now.timeIntervalSince(lastDecisionLog) >= 5

        // Only single-display machines lack the marker windows. Multi-display
        // (physical or virtual) already publishes them. managedScreens excludes
        // any virtual display we created.
        guard displayCount == 1, !orphans.isEmpty else {
            firstSeenUnresolved.removeAll()
            lastAttempt.removeAll()
            return
        }

        // Wait out settling (cold boot, profile apply): items are transiently
        // unresolved then; only once it ends has the normal pipeline (spatial
        // AX, marker-pair, elimination) had its chance, so a still-unresolved
        // item is genuinely stuck. Clearing firstSeenUnresolved here measures
        // the grace from after settling, never from cold-boot churn.
        guard !settling else {
            firstSeenUnresolved.removeAll()
            if shouldLogDecision {
                lastDecisionLog = now
                diagLog.info("VirtualDisplayProvoke: deferring while settling (orphans \(orphans.sorted()))")
            }
            return
        }

        // Forget state for windowIDs that are no longer orphaned.
        firstSeenUnresolved = firstSeenUnresolved.filter { orphans.contains($0.key) }
        lastAttempt = lastAttempt.filter { orphans.contains($0.key) }
        for windowID in orphans where firstSeenUnresolved[windowID] == nil {
            firstSeenUnresolved[windowID] = now
        }

        let eligible = orphans.filter { windowID in
            guard
                let firstSeen = firstSeenUnresolved[windowID],
                now.timeIntervalSince(firstSeen) >= unresolvedGrace
            else {
                return false
            }
            if let attempted = lastAttempt[windowID], now.timeIntervalSince(attempted) < attemptCooldown {
                return false
            }
            return true
        }

        guard !eligible.isEmpty else {
            // Diagnostic: a single-display orphan that is not (yet) provoked.
            // Shows why so a non-firing case is explainable from the field log.
            if shouldLogDecision {
                lastDecisionLog = now
                let ages = orphans.sorted().map { windowID in
                    let age = firstSeenUnresolved[windowID].map { now.timeIntervalSince($0) } ?? 0
                    return "\(windowID):\(String(format: "%.1f", age))s"
                }
                let cooled = orphans.sorted().filter { windowID in
                    lastAttempt[windowID].map { now.timeIntervalSince($0) < attemptCooldown } ?? false
                }
                diagLog.info(
                    "VirtualDisplayProvoke: not yet eligible (orphan ages \(ages), grace \(unresolvedGrace)s, cooldown-blocked \(cooled))"
                )
            }
            // Re-check at grace expiry so firing does not depend on an incidental
            // cache cycle landing after the grace elapses.
            scheduleRecheckIfNeeded()
            return
        }

        // Claim the in-flight slot synchronously so a concurrent call cannot
        // spawn a second provoke before the task starts.
        isProvoking = true
        let targets = Set(eligible)
        lastDecisionLog = now
        diagLog.info("VirtualDisplayProvoke: eligible \(targets.sorted()); starting provoke")
        Task { await runProvoke(targets: targets) }
    }

    /// Schedules a single re-evaluation after the grace period so a stuck
    /// orphan provokes even when no further cache cycle happens to occur.
    private func scheduleRecheckIfNeeded() {
        guard !recheckScheduled else {
            return
        }
        recheckScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard let self else {
                return
            }
            self.recheckScheduled = false
            self.considerProvoking()
        }
    }

    private func runProvoke(targets: Set<CGWindowID>) async {
        defer { isProvoking = false }
        guard let appState else {
            return
        }

        let attemptTime = Date()
        for windowID in targets {
            lastAttempt[windowID] = attemptTime
        }

        let start = Date()
        diagLog.info(
            "VirtualDisplayProvoke: single display with \(targets.count) unresolved orphan(s) \(targets.sorted()); creating virtual display"
        )
        guard let display = VirtualDisplay.create() else {
            // Report which private classes resolved so a binding failure on a
            // given macOS version is diagnosable from Thaw's own log (the ObjC
            // shim's detail goes to the system log, which the tester may not
            // capture).
            diagLog.error(
                "VirtualDisplayProvoke: CGVirtualDisplay creation failed; cannot provoke. Classes present: "
                    + "descriptor=\(NSClassFromString("CGVirtualDisplayDescriptor") != nil), "
                    + "display=\(NSClassFromString("CGVirtualDisplay") != nil), "
                    + "mode=\(NSClassFromString("CGVirtualDisplayMode") != nil), "
                    + "settings=\(NSClassFromString("CGVirtualDisplaySettings") != nil)"
            )
            return
        }
        self.display = display
        // Exclude our phantom from Thaw's display enumeration so it never
        // pollutes per-display state (the Displays settings panel, overlay
        // panels, profile auto-switch, etc.) while it briefly exists. The
        // marker windows it makes the window server publish are unaffected.
        Bridging.excludedDisplayID = display.displayID
        // Suppress display-change reactions for the lifetime of the phantom so
        // its creation notification is ignored; converted to a bounded grace at
        // teardown to also cover the debounced removal notification.
        Self.displayReactionsSuppressedUntil = .distantFuture
        diagLog.info(
            "VirtualDisplayProvoke: created virtual display id=\(display.displayID); polling for marker-pair resolution"
        )

        var resolvedAll = false
        while Date().timeIntervalSince(start) < maxHold {
            try? await Task.sleep(for: pollInterval)
            let stillUnresolved = await unresolvedTargets(targets)
            let elapsed = Date().timeIntervalSince(start)
            diagLog.info(
                "VirtualDisplayProvoke: +\(String(format: "%.2f", elapsed))s \(targets.count - stillUnresolved.count)/\(targets.count) target orphan(s) resolved"
            )
            if stillUnresolved.isEmpty {
                resolvedAll = true
                diagLog.info(
                    "VirtualDisplayProvoke: all targets resolved \(String(format: "%.2f", elapsed))s after display creation"
                )
                break
            }
        }
        if !resolvedAll {
            diagLog.info(
                "VirtualDisplayProvoke: gave up after \(String(format: "%.2f", maxHold))s; some orphans still unresolved (retry after cooldown)"
            )
        }

        Bridging.excludedDisplayID = nil
        display.invalidate()
        self.display = nil
        // Keep suppressing past teardown so the removal's debounced
        // (and any coalesced creation) screen-parameters notification, which
        // arrives about a second later, is still ignored.
        Self.displayReactionsSuppressedUntil = Date().addingTimeInterval(2.0)
        diagLog.info(
            "VirtualDisplayProvoke: removed virtual display \(String(format: "%.2f", Date().timeIntervalSince(start)))s after creation"
        )

        // Persistence check: the one-shot only works if the resolved windowID
        // -> PID mappings survive the display being removed. Read fresh (which
        // returns the XPC's cached PIDs now that the marker is gone) and report
        // how many targets are still resolved.
        let stillUnresolved = await unresolvedTargets(targets)
        diagLog.info(
            "VirtualDisplayProvoke: after teardown \(targets.count - stillUnresolved.count)/\(targets.count) target(s) still resolved (persistence check)"
        )

        // Propagate the freshly resolved sourcePIDs into the manager's
        // published item cache. The provoke only updates the XPC's PID cache;
        // without this the cached items keep their pre-provoke nil sourcePID
        // (the icon stays labelled com.apple.controlcenter:Item-0, and any
        // layout pass in the meantime treats it as an orphan) until an
        // unrelated event happens to trigger the next full cache cycle. The
        // phantom is gone and its screen-parameters notifications are
        // suppressed, so this refresh runs cleanly, no cancellation, no orphan
        // flash. Skipped when nothing resolved, since the cache is already
        // up to date in that case.
        if stillUnresolved.count < targets.count {
            await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    /// Returns which of the given target windowIDs are still unresolved, read
    /// from a fresh getMenuBarItems. This both drives the XPC scan (so marker-
    /// pair resolution runs while the marker window is present) and reads the
    /// authoritative result, rather than the cached itemCache whose refresh can
    /// be dropped by the in-flight cache gate during the rapid provoke poll.
    private func unresolvedTargets(_ targets: Set<CGWindowID>) async -> Set<CGWindowID> {
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        return targets.filter { windowID in
            items.contains { $0.windowID == windowID && $0.sourcePID == nil }
        }
    }
}
