//
//  SourcePIDCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import AXSwift
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
final class SourcePIDCache {
    private static let diagLog = DiagLog(category: "SourcePIDCache")
    /// An object that contains a running application and provides an
    /// interface to access relevant information, such as its process
    /// identifier and extras menu bar.
    private final class CachedApplication: @unchecked Sendable {
        private let runningApp: NSRunningApplication

        private struct State {
            var extrasMenuBar: UIElement?
            var checkedWithNoResult = false
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
            let (hasCached, isNegative) = lock.withLock {
                ($0.extrasMenuBar, $0.checkedWithNoResult)
            }
            if let bar = hasCached {
                return bar
            }
            if isNegative {
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
                // App is reachable but has no extras menu bar.
                lock.withLock {
                    if $0.extrasMenuBar == nil {
                        $0.checkedWithNoResult = true
                    }
                }
                return nil
            }
            lock.withLock { $0.extrasMenuBar = bar }
            return bar
        }

        /// Resets the negative cache so the app will be re-checked
        /// on the next scan. Called during cleanup to discover apps
        /// that register status items after launch. Preserves a
        /// valid `extrasMenuBar` to avoid unnecessary AX re-queries.
        func resetNegativeCache() {
            lock.withLock {
                if $0.extrasMenuBar == nil {
                    $0.checkedWithNoResult = false
                }
            }
        }
    }

    /// State for the cache.
    private struct State {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

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
    static nonisolated(unsafe) let shared = SourcePIDCache()

    /// The cache's protected state.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Lock to prevent multiple concurrent full scans of all applications.
    private let scanLock = OSAllocatedUnfairLock(initialState: ())

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
    private func performCleanup() {
        autoreleasepool {
            performCleanupBody()
        }
    }

