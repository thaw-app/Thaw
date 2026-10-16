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
/// The "source process" is the process that created a menu bar item. As of
/// macOS 26, item windows are owned by Control Center, so `kCGWindowOwnerPID`
/// no longer identifies it and we resolve it through Accessibility instead.
/// Accessibility calls block, so the work runs in this XPC service.
///
/// Only the Combine wiring in `start()` (and `cancellable`) is actor-isolated.
/// `state`, `scanLock`, and `CachedApplication` entries have their own
/// `OSAllocatedUnfairLock`, so members that only touch them are `nonisolated`.
/// Isolating them would serialize fast cache-hit reads behind blocking AX
/// scans; `scanLock` is what serializes full scans.
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

        /// How many consecutive checks have found no extras menu bar.
        ///
        /// Zero once one is found, so this doubles as what
        /// ``ExtrasMenuBarProbeMemory`` wants to remember: a positive count
        /// is an application worth skipping next launch, and zero is one
        /// whose entry must be dropped.
        var consecutiveExtrasMenuBarMisses: Int {
            lock.withLock { $0.consecutiveMisses }
        }

        /// Whether an unexpired negative deadline would make
        /// ``getOrCreateExtrasMenuBar()`` skip its accessibility calls.
        ///
        /// Diagnostics only, sampled outside the lock that
        /// ``getOrCreateExtrasMenuBar()`` takes, so it is a count rather than a
        /// guarantee. It tells a full-system probe from one the negative cache spared.
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
        ///
        /// - Parameter seed: What earlier sessions learned about this
        ///   application, from ``ExtrasMenuBarProbeMemory``. Starting partway up
        ///   the ladder keeps a cold start from re-probing the whole system; a
        ///   seeded deadline still expires within seconds.
        init(_ runningApp: NSRunningApplication, seed: (misses: Int, initialTTL: Duration)? = nil) {
            self.runningApp = runningApp
            guard let seed else {
                return
            }
            lock.withLock {
                $0.consecutiveMisses = seed.misses
                $0.retryAfter = ContinuousClock.now + seed.initialTTL
            }
        }

        /// Returns the accessibility element representing the app's extras
        /// menu bar, creating it if necessary.
        ///
        /// The element is cached after the first creation.
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
                // No extras menu bar yet. It may register a status item later, so
                // back off with a growing deadline instead of flagging it permanently.
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
        /// Drives the negative-cache TTL ladder: short deadlines while AX trees
        /// warm up at startup, then the steady-state TTL. Reset when a window
        /// resolves; pruned alongside `negativeUntil`.
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

    static let shared = SourcePIDCache()

    // The per-failure negative-cache deadline lives in
    // SourcePIDNegativeCachePolicy (Shared/), so the ladder is unit-testable
    // from ThawTests.

    /// How long a single app's extras-bar probe may take before the scan
    /// names it in the log.
    ///
    /// Low enough that slow apps stand out in a scan of a few hundred
    /// milliseconds, high enough that a healthy scan logs nothing.
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
    /// `nonisolated`: its own `OSAllocatedUnfairLock` synchronizes it, so
    /// cache-hit reads don't wait on the actor while `start()` or cleanup run.
    private nonisolated let state = OSAllocatedUnfairLock(initialState: State())

    /// What earlier sessions learned about which applications have an extras
    /// menu bar, read once at init and rewritten as this session revises it.
    ///
    /// `nonisolated` and separately locked for the same reason as `state`:
    /// it is touched from `performCleanupBody`, which is `nonisolated` and
    /// cannot reach actor-isolated storage.
    private nonisolated let probeMemory = OSAllocatedUnfairLock(
        initialState: ExtrasMenuBarProbeStore.load()
    )

    /// Lock to prevent multiple concurrent full scans of all applications.
    ///
    /// `nonisolated` for the same reason as `state` above — it is the
    /// mechanism (not actor isolation) that serializes full AX scans.
    private nonisolated let scanLock = OSAllocatedUnfairLock(initialState: ())

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

    private init() {
        Bridging.setProcessUnresponsiveTimeout(3)
    }

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
        let remembered = probeMemory.withLock { $0 }

        state.withLock { state in
            // Clean up entries for terminated apps to prevent memory leaks
            let oldAppPids = Set(state.apps.map(\.processIdentifier))
            let terminatedPids = oldAppPids.subtracting(currentAppPids)

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
                    // Prefer the cached app: it may already hold its extras menu bar,
                    // and its negative deadline carries over instead of re-probing.
                    result.apps.append(app)
                } else {
                    // New app. One the probe memory knows starts partway up the
                    // ladder, keeping the first scan off the ~155 of ~170 apps
                    // that never have an extras menu bar (#956).
                    let rememberedMisses: Int? = if let bundleID = app.bundleIdentifier {
                        remembered[bundleID]
                    } else {
                        nil
                    }
                    let seed = ExtrasMenuBarProbeMemory.seed(forRememberedMisses: rememberedMisses)
                    result.apps.append(CachedApplication(app, seed: seed))
                }

                if let pids = pidMappings[pid] {
                    for (windowID, pid) in pids {
                        result.pids[windowID] = pid
                    }
                }
            }
            // Carry negative state only for still-unresolved windows, so a window
            // that has since resolved starts its next miss at the first rung.
            state.negativeUntil = carriedNegativeUntil.filter { state.pids[$0.key] == nil }
            state.negativeFailures = carriedNegativeFailures.filter {
                state.negativeUntil[$0.key] != nil
            }

            if !terminatedPids.isEmpty {
                SourcePIDCache.diagLog.info("Cleaned up PID cache entries for terminated processes: \(terminatedPids)")
            }
        }

        recordExtrasMenuBarProbeResults(startingFrom: remembered)
    }

    /// Folds what this session has learned about extras menu bars back into
    /// the memory the next launch starts from.
    ///
    /// Runs after every cleanup rather than at exit: the system kills this
    /// on-demand XPC service when idle, with no orderly shutdown.
    private nonisolated func recordExtrasMenuBarProbeResults(
        startingFrom remembered: [String: Int]
    ) {
        let apps = state.withLock { $0.apps }
        let observed = apps.reduce(into: [String: Int]()) { result, app in
            guard let bundleID = app.bundleIdentifier else {
                return
            }
            // Several processes can share a bundle identifier. The lowest count
            // wins: a wasted probe is cheaper than an unresolved item.
            result[bundleID] = min(result[bundleID] ?? .max, app.consecutiveExtrasMenuBarMisses)
        }

        let merged = ExtrasMenuBarProbeMemory.merged(
            persisted: remembered,
            observed: observed,
            runningBundleIDs: Set(observed.keys)
        )
        probeMemory.withLock { $0 = merged }
        ExtrasMenuBarProbeStore.save(merged)
    }

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
    /// Wrapped in an autoreleasepool: this service has no NSApplication, so
    /// autoreleased ObjC/CF objects would pile up on the GCD thread until exit.
    nonisolated func pids(for windows: [WindowInfo]) -> [pid_t?] {
        autoreleasepool {
            pidsBody(for: windows)
        }
    }

    private nonisolated func pidsBody(for windows: [WindowInfo]) -> [pid_t?] {
        // Drive the scan with an unresolved window, not `windows.first`: pidBody
        // returns early on a cache hit, so mid-session arrivals would never scan.
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
        // A zero-area window can't match an AX element, so it must not start a
        // scan itself: it would trigger a full traversal every TTL and never resolve.
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

        // Only one thread performs the full AX traversal, even with many concurrent windows.
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
                // AX reads run on the target app's main thread, bounded only by the
                // timeout set in `init`. Naming slow apps tells a long app list from a wedged app.
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
                // Never skip Thaw's own disabled children: a collapsed divider is
                // disabled on purpose (.hideSection), and skipping it breaks both
                // sourcePID-based ControlItemPair fallbacks (#899, #895).
                let isOwnApp = app.bundleIdentifier == thawBundleID
                let children = AXHelpers.children(for: bar)
                for child in children {
                    totalChildrenChecked += 1
                    // Skip only explicitly disabled children. Missing AXEnabled counts as
                    // enabled: some Control Center-hosted items (the Clock) never publish it.
                    guard isOwnApp || AXHelpers.enabledAttribute(child) != false,
                          let childFrame = AXHelpers.frame(for: child)
                    else {
                        continue
                    }

                    let childCenter = childFrame.center

                    // Skip Control Center-hosted generic Item-N slots: the match only
                    // proves CC hosts it, and CC's PID would mark it a transient CC
                    // widget that can't be hidden. The marker-pair pass supplies the
                    // real owner. On one display markers may never publish, leaving
                    // it unresolved; that beats a permanent mislabel.
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

        // Exact-title PID resolution, run first: a title equal to a running app's
        // bundle ID names its owner outright. CC-hosted items publish no
        // AXExtrasMenuBar, so the spatially confirmed pass below never resolves
        // them (#854). Thaw and Control Center are never attributed.
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

        // Corroborated spatial fallback for CC-hosted items whose app does publish
        // an extras-bar AX child, offset from the wider CG slot's center (AirBuddy
        // ~2pt, SpamSieve ~8pt). The nearest child within 20pt is accepted only
        // when the title passes HostedItemOwnership; that check, not the distance,
        // rejects unrelated neighbors. Runs before marker-pair. Furthest correct
        // match seen in logs is ~15pt.
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
        // On macOS 26 some widgets (Little Snitch's agent) are hosted by Control
        // Center at the AX layer and publish no AXExtrasMenuBar, so the spatial
        // pass can't resolve them. Each such widget also publishes a second CG
        // "marker" window titled with its bundle ID, same size as the icon but at
        // an unpredictable position, possibly on another display (hence this runs
        // in the XPC, where allWindows spans every display).
        //
        // For each unresolved icon with a generic title ("Item-0" or empty), find
        // the unique same-size marker and take its owner PID (unless Thaw or CC)
        // or the app its title names. Multiple matches are skipped, and Thaw's
        // own windows are excluded so its PID never lands on a third-party widget.
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

        // Title-identity fallback for parked (off-screen) items, which the spatial
        // and marker-pair passes can't see. A title equal to a running app's bundle
        // ID proves ownership without geometry; the reverse-DNS check skips Item-N.
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

        // Negative-cache unresolved windows with a backoff: short deadlines while AX
        // trees warm up, then the steady-state TTL. A flat TTL wedged resolution for
        // good, since the cold scan's deadline outlasted every app retry. Expired and
        // now-resolved entries are dropped here, so this runs even when all resolved.
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

        // Diagnostic dump for unresolved windows. Distinguishes three failures:
        // (a) the app is missing from runningApplications, (b) it exposes no
        // AXExtrasMenuBar (unset on macOS 26 for some widgets), or (c) its extras
        // are more than 1pt off the CG bounds (HiDPI, multi-display, coordinates).
        // Re-walking AX is expensive, so it runs at most once per interval per set.
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

            // Bundle IDs to probe while debugging one widget's resolution. Leave empty.
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
                // Collect every extras-bar child, not just the closest, so the log
                // shows competing candidates within the match radius.
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
                // closestAXEnabled tells a missing AXEnabled (nil) from an explicitly
                // disabled child.
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
                // Raw enabled value per child (nil = attribute absent).
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
