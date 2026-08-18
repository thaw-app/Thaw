//
//  SourcePIDCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import Combine
import os

/// A cache for the source process identifiers for menu bar item windows.
///
/// We use the term "source process" to refer to the process that created
/// a menu bar item. Originally, we used the CGWindowList API to get the
/// window's owning process (`kCGWindowOwnerPID`), which was always the
/// source process. However, as of macOS 26, item windows are owned by
/// the Control Center.
///
/// We can find what we need using the Accessibility API, but doing it
/// efficiently ends up being a fairly complex process. Since calls to
/// Accessibility are thread blocking, we do most of the heavy lifting
/// in a dedicated XPC service, which we then call asynchronously from
/// the main app.
///
/// This type is an `actor`. Only the Combine observer wiring in
/// `start()` (and its backing `cancellable` lazy var) is actually
/// actor-isolated — that state had no synchronization of its own
/// before this conversion. Everything else (`state`, `scanLock`, and
/// the `CachedApplication` cache entries) was already protected by its
/// own `OSAllocatedUnfairLock`, so those members and the methods that
/// only touch them are marked `nonisolated`. This preserves the exact
/// pre-actor concurrency semantics: cache-hit reads in `pidBody` can
/// still proceed without waiting on an in-flight full AX scan, and
/// `scanLock` (not actor isolation) is still what serializes full
/// scans across concurrent callers. Making these methods actor-isolated
/// instead would have serialized *all* calls — including fast
/// cache-hit checks — behind any long-running blocking AX scan, which
/// would have been a behavior change, not just a safety upgrade.
actor SourcePIDCache {
    private static let diagLog = DiagLog(category: "SourcePIDCache")
    /// An object that contains a running application and provides an
    /// interface to access relevant information, such as its process
    /// identifier and extras menu bar.
    private final class CachedApplication: @unchecked Sendable {
        private let runningApp: NSRunningApplication

        private struct State {
            var extrasMenuBar: UIElement?

            /// Consecutive checks that found no extras menu bar. Drives the
            /// TTL ladder in ``ExtrasMenuBarNegativeCachePolicy``.
            var consecutiveMisses = 0

            /// The instant after which a missing extras menu bar may be
            /// probed again, or `nil` when this app has never come back
            /// empty. Only meaningful while `extrasMenuBar` is `nil`.
            var retryAfter: ContinuousClock.Instant?
        }

        private let lock = OSAllocatedUnfairLock(initialState: State())

        /// The app's process identifier.
        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        /// The app's bundle identifier, if any. Used by diagnostic
        /// logging to identify which app's AX extras a frame came from.
        var bundleIdentifier: String? {
            runningApp.bundleIdentifier
        }

        /// A localized, human-readable name for the app. Used by
        /// diagnostic logging when the bundle identifier is absent.
        var localizedName: String? {
            runningApp.localizedName
        }

        /// A Boolean value indicating whether the app's extras menu
        /// bar has been successfully created and stored.
        var hasExtrasMenuBar: Bool {
            lock.withLock { $0.extrasMenuBar != nil }
        }

        /// Whether an unexpired negative deadline would make
        /// ``getOrCreateExtrasMenuBar()`` skip its accessibility calls.
        ///
        /// Diagnostics only, and sampled outside the lock that
        /// ``getOrCreateExtrasMenuBar()`` takes, so it is a count rather
        /// than a guarantee. It exists because a field log that reports
        /// only "checked N apps" cannot distinguish a scan that probed the
        /// whole system from one the negative cache spared.
        var isSkippingExtrasMenuBarProbe: Bool {
            lock.withLock { state in
                guard state.extrasMenuBar == nil, let retryAfter = state.retryAfter else {
                    return false
                }
                return retryAfter > ContinuousClock.now
            }
        }

        /// A Boolean value indicating whether the app is in a valid
        /// state for making accessibility calls.
        private var isValidForAccessibility: Bool {
            // These checks help prevent blocking that can occur when
            // calling AX APIs while the app is an invalid state.
            runningApp.isFinishedLaunching &&
                !runningApp.isTerminated &&
                !Bridging.isProcessUnresponsive(processIdentifier)
        }

        /// Creates a `CachedApplication` instance with the given running
        /// application.
        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }

        /// Returns the accessibility element representing the app's extras
        /// menu bar, creating it if necessary.
        ///
        /// When the element is first created, it gets stored for efficient
        /// access on subsequent calls.
        func getOrCreateExtrasMenuBar() -> UIElement? {
            // Fast path: check cached state under the lock first.
            let now = ContinuousClock.now
            let (hasCached, isBarred) = lock.withLock { state -> (UIElement?, Bool) in
                guard state.extrasMenuBar == nil else {
                    return (state.extrasMenuBar, false)
                }
                guard let retryAfter = state.retryAfter else {
                    return (nil, false)
                }
                return (nil, retryAfter > now)
            }
            if let bar = hasCached {
                return bar
            }
            if isBarred {
                return nil
            }

            guard isValidForAccessibility else {
                // Transient condition (still launching, unresponsive, or
                // terminated). Do NOT set negative cache — retry next scan.
                return nil
            }

            // Slow path: AX API calls performed outside the lock to
            // avoid holding it during blocking IPC.
            guard
                let app = AXHelpers.application(for: runningApp),
                let bar = AXHelpers.extrasMenuBar(for: app)
            else {
                // App is reachable but has no extras menu bar. Bar it from
                // the next scans rather than flagging it permanently: it may
                // still register a status item later, so the deadline grows
                // with each empty check instead of never expiring.
                lock.withLock {
                    if $0.extrasMenuBar == nil {
                        $0.consecutiveMisses += 1
                        $0.retryAfter = ContinuousClock.now + ExtrasMenuBarNegativeCachePolicy.ttl(
                            afterConsecutiveMisses: $0.consecutiveMisses
                        )
                    }
                }
                return nil
            }
            lock.withLock {
                $0.extrasMenuBar = bar
                $0.consecutiveMisses = 0
                $0.retryAfter = nil
            }
            return bar
        }
    }

    /// State for the cache.
    private struct State {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        /// Window IDs a full scan failed to resolve, mapped to the deadline
        /// after which they may initiate a new scan. A negative entry gates
        /// scan initiation only: a scan started for another window still
        /// retries every unresolved window, so late-arriving markers are
        /// discovered immediately.
        var negativeUntil = [CGWindowID: ContinuousClock.Instant]()

        /// Consecutive full scans that have left each window unresolved.
        /// Drives the negative-cache TTL ladder: early failures get short
        /// deadlines so the app's startup settling window can retry while
        /// AX trees are still warming up, repeat failures back off to the
        /// steady-state TTL. Reset when a window resolves; pruned alongside
        /// `negativeUntil` so it stays bounded.
        var negativeFailures = [CGWindowID: Int]()

        /// Reorders the cached apps so that those that are confirmed
        /// to have an extras menu bar are first in the array.
        mutating func partitionApps() {
            var lhs = [CachedApplication]()
            var rhs = [CachedApplication]()

            for app in apps {
                if app.hasExtrasMenuBar {
                    lhs.append(app)
                } else {
                    rhs.append(app)
                }
            }

            apps = lhs + rhs
        }
    }

    /// The shared cache.
    static let shared = SourcePIDCache()

    // The per-failure negative-cache deadline lives in
    // SourcePIDNegativeCachePolicy (Shared/), so the ladder is unit-testable
    // from ThawTests.

    /// How long a single app's extras-bar probe may take before the scan
    /// names it in the log.
    ///
    /// Low enough that a handful of slow apps stand out inside a scan that
    /// takes a few hundred milliseconds in total, high enough that a healthy
    /// scan says nothing at all.
    private static let slowProbeThreshold: Duration = .milliseconds(50)

    /// Minimum interval between unresolved-diagnostic dumps for an unchanged
    /// unresolved set. The dump re-walks every app's AX tree, so repeating it
    /// can add seconds of IPC without yielding new information.
    private static let unresolvedDiagDumpInterval: Duration = .seconds(300)

    /// Rate-limits unresolved diagnostic dumps. Kept in its own lock because
    /// `pidBody` (which emits diagnostics under `scanLock`) is `nonisolated`
    /// and cannot touch actor-isolated storage. Concurrent access is still
    /// serialized in practice by `scanLock` around the dump site.
    private nonisolated let lastUnresolvedDiagDump = OSAllocatedUnfairLock<
        (windowIDs: Set<CGWindowID>, at: ContinuousClock.Instant)?
    >(initialState: nil)

    /// The cache's protected state.
    ///
    /// `nonisolated`: this is already synchronized by its own
    /// `OSAllocatedUnfairLock` and does not need actor isolation on
    /// top of that. Keeping it `nonisolated` lets fast cache-hit reads
    /// run without waiting for the actor even while `start()`/cleanup
    /// (which remain actor-isolated) are in flight.
    private nonisolated let state = OSAllocatedUnfairLock(initialState: State())

    /// Lock to prevent multiple concurrent full scans of all applications.
    ///
    /// `nonisolated` for the same reason as `state` above — it is the
    /// mechanism (not actor isolation) that serializes full AX scans.
    private nonisolated let scanLock = OSAllocatedUnfairLock(initialState: ())

    /// Observer for running applications.
    private lazy var cancellable: AnyCancellable = {
        let runningAppsPublisher = NSWorkspace.shared.publisher(for: \.runningApplications)
            .map { _ in () }

        let timerPublisher = Timer.publish(every: 300, on: .main, in: .default)
            .autoconnect()
            .map { _ in () }

        return Publishers.Merge(runningAppsPublisher, timerPublisher)
            .sink { [weak self] in
                self?.performCleanup()
            }
    }()

    /// Creates the shared cache.
    private init() {
        Bridging.setProcessUnresponsiveTimeout(3)
    }

    /// Performs cleanup of the cache state.
    private nonisolated func performCleanup() {
        autoreleasepool {
            performCleanupBody()
        }
    }

    private nonisolated func performCleanupBody() {
        let runningApps = NSWorkspace.shared.runningApplications
        SourcePIDCache.diagLog.debug("Performing PID cache cleanup")

        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let currentAppPids = Set(runningApps.map(\.processIdentifier))

        state.withLock { state in
            // Clean up entries for terminated apps to prevent memory leaks
            let oldAppPids = Set(state.apps.map(\.processIdentifier))
            let terminatedPids = oldAppPids.subtracting(currentAppPids)

            // Remove PID mappings for terminated apps
            for terminatedPid in terminatedPids {
                state.pids = state.pids.filter { $0.value != terminatedPid }
            }

            // Convert the cached state to dictionaries keyed by pid to
            // allow for efficient repeated access.
            let appMappings = state.apps.reduce(into: [:]) { result, app in
                result[app.processIdentifier] = app
            }
            let pidMappings: [pid_t: [CGWindowID: pid_t]] = windowIDs.reduce(into: [:]) { result, windowID in
                if let pid = state.pids[windowID] {
                    result[pid, default: [:]][windowID] = pid
                }
            }

            // Preserve unexpired negative entries across cleanup. Dropping
            // them would let a known-unresolvable window start a full scan
            // immediately after every application-list update.
            let now = ContinuousClock.now
            let carriedNegativeUntil = state.negativeUntil.filter { $0.value > now }
            let carriedNegativeFailures = state.negativeFailures

            // Create a new state that matches the current running apps.
            state = runningApps.reduce(into: State()) { result, app in
                let pid = app.processIdentifier

                if let app = appMappings[pid] {
                    // Prefer the cached app, as it may have already done
                    // the work to initialize its extras menu bar. Its
                    // extras-bar negative deadline rides along: it expires on
                    // its own schedule, so a status item registered after
                    // launch is still discovered without re-probing every
                    // app on the system each time this list changes.
                    result.apps.append(app)
                } else {
                    // App wasn't in the cache, so it must be new.
                    result.apps.append(CachedApplication(app))
                }

                if let pids = pidMappings[pid] {
                    for (windowID, pid) in pids {
                        result.pids[windowID] = pid
                    }
                }
            }
            // Carry negative state only for windows that are still unresolved.
            // A scan driven by any one window resolves every window it can, so
            // a previously negative-cached window may now hold a PID; keeping
            // its failure count would start its next miss partway up the
            // ladder instead of at the first rung.
            state.negativeUntil = carriedNegativeUntil.filter { state.pids[$0.key] == nil }
            state.negativeFailures = carriedNegativeFailures.filter {
                state.negativeUntil[$0.key] != nil
            }

            // Log cleanup activity
            if !terminatedPids.isEmpty {
                SourcePIDCache.diagLog.info("Cleaned up PID cache entries for terminated processes: \(terminatedPids)")
            }
        }
    }

    /// Starts the observers for the cache.
    func start() {
        SourcePIDCache.diagLog.debug("Starting observers for source PID cache")
        _ = cancellable
    }

    /// Returns the cached process identifiers for the given windows,
    /// performing a single batch resolution if any are missing.
    ///
    /// `pidBody` already caches **all** matched windows during its full
    /// AX scan, so after one call all resolvable PIDs are available.
    ///
    /// The entire request is wrapped in an autoreleasepool. This XPC
    /// service has no NSApplication, so autoreleased ObjC/CF objects from
    /// WindowInfo creation, AX API calls, and CGS bridging would otherwise
    /// accumulate on the GCD thread until process exit.
    nonisolated func pids(for windows: [WindowInfo]) -> [pid_t?] {
        autoreleasepool {
            pidsBody(for: windows)
        }
    }

    private nonisolated func pidsBody(for windows: [WindowInfo]) -> [pid_t?] {
        // Drive the scan via an unresolved window in the batch, not via
        // `windows.first`. pidBody returns early on a cache hit (line 292),
        // so passing a cached window skips the AX traversal entirely.
        // Once macOS 26 began routing some widgets through the marker-pair
        // fallback that lives in pidBody's scan body, mid-session arrivals
        // (new app launches that introduce a fresh nil-PID windowID) were
        // never getting a scan: the first window in their batch was always
        // an already-cached resolved one, and the scan only ever ran at
        // session start.
        let now = ContinuousClock.now
        if let unresolved = windows.first(where: { needsScan($0, asOf: now) }) {
            _ = pidBody(for: unresolved)
        }
        return windows.map { window in
            state.withLock { $0.pids[window.windowID] }
        }
    }

    /// Whether `window` still needs the full AX traversal: it has area to
    /// match on, no PID has been cached for it, and any negative-cache entry
    /// has expired by `now`.
    ///
    /// Split out of `pidsBody` so the search predicate, the lock, and the
    /// deadline comparison are not three closures deep.
    private nonisolated func needsScan(_ window: WindowInfo, asOf now: ContinuousClock.Instant) -> Bool {
        // A window with no area cannot be matched to an accessibility
        // element, so it must not start a scan on its own behalf: allowed to,
        // it wakes a full traversal of every running app once per
        // negative-cache TTL for the life of the session and never resolves.
        // It is still resolved by a scan another window starts, and bounds
        // are re-read on every request, so one that gains area later stops
        // being skipped.
        guard !window.isDegenerate else {
            return false
        }
        return state.withLock { state in
            guard state.pids[window.windowID] == nil else {
                return false
            }
            guard let negativeUntil = state.negativeUntil[window.windowID] else {
                return true
            }
            return negativeUntil <= now
        }
    }

    private nonisolated func pidBody(for window: WindowInfo) -> pid_t? {
        if let pid = state.withLock({ $0.pids[window.windowID] }) {
            SourcePIDCache.diagLog.debug("SourcePIDCache.pid: cache hit for windowID \(window.windowID) -> PID \(pid)")
            return pid
        }

        if let deadline = state.withLock({ $0.negativeUntil[window.windowID] }),
           deadline > ContinuousClock.now
        {
            SourcePIDCache.diagLog.debug("SourcePIDCache.pid: negative cache hit for windowID \(window.windowID), skipping scan")
            return nil
        }

        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: cache miss for windowID \(window.windowID) title=\(window.title ?? "nil"), acquiring scan lock")

        // Use a lock to ensure that only one thread performs the full AX traversal.
        // This is critical when resolving many windows (e.g. 64) concurrently.
        scanLock.lock()
        defer { scanLock.unlock() }

        // Re-check cache after acquiring the scan lock, as it may have been populated
        // or negative-cached by another thread that just finished a full scan.
        if let pid = state.withLock({ $0.pids[window.windowID] }) {
            SourcePIDCache.diagLog.debug("SourcePIDCache.pid: cache hit after scan lock for windowID \(window.windowID) -> PID \(pid)")
            return pid
        }
        if let deadline = state.withLock({ $0.negativeUntil[window.windowID] }),
           deadline > ContinuousClock.now
        {
            SourcePIDCache.diagLog.debug("SourcePIDCache.pid: negative cache hit after scan lock for windowID \(window.windowID), skipping scan")
            return nil
        }

        let isTrusted = AXHelpers.isProcessTrusted()
        guard isTrusted else {
            SourcePIDCache.diagLog.warning("SourcePIDCache.pid: AXHelpers.isProcessTrusted() returned false — accessibility permission missing in XPC service")
            return nil
        }

        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: performing batch resolution via AX API")
        let scanStart = ContinuousClock.now

        // Fetch all current menu bar item windows to perform a single batch resolution.
        // This avoids doing the O(W*A*C) work (Windows * Apps * Children) for every request.
        let allWindows = WindowInfo.createMenuBarWindows(option: .itemsOnly)
        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: batch resolving for \(allWindows.count) windows")

        // Get a copy of the apps list to iterate over without holding the state lock.
        let apps = state.withLock { state -> [CachedApplication] in
            state.partitionApps()
            return state.apps
        }

        let ccBundleID = "com.apple.controlcenter"
        let thawBundleID = "com.stonerl.Thaw"
        var appsChecked = 0
        var appsWithBar = 0
        var appsSkipped = 0
        var totalChildrenChecked = 0
        var totalMatchesFound = 0
        var unresolvedWindows = Set(allWindows.map(\.windowID))

        for app in apps {
            if unresolvedWindows.isEmpty {
                break
            }
            appsChecked += 1
            if app.isSkippingExtrasMenuBarProbe {
                appsSkipped += 1
            }
            autoreleasepool {
                // Accessibility reads are serviced by the *target* process,
                // normally on its main thread, and are bounded only by the
                // unresponsive timeout set in `init`. One busy app can
                // therefore account for most of a scan's wall time. Naming
                // the slow ones is what separates "the app list is too long"
                // from "two apps are wedged" — the first calls for a
                // narrower scan, the second for a shorter timeout, and a
                // total alone cannot tell them apart.
                let probeStart = ContinuousClock.now
                let bar = app.getOrCreateExtrasMenuBar()
                let probeDuration = ContinuousClock.now - probeStart
                if probeDuration >= SourcePIDCache.slowProbeThreshold {
                    let label = app.bundleIdentifier ?? app.localizedName ?? "pid \(app.processIdentifier)"
                    SourcePIDCache.diagLog.debug(
                        "SourcePIDCache.pid: slow extras-bar probe: \(label) took \(probeDuration)"
                    )
                }

                guard let bar else {
                    return
                }
                appsWithBar += 1
                // Thaw's own children are never skipped for being disabled.
                // A collapsed section divider is deliberately disabled
                // (ControlItem sets isEnabled = false in .hideSection so the
                // spacer stays inert), which is its normal steady state — so
                // skipping it here leaves Thaw unable to resolve its own
                // control items for as long as the section stays collapsed.
                // That kills both ControlItemPair fallbacks that key off
                // sourcePID: the tag+PID match, and the AX-frame correlation,
                // whose candidate predicate requires sourcePID == ourPID.
                // Thaw then cannot identify its own dividers even with an
                // exact positional match available (#899, and the
                // "strategies 1 through 3 never fired" report in #895).
                let isOwnApp = app.bundleIdentifier == thawBundleID
                let children = AXHelpers.children(for: bar)
                for child in children {
                    totalChildrenChecked += 1
                    // Skip only children the app marks explicitly disabled. A
                    // missing AXEnabled attribute (nil) is treated as enabled:
                    // some status items hosted by Control Center (The Clock's
                    // among them) never publish AXEnabled, and treating absent as
                    // disabled would drop an otherwise exact positional match and
                    // leave the item unresolved.
                    guard isOwnApp || AXHelpers.enabledAttribute(child) != false,
                          let childFrame = AXHelpers.frame(for: child)
                    else {
                        continue
                    }

                    let childCenter = childFrame.center

                    // Match this child to ANY window in our list, but skip
                    // Control-Center-hosted generic slots. Control Center is the
                    // CG owner for every CC-hosted NSStatusItem. When the matched
                    // app is Control Center and the window title is a generic
                    // Item-N slot, the spatial match only confirms the window is
                    // CC-hosted; it does not identify the owning app. Writing
                    // Control Center's PID would tag the item as a transient CC
                    // widget (isTransientControlCenterItem true, canBeHidden
                    // false), hiding it from profile management. Leaving it
                    // unresolved lets the marker-pair pass below supply the real
                    // owner PID; named CC items (BentoBox-0, Clock, WiFi,
                    // NowPlaying) carry non-generic titles and resolve to Control
                    // Center normally.
                    //
                    // On a single display the marker windows may never publish,
                    // in which case the item stays unresolved for the session.
                    // Accepted: a permanent mislabel is worse than no owner.
                    if let matchedWindow = allWindows.first(where: {
                        $0.bounds.center.distance(to: childCenter) <= 1
                    }), !MarkerPairResolver.isCCHostedGenericSlot(
                        appBundleID: app.bundleIdentifier,
                        windowTitle: matchedWindow.title,
                        ccBundleID: ccBundleID
                    ) {
                        totalMatchesFound += 1
                        unresolvedWindows.remove(matchedWindow.windowID)
                        let pid = app.processIdentifier
                        state.withLock { $0.pids[matchedWindow.windowID] = pid }
                    }
                }
            }
        }

        // Corroborated spatial fallback for Control-Center-hosted items
        // whose own app DOES publish an extras-bar AX child, but offset from
        // the CG window center by more than the strict 1pt pass tolerates.
        // The hosting CG slot is wider than the real icon, so their centers
        // diverge: AirBuddy's by ~2pt, SpamSieve's by up to ~8pt. Accept the
        // nearest such child within a generous radius ONLY when the window's
        // reverse-DNS title is in an owner relationship with the app's bundle
        // identifier (HostedItemOwnership). The title corroboration, not the
        // distance, is what makes this safe: a nearby unrelated neighbor
        // (WireGuard's slot beside Updatest at ~2pt) fails the owner check and
        // is left for later passes. Runs BEFORE marker-pair so items that have
        // their own AX child are claimed here and never reach that fallback.
        // Empirically the furthest correct owner-corroborated match across
        // captured logs is ~15pt; 20 leaves margin while staying well inside
        // a neighbor's slot. The owner check is the real guard.
        // Exact-title PID resolution.
        //
        // Runs BEFORE the hosted-extras pass because it is the strongest
        // signal available: a window whose title is the complete bundle
        // identifier of a running application is naming its owner outright.
        // The pass below finds the same app by title but then requires
        // spatial confirmation against the app's AX children — and an item
        // hosted by Control Center publishes no AXExtrasMenuBar of its own,
        // which is why it is unresolved in the first place. The confirmation
        // can never arrive, so those items fell through every pass (#854:
        // com.microsoft.OneDrive, com.apple.TextInputMenuAgent, us.zoom.xos
        // and seven more, all with a nil source PID in one log).
        //
        // Thaw and Control Center are excluded: attributing a widget to
        // either is the misattribution every other pass is careful to avoid.
        let attributableBundleIDs = apps.compactMap { app -> String? in
            guard let bundleID = app.bundleIdentifier,
                  bundleID != thawBundleID,
                  bundleID != ccBundleID
            else {
                return nil
            }
            return bundleID
        }
        if !unresolvedWindows.isEmpty, !attributableBundleIDs.isEmpty {
            let pidsByBundleID = Dictionary(
                apps.compactMap { app -> (String, pid_t)? in
                    guard let bundleID = app.bundleIdentifier else { return nil }
                    return (bundleID, app.processIdentifier)
                },
                uniquingKeysWith: { first, _ in first }
            )
            for window in allWindows where unresolvedWindows.contains(window.windowID) {
                guard
                    let bundleID = HostedItemOwnership.exactlyNamedOwner(
                        window.title,
                        runningBundleIDs: attributableBundleIDs
                    ),
                    let pid = pidsByBundleID[bundleID]
                else {
                    continue
                }
                totalMatchesFound += 1
                unresolvedWindows.remove(window.windowID)
                state.withLock { $0.pids[window.windowID] = pid }
                SourcePIDCache.diagLog.info(
                    "SourcePIDCache exact-title resolution: windowID=\(window.windowID) → PID \(pid) via title=\(bundleID)"
                )
            }
        }

        let hostedExtrasMatchRadius: CGFloat = 20
        for app in apps {
            if unresolvedWindows.isEmpty {
                break
            }
            guard let appBundleID = app.bundleIdentifier else { continue }
            let candidateWindows = allWindows.filter {
                unresolvedWindows.contains($0.windowID)
                    && HostedItemOwnership.titleIndicatesOwner($0.title, bundleID: appBundleID)
            }
            guard !candidateWindows.isEmpty else { continue }
            autoreleasepool {
                guard let bar = app.getOrCreateExtrasMenuBar() else { return }
                let childCenters = AXHelpers.children(for: bar).compactMap { child -> CGPoint? in
                    guard AXHelpers.enabledAttribute(child) != false,
                          let frame = AXHelpers.frame(for: child)
                    else {
                        return nil
                    }
                    return frame.center
                }
                guard !childCenters.isEmpty else { return }
                for window in candidateWindows {
                    let target = window.bounds.center
                    let nearest = childCenters.lazy.map { $0.distance(to: target) }.min()
                        ?? .greatestFiniteMagnitude
                    guard nearest <= hostedExtrasMatchRadius else { continue }
                    totalMatchesFound += 1
                    unresolvedWindows.remove(window.windowID)
                    state.withLock { $0.pids[window.windowID] = app.processIdentifier }
                }
            }
        }

        // Marker-pair PID resolution.
        //
        // On macOS 26 some widgets (Little Snitch's agent observed in
        // the wild) have their NSStatusItem hosted by Control Center
        // at the AX layer and do not publish an AXExtrasMenuBar of
        // their own. The spatial CG-to-AX pass above cannot find a
        // per-app extras child for them, so the icon stays unresolved
        // and the namespace falls back to com.apple.controlcenter.
        //
        // Structurally, every NSStatusItem-style widget also publishes
        // a SECOND CG window in the items-only list whose title is
        // the widget's bundle identifier (verified empirically for
        // at.obdev.littlesnitch.agent, com.rogueamoeba.soundsource,
        // com.wireguard.macos, org.eduvpn.app, com.lighting.huesync,
        // pl.maketheweb.cleanshotx, and others). This marker window
        // has the same (width, height) as the on-screen icon but
        // its position is non-deterministic across launches and can
        // even sit on a different display, which is why this pass
        // runs here in the XPC where allWindows spans every display
        // rather than in the main app's per-call list.
        //
        // For each unresolved on-screen icon whose title is NOT
        // bundle-ID-shaped (generic names like "Item-0", or empty),
        // looks for the unique marker window with matching size and
        // synthesizes the sourcePID by either using the marker's
        // CG-layer owning PID (when it is neither Thaw itself nor
        // Control Center) or by looking up the running app named by
        // the marker's bundle-ID title. Multi-match cases are skipped
        // to prevent misattribution. Thaw's own control items and
        // self-registration windows are excluded so Thaw's PID can
        // never be attributed to a third-party widget.
        var markerWindowIDs = Set<CGWindowID>()
        if !unresolvedWindows.isEmpty {
            let markers = MarkerPairResolver.extractMarkers(
                from: allWindows.map { win in
                    (
                        windowID: win.windowID,
                        title: win.title,
                        size: win.bounds.size,
                        owningPID: win.owningApplication?.processIdentifier
                    )
                },
                thawControlItemPrefix: "Thaw.ControlItem.",
                thawBundleID: thawBundleID
            )
            markerWindowIDs = Set(markers.map(\.windowID))
            let unresolvedInfos = allWindows.filter { unresolvedWindows.contains($0.windowID) }
            let icons = unresolvedInfos.map { win in
                MarkerPairResolver.UnresolvedIcon(
                    windowID: win.windowID,
                    title: win.title,
                    size: win.bounds.size
                )
            }
            let resolutions = MarkerPairResolver.resolve(
                unresolvedIcons: icons,
                markers: markers,
                thawBundleID: thawBundleID,
                ccBundleID: ccBundleID,
                pidToBundleID: { pid in
                    NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                },
                bundleIDToPID: { bundleID in
                    NSRunningApplication
                        .runningApplications(withBundleIdentifier: bundleID)
                        .first?
                        .processIdentifier
                }
            )
            for resolution in resolutions {
                SourcePIDCache.diagLog.info(
                    "SourcePIDCache marker-pair resolution: windowID=\(resolution.iconWindowID) → PID \(resolution.resolvedPID) via marker windowID=\(resolution.markerWindowID) (title=\(resolution.markerTitle))"
                )
                state.withLock { $0.pids[resolution.iconWindowID] = resolution.resolvedPID }
                unresolvedWindows.remove(resolution.iconWindowID)
            }
        }

        // Title-identity fallback for parked (off-screen) items.
        //
        // The spatial passes need an AX child near the CG window and the
        // marker-pair pass only considers on-screen icons, so a widget whose
        // window title is its own bundle identifier (Little Snitch's agent)
        // becomes unresolvable the moment it is parked at off-screen
        // coordinates — and an unresolvable hidden item can never be matched
        // back to its saved section. An exact title == bundle-identifier
        // match against a running application is direct ownership evidence
        // that needs no geometry; the reverse-DNS shape requirement keeps
        // generic slot titles (Item-0) away from the lookup.
        let unresolvedInfos = allWindows.filter {
            unresolvedWindows.contains($0.windowID) && !markerWindowIDs.contains($0.windowID)
        }
        for window in unresolvedInfos {
            guard let title = window.title,
                  title.split(separator: ".").count >= 3,
                  let pid = NSRunningApplication
                  .runningApplications(withBundleIdentifier: title)
                  .first?
                  .processIdentifier
            else { continue }
            SourcePIDCache.diagLog.info(
                "SourcePIDCache title-identity resolution: windowID=\(window.windowID) → PID \(pid) (title=\(title))"
            )
            state.withLock { $0.pids[window.windowID] = pid }
            unresolvedWindows.remove(window.windowID)
            totalMatchesFound += 1
        }

        let finalPID = state.withLock { $0.pids[window.windowID] }
        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: batch resolution finished. Found \(totalMatchesFound) matches. Requested windowID \(window.windowID) -> PID \(finalPID.map { "\($0)" } ?? "nil") (checked \(appsChecked) apps, \(appsSkipped) skipped by negative cache, \(appsWithBar) with extras bar, \(totalChildrenChecked) children, took \(ContinuousClock.now - scanStart))")

        // Negative-cache every window that survived the full scan unresolved,
        // with a deadline that backs off as consecutive failures accumulate:
        // short at first so the app's startup settling window can retry while
        // AX trees are still warming up, then the steady-state TTL. A flat
        // TTL here wedged resolution permanently — the first cold scan
        // under-resolves, its deadline outlasts every retry the app makes,
        // and no scan runs again (the app stops requesting once settled).
        // Entries that expired, and entries whose window this scan resolved,
        // are dropped on the same write, so both dictionaries stay bounded and
        // a resolved window's next miss starts at the first rung. This runs
        // unconditionally: a scan that resolves everything leaves
        // unresolvedWindows empty, and that is exactly when the stale entries
        // need clearing.
        let now = ContinuousClock.now
        let unresolvedSnapshot = unresolvedWindows
        state.withLock { state in
            var negativeUntil = state.negativeUntil.filter { entry in
                entry.value > now && state.pids[entry.key] == nil
            }
            for windowID in unresolvedSnapshot {
                let failures = (state.negativeFailures[windowID] ?? 0) + 1
                state.negativeFailures[windowID] = failures
                negativeUntil[windowID] = now + SourcePIDNegativeCachePolicy.ttl(
                    afterConsecutiveFailures: failures
                )
            }
            state.negativeUntil = negativeUntil
            state.negativeFailures = state.negativeFailures.filter {
                negativeUntil[$0.key] != nil
            }
        }

        // Diagnostic dump for unresolved windows.
        //
        // When at least one window remains unresolved after the batch
        // loop, log enough state to determine which of three failure
        // modes is hitting: (a) the suspect app is absent from
        // NSWorkspace runningApplications, (b) the app is present but
        // does not expose AXExtrasMenuBar (the per-app menu extras
        // attribute is unset on macOS 26 for some widgets), or (c)
        // the app exposes extras but their frames are more than 1pt
        // off-center from the unresolved CG window bounds (a HiDPI,
        // multi-display, or coord-system mismatch).
        //
        // Quiet path on normal cycles where every window resolves.
        // The diagnostic re-walks AX children, which can be expensive,
        // so it only fires when there is actual unresolved state—and no more
        // than once per interval for the same unresolved set.
        var shouldDumpUnresolvedDiagnostics = false
        if !unresolvedWindows.isEmpty {
            let unresolvedSnapshot = unresolvedWindows
            shouldDumpUnresolvedDiagnostics = lastUnresolvedDiagDump.withLock { last in
                if let last {
                    return last.windowIDs != unresolvedSnapshot
                        || ContinuousClock.now >= last.at + Self.unresolvedDiagDumpInterval
                }
                return true
            }
            if shouldDumpUnresolvedDiagnostics {
                lastUnresolvedDiagDump.withLock { $0 = (unresolvedSnapshot, ContinuousClock.now) }
            }
        }
        if shouldDumpUnresolvedDiagnostics {
            SourcePIDCache.diagLog.debug(
                "SourcePIDCache diag: \(unresolvedWindows.count) window(s) unresolved after batch, dumping details"
            )

            // Ad-hoc probe for specific bundles under investigation.
            // Leave empty in normal builds; populate with bundle IDs
            // when diagnosing a particular widget's resolution failure
            // to see whether NSWorkspace sees it and whether it claims
            // an extras menu bar of its own.
            let probeBundleIDs: Set<String> = []
            for bundleID in probeBundleIDs {
                if let app = apps.first(where: { $0.bundleIdentifier == bundleID }) {
                    SourcePIDCache.diagLog.debug(
                        "SourcePIDCache diag probe: \(bundleID) PRESENT pid=\(app.processIdentifier) hasExtrasBar=\(app.hasExtrasMenuBar)"
                    )
                } else {
                    SourcePIDCache.diagLog.debug(
                        "SourcePIDCache diag probe: \(bundleID) ABSENT from runningApplications"
                    )
                }
            }

            let unresolvedWindowInfos = allWindows.filter { unresolvedWindows.contains($0.windowID) }
            for window in unresolvedWindowInfos {
                let target = window.bounds.center
                // Collect every extras-bar child across all apps as a candidate,
                // not just the single closest, so the diagnostic shows whether the
                // nearest match is unique or whether a competing child sits within
                // the match radius. Paired with each candidate's enabled state and
                // distance, this is usually enough to see why an item failed to
                // resolve (wrong distance, missing AXEnabled, or ambiguity).
                var candidates: [(distance: CGFloat, label: String, frame: CGRect, enabled: Bool?)] = []
                for app in apps {
                    guard let bar = app.getOrCreateExtrasMenuBar() else { continue }
                    let label = app.bundleIdentifier ?? app.localizedName ?? "pid=\(app.processIdentifier)"
                    for child in AXHelpers.children(for: bar) {
                        guard let frame = AXHelpers.frame(for: child) else { continue }
                        candidates.append((frame.center.distance(to: target), label, frame, AXHelpers.enabledAttribute(child)))
                    }
                }
                let nearest = candidates.sorted { $0.distance < $1.distance }
                let best = nearest.first
                let cgOwner = window.owningApplication.map { app in
                    "\(app.bundleIdentifier ?? app.localizedName ?? "?"):pid=\(app.processIdentifier)"
                } ?? "nil"
                // closestAXEnabled distinguishes a missing AXEnabled attribute (nil)
                // from an explicitly disabled child, and nearest lists the top
                // candidates with their owning app and enabled state, so a future
                // unresolved item can be diagnosed from a single log line.
                let nearestDesc = nearest.prefix(3).map {
                    "\($0.label)@\(String(format: "%.1f", $0.distance))(enabled=\($0.enabled.map { "\($0)" } ?? "nil"))"
                }.joined(separator: ", ")
                SourcePIDCache.diagLog.debug(
                    "SourcePIDCache diag unresolved: windowID=\(window.windowID) title=\(window.title ?? "nil") bounds=\(window.bounds) center=\(target) | cgOwner=\(cgOwner) ownerName=\(window.ownerName ?? "nil") | closestAXFrame=\(best.map { "\($0.frame)" } ?? "nil") in app=\(best?.label ?? "(none)") distance=\(best?.distance ?? .greatestFiniteMagnitude) closestAXEnabled=\(best?.enabled.map { "\($0)" } ?? "nil") | nearest=[\(nearestDesc)]"
                )
            }

            for app in apps {
                guard let bar = app.getOrCreateExtrasMenuBar() else { continue }
                let children = AXHelpers.children(for: bar)
                // Include each child's raw enabled value (nil = attribute absent)
                // next to its frame, so a child the matching pass excluded as
                // explicitly disabled is visible here.
                let childDescs = children.compactMap { child -> String? in
                    guard let frame = AXHelpers.frame(for: child) else { return nil }
                    let enabled = AXHelpers.enabledAttribute(child).map { "\($0)" } ?? "nil"
                    return "(x=\(frame.minX),y=\(frame.minY),w=\(frame.width),h=\(frame.height),enabled=\(enabled))"
                }
                guard !childDescs.isEmpty else { continue }
                let label = app.bundleIdentifier ?? app.localizedName ?? "pid=\(app.processIdentifier)"
                SourcePIDCache.diagLog.debug(
                    "SourcePIDCache diag app=\(label) extrasBar children=\(children.count) frames=\(childDescs.joined(separator: " "))"
                )
            }
        }

        return finalPID
    }
}