    private func performCleanupBody() {
        let runningApps = NSWorkspace.shared.runningApplications
        SourcePIDCache.diagLog.debug("Performing PID cache cleanup")

        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let currentAppPids = Set(runningApps.map(\.processIdentifier))

        let reusedApps = state.withLock { state -> [CachedApplication] in
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

            // Collect reused apps to reset their negative caches after
            // releasing the lock.
            var reused = [CachedApplication]()

            // Create a new state that matches the current running apps.
            state = runningApps.reduce(into: State()) { result, app in
                let pid = app.processIdentifier

                if let app = appMappings[pid] {
                    // Prefer the cached app, as it may have already done
                    // the work to initialize its extras menu bar.
                    reused.append(app)
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

            // Log cleanup activity
            if !terminatedPids.isEmpty {
                SourcePIDCache.diagLog.info("Cleaned up PID cache entries for terminated processes: \(terminatedPids)")
            }

            return reused
        }

        // Reset negative caches outside the state lock so we don't
        // hold the unfair lock while acquiring per-app locks.
        for app in reusedApps {
            app.resetNegativeCache()
        }
    }

    /// Starts the observers for the cache.
    func start() {
        SourcePIDCache.diagLog.debug("Starting observers for source PID cache")
        _ = cancellable
    }

    /// Returns the cached process identifier for the given window,
    /// updating the cache if needed.
    func pid(for window: WindowInfo) -> pid_t? {
        // Wrap the entire request in an autoreleasepool. This XPC service
        // has no NSApplication, so autoreleased ObjC/CF objects from
        // WindowInfo creation, AX API calls, and CGS bridging would
        // otherwise accumulate on the GCD thread until process exit.
        autoreleasepool {
            pidBody(for: window)
        }
    }

    /// Returns the cached process identifiers for the given windows,
    /// performing a single batch resolution if any are missing.
    ///
    /// `pidBody` already caches **all** matched windows during its full
    /// AX scan, so after one call all resolvable PIDs are available.
    func pids(for windows: [WindowInfo]) -> [pid_t?] {
        autoreleasepool {
            pidsBody(for: windows)
        }
    }

    private func pidsBody(for windows: [WindowInfo]) -> [pid_t?] {
        // Drive the scan via an unresolved window in the batch, not via
        // `windows.first`. pidBody returns early on a cache hit (line 292),
        // so passing a cached window skips the AX traversal entirely.
        // Once macOS 26 began routing some widgets through the marker-pair
        // fallback that lives in pidBody's scan body, mid-session arrivals
        // (new app launches that introduce a fresh nil-PID windowID) were
        // never getting a scan: the first window in their batch was always
        // an already-cached resolved one, and the scan only ever ran at
        // session start.
        if let unresolved = windows.first(where: { window in
            state.withLock { $0.pids[window.windowID] == nil }
        }) {
            _ = pidBody(for: unresolved)
        }
        return windows.map { window in
            state.withLock { $0.pids[window.windowID] }
        }
    }

    private func pidBody(for window: WindowInfo) -> pid_t? {
        if let pid = state.withLock({ $0.pids[window.windowID] }) {
            SourcePIDCache.diagLog.debug("SourcePIDCache.pid: cache hit for windowID \(window.windowID) -> PID \(pid)")
            return pid
        }

        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: cache miss for windowID \(window.windowID) title=\(window.title ?? "nil"), acquiring scan lock")

        // Use a lock to ensure that only one thread performs the full AX traversal.
        // This is critical when resolving many windows (e.g. 64) concurrently.
        scanLock.lock()
        defer { scanLock.unlock() }

        // Re-check cache after acquiring the scan lock, as it may have been populated
        // by another thread that just finished a full scan.
        if let pid = state.withLock({ $0.pids[window.windowID] }) {
            SourcePIDCache.diagLog.debug("SourcePIDCache.pid: cache hit after scan lock for windowID \(window.windowID) -> PID \(pid)")
            return pid
        }

        let isTrusted = AXHelpers.isProcessTrusted()
        guard isTrusted else {
            SourcePIDCache.diagLog.warning("SourcePIDCache.pid: AXHelpers.isProcessTrusted() returned false — accessibility permission missing in XPC service")
            return nil
        }

        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: performing batch resolution via AX API")

        // Fetch all current menu bar item windows to perform a single batch resolution.
        // This avoids doing the O(W*A*C) work (Windows * Apps * Children) for every request.
        let allWindows = WindowInfo.createMenuBarWindows(option: .itemsOnly)
        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: batch resolving for \(allWindows.count) windows")

        // Get a copy of the apps list to iterate over without holding the state lock.
        let apps = state.withLock { state -> [CachedApplication] in
            state.partitionApps()
            return state.apps
        }

        var appsChecked = 0
        var appsWithBar = 0
        var totalChildrenChecked = 0
        var totalMatchesFound = 0
        var unresolvedWindows = Set(allWindows.map(\.windowID))

        for app in apps {
            if unresolvedWindows.isEmpty {
                break
            }
            appsChecked += 1
            autoreleasepool {
                guard let bar = app.getOrCreateExtrasMenuBar() else {
                    return
                }
                appsWithBar += 1
                let children = AXHelpers.children(for: bar)
                for child in children {
                    totalChildrenChecked += 1
                    guard AXHelpers.isEnabled(child),
                          let childFrame = AXHelpers.frame(for: child)
                    else {
                        continue
                    }

                    let childCenter = childFrame.center

                    // Match this child to ANY window in our list.
                    if let matchedWindow = allWindows.first(where: {
                        $0.bounds.center.distance(to: childCenter) <= 1
                    }) {
                        totalMatchesFound += 1
                        unresolvedWindows.remove(matchedWindow.windowID)
                        let pid = app.processIdentifier
                        state.withLock { $0.pids[matchedWindow.windowID] = pid }
                    }
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
        if !unresolvedWindows.isEmpty {
            let thawBundleID = "com.stonerl.Thaw"
            let ccBundleID = "com.apple.controlcenter"
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

        // AX-windowID fallback for Control-Center-hosted proxy nodes.
        //
        // Runs last so the marker-pair pass above (which can attribute
        // to the real owning app's PID via the marker's bundle-ID
        // title) gets first crack at unresolved windows. Anything
        // marker-pair could not resolve falls through to here.
        //
        // The primary spatial loop earlier in this method skips AX
        // children with isEnabled=false. On macOS 26, Control Center
        // hosts proxy AX nodes for third-party status items whose
        // owning app does not publish its own AXExtrasMenuBar (Little
        // Snitch's agent is the observed case: hasExtrasBar=false on
        // the agent process, Control Center publishes a disabled
        // proxy at the icon's exact bounds). When the marker window
        // is not published by macOS (observed taking 50 minutes to
        // appear in one session, never appearing in another), the
        // marker-pair pass cannot bridge the icon to its owning app.
        //
        // For each disabled AX child whose _AXUIElementGetWindow-
        // returned CGWindowID matches an unresolved CG window, pull
        // identifying AX attributes off the proxy and match them
        // against running apps to recover the real owning PID. The
        // AXIdentifier attribute on Control-Center-hosted proxies is
        // populated with the owning app's bundle identifier
        // (observed for Little Snitch's agent), so that's the primary
        // signal. Title and description are tried as fallbacks
        // (localized app name lookup). Only when none of those match
        // a running app does the resolution fall back to the proxy's
        // host PID (Control Center), which is the same attribution
        // the namespace fallback would derive anyway but stored as
        // a concrete resolution rather than nil-PID limbo.
        if !unresolvedWindows.isEmpty {
            // Pre-compute unresolved windows' centers so we can do a
            // spatial backstop match when _AXUIElementGetWindow does
            // not return a CGWindowID we recognise. Some macOS 26
            // hosting cases return the parent menu-bar window rather
            // than the proxy child's window; the backstop catches
            // those by pairing on bounds-center proximity (same
            // criterion the primary spatial pass uses).
            let unresolvedInfos = allWindows.filter { unresolvedWindows.contains($0.windowID) }
            for app in apps {
                if unresolvedWindows.isEmpty {
                    break
                }
                autoreleasepool {
                    guard let bar = app.getOrCreateExtrasMenuBar() else { return }
                    let children = AXHelpers.children(for: bar)
                    for child in children {
                        guard !AXHelpers.isEnabled(child) else { continue }

                        let childFrame = AXHelpers.frame(for: child)
                        let proxyWID = AXHelpers.windowID(for: child)
                        let axIdentifier = AXHelpers.identifier(for: child)
                        let axTitle = AXHelpers.title(for: child)
                        let axDescription = AXHelpers.description(for: child)

                        // Resolve the unresolved windowID this disabled
                        // child corresponds to. Prefer the SPI's direct
                        // answer when it's a known unresolved window;
                        // fall back to a spatial center-point match
                        // (within 1pt) when the SPI returned a windowID
                        // we do not have in the unresolved set (parent
                        // bar, sibling window, etc.). Tracks the source
                        // for the diag log so we can see in the field
                        // which path is firing for each item.
                        var matchedWID: CGWindowID?
                        var matchSource: String = "none"
                        if let proxyWID,
                           unresolvedWindows.contains(proxyWID)
                        {
                            matchedWID = proxyWID
                            matchSource = "SPI"
                        } else if let frame = childFrame {
                            let target = frame.center
                            if let spatial = unresolvedInfos.first(where: {
                                $0.bounds.center.distance(to: target) <= 1
                            }) {
                                if unresolvedWindows.contains(spatial.windowID) {
                                    matchedWID = spatial.windowID
                                    matchSource = "spatial"
                                }
                            }
                        }

                        // Unconditional probe log so we can see in the
                        // field what each disabled child yielded, even
                        // when neither match path produced an unresolved
                        // windowID. Critical for diagnosing whether the
                        // pass is silently passing over a candidate
                        // (zero matches and zero logs would otherwise be
                        // indistinguishable from "this build does not
                        // contain the fallback").
                        SourcePIDCache.diagLog.debug(
                            "SourcePIDCache AX-windowID probe: host=\(app.bundleIdentifier ?? "pid=\(app.processIdentifier)") childFrame=\(childFrame.map { "\($0)" } ?? "nil") spiWindowID=\(proxyWID.map { "\($0)" } ?? "nil") spiInUnresolved=\(proxyWID.map { unresolvedWindows.contains($0) } ?? false) matchedWID=\(matchedWID.map { "\($0)" } ?? "nil") matchSource=\(matchSource) AXIdentifier=\(axIdentifier ?? "nil") AXTitle=\(axTitle ?? "nil") AXDescription=\(axDescription ?? "nil")"
                        )

                        guard let matchedWID else { continue }

                        // Look for the real owning app by walking the
                        // proxy's identifying AX attributes against the
                        // running apps list. Bundle-ID match (via the
                        // AXIdentifier attribute) wins over name match
                        // because it's unambiguous; title and
                        // description fall back to case-insensitive
                        // localizedName equality.
                        var resolvedPID: pid_t?
                        var resolvedVia = "host"
                        if let bundleID = axIdentifier,
                           let match = NSRunningApplication
                            .runningApplications(withBundleIdentifier: bundleID)
                            .first
                        {
                            resolvedPID = match.processIdentifier
                            resolvedVia = "AXIdentifier=\(bundleID)"
                        } else if let name = axTitle?.lowercased(),
                                  !name.isEmpty,
                                  let match = NSWorkspace.shared.runningApplications.first(where: {
                                      $0.localizedName?.lowercased() == name
                                  })
                        {
                            resolvedPID = match.processIdentifier
                            resolvedVia = "AXTitle=\(axTitle ?? "")"
                        } else if let desc = axDescription?.lowercased(),
                                  !desc.isEmpty,
                                  let match = NSWorkspace.shared.runningApplications.first(where: {
                                      $0.localizedName?.lowercased() == desc
                                  })
                        {
                            resolvedPID = match.processIdentifier
                            resolvedVia = "AXDescription=\(axDescription ?? "")"
                        }
                        let finalPID = resolvedPID ?? app.processIdentifier
                        SourcePIDCache.diagLog.info(
                            "SourcePIDCache AX-windowID fallback: windowID=\(matchedWID) → PID \(finalPID) via \(resolvedVia) (match=\(matchSource) host=\(app.bundleIdentifier ?? "pid=\(app.processIdentifier)"))"
                        )
                        state.withLock { $0.pids[matchedWID] = finalPID }
                        unresolvedWindows.remove(matchedWID)
                    }
                }
            }
        }

        let finalPID = state.withLock { $0.pids[window.windowID] }
        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: batch resolution finished. Found \(totalMatchesFound) matches. Requested windowID \(window.windowID) -> PID \(finalPID.map { "\($0)" } ?? "nil") (checked \(appsChecked) apps, \(appsWithBar) with extras bar, \(totalChildrenChecked) children)")

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
        // so it only fires when there is actual unresolved state.
        if !unresolvedWindows.isEmpty {
            SourcePIDCache.diagLog.debug(
                "SourcePIDCache diag: \(unresolvedWindows.count) window(s) unresolved after batch, dumping details"
            )

            let probeBundleIDs: Set<String> = [
                "at.obdev.littlesnitch",
                "at.obdev.littlesnitch.agent",
            ]
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
                var bestDistance = CGFloat.greatestFiniteMagnitude
                var bestLabel = "(none)"
                var bestFrame: CGRect?
                for app in apps {
                    guard let bar = app.getOrCreateExtrasMenuBar() else { continue }
                    let children = AXHelpers.children(for: bar)
                    for child in children {
                        guard let frame = AXHelpers.frame(for: child) else { continue }
                        let d = frame.center.distance(to: target)
                        if d < bestDistance {
                            bestDistance = d
                            bestLabel = app.bundleIdentifier ?? app.localizedName ?? "pid=\(app.processIdentifier)"
                            bestFrame = frame
                        }
                    }
                }
                let cgOwner = window.owningApplication.map { app in
                    "\(app.bundleIdentifier ?? app.localizedName ?? "?"):pid=\(app.processIdentifier)"
                } ?? "nil"
                SourcePIDCache.diagLog.debug(
                    "SourcePIDCache diag unresolved: windowID=\(window.windowID) title=\(window.title ?? "nil") bounds=\(window.bounds) center=\(target) | cgOwner=\(cgOwner) ownerName=\(window.ownerName ?? "nil") | closestAXFrame=\(bestFrame.map { "\($0)" } ?? "nil") in app=\(bestLabel) distance=\(bestDistance)"
                )
            }

            for app in apps {
                guard let bar = app.getOrCreateExtrasMenuBar() else { continue }
                let children = AXHelpers.children(for: bar)
                let frames = children.compactMap { AXHelpers.frame(for: $0) }
                guard !frames.isEmpty else { continue }
                let label = app.bundleIdentifier ?? app.localizedName ?? "pid=\(app.processIdentifier)"
                SourcePIDCache.diagLog.debug(
                    "SourcePIDCache diag app=\(label) extrasBar children=\(children.count) frames=\(frames.map { "(x=\($0.minX),y=\($0.minY),w=\($0.width),h=\($0.height))" }.joined(separator: " "))"
                )
            }
        }

        return finalPID
    }
}
