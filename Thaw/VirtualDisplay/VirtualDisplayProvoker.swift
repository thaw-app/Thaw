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
    /// WindowIDs that a provoke already failed to resolve. Every field case
    /// resolves within a second of the markers publishing or never resolves at
    /// all (retrying the same window produced an identical 0/1 each time), so a
    /// single failed hold means a display will not help this window and we stop
    /// provoking for it. Keyed on windowID, not source PID, because these orphans
    /// have no resolvable source PID; the set is in-memory so a relaunch (which
    /// assigns a fresh windowID) still gets one clean attempt.
    private var blacklisted = Set<CGWindowID>()

    /// How long an orphan must stay unresolved before provoking, so we do not
    /// fire for items the normal AX / marker pass resolves within a cycle.
    private let unresolvedGrace: TimeInterval = 3
    /// Maximum time to keep the virtual display up waiting for resolution. Every
    /// field resolution landed under a second, so this is generous headroom; a
    /// window that has not resolved by here is blacklisted rather than retried.
    private let maxHold: TimeInterval = 4
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
            blacklisted.removeAll()
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
        blacklisted = blacklisted.intersection(orphans)
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
            return !blacklisted.contains(windowID)
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
                let blocked = orphans.sorted().filter { blacklisted.contains($0) }
                diagLog.info(
                    "VirtualDisplayProvoke: not yet eligible (orphan ages \(ages), grace \(unresolvedGrace)s, blacklisted \(blocked))"
                )
            }
            // Re-check at grace expiry so firing does not depend on an incidental
            // cache cycle landing after the grace elapses. Only worth doing while
            // a non-blacklisted orphan is still inside its grace window; once every
            // orphan is blacklisted there is nothing that will become eligible.
            if orphans.contains(where: { !blacklisted.contains($0) }) {
                scheduleRecheckIfNeeded()
            }
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

        let start = Date()
        diagLog.info(
            "VirtualDisplayProvoke: single display with \(targets.count) unresolved orphan(s) \(targets.sorted()); creating virtual display"
        )
        // Capture the real main display before the phantom exists, so it can be
        // re-anchored as main once the phantom is added (see excludeFromMainDisplay).
        let realMain = CGMainDisplayID()
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
            "VirtualDisplayProvoke: created virtual display id=\(display.displayID); realMain=\(realMain), mainAfterCreate=\(CGMainDisplayID()); polling for marker-pair resolution"
        )
        // Keep the phantom from becoming the main display (issue #661). macOS can
        // hand a freshly added display main status a moment after it comes online,
        // so assert it once immediately and again on every poll below rather than
        // trusting a single call to stick.
        enforceRealDisplayMain(realMain: realMain, display: display)

        var resolvedAll = false
        // The set of targets still unresolved at the last in-hold poll. Initialised
        // to all targets so a provoke that somehow never polls counts as a failure.
        var heldUnresolved = targets
        while Date().timeIntervalSince(start) < maxHold {
            try? await Task.sleep(for: pollInterval)
            // Re-assert the real display as main: the phantom can take main status
            // late, after the immediate call above, so this keeps it corrected for
            // the phantom's whole lifetime.
            enforceRealDisplayMain(realMain: realMain, display: display)
            let stillUnresolved = await unresolvedTargets(targets)
            // Remember the last in-hold result: this, taken while the phantom is up
            // and the markers are present, is the authoritative "did the provoke
            // resolve it" signal that the blacklist decision uses.
            heldUnresolved = stillUnresolved
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
                "VirtualDisplayProvoke: gave up after \(String(format: "%.2f", maxHold))s; some orphans still unresolved (blacklisting)"
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

        // Blacklist any target that did not resolve during the hold (while the
        // phantom and its markers were present) so it is not provoked again. A
        // display either makes the markers publish (resolves within ~1s) or it does
        // not, in which case repeating the disruption every few minutes just churns
        // the display arrangement for nothing (issue #661). This uses the in-hold
        // result, not the post-teardown persistence check above: a flapping orphan
        // can momentarily read as resolved at the instant of that check and thereby
        // dodge the blacklist, only to provoke again seconds later, observed as a
        // back-to-back double provoke in the field. A relaunch assigns a fresh
        // windowID, which is not blacklisted, so a genuinely new instance still gets
        // one clean attempt.
        if !heldUnresolved.isEmpty {
            blacklisted.formUnion(heldUnresolved)
            diagLog.info("VirtualDisplayProvoke: blacklisted \(heldUnresolved.sorted()); will not provoke these again")
        }

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

    /// Keeps realMain the system main display while the phantom exists. No-ops
    /// (and stays silent) when the real display is already main, which is the
    /// normal case on machines where the phantom never takes main. When the
    /// phantom has taken main it runs one reanchor transaction and logs the
    /// before/after main display IDs and the transaction return codes, so whether
    /// the phantom ever hijacks main, and whether the correction lands, is
    /// auditable from the field log (issue #661). Returns whether the real display
    /// is main after the call.
    @discardableResult
    private func enforceRealDisplayMain(realMain: CGDirectDisplayID, display: VirtualDisplay) -> Bool {
        let before = CGMainDisplayID()
        guard before != realMain else {
            return true
        }
        let result = display.reanchorRealDisplayAsMain(realMain)
        let after = CGMainDisplayID()
        diagLog.info(
            "VirtualDisplayProvoke: phantom held main (was \(before), realMain \(realMain)); reanchor begin=\(result.beginOK) originReal=\(result.originReal.rawValue) originPhantom=\(result.originPhantom.rawValue) complete=\(result.complete.rawValue) -> main now \(after)"
        )
        return after == realMain
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
