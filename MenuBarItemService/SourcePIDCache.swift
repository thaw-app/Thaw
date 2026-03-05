//
//  SourcePIDCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift
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
    private final class CachedApplication {
        private let runningApp: NSRunningApplication
        private let lock = NSLock()
        private var _extrasMenuBar: UIElement?
        private var _checkedWithNoResult = false

        /// The app's process identifier.
        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        /// A Boolean value indicating whether the app's extras menu
        /// bar has been successfully created and stored.
        var hasExtrasMenuBar: Bool {
            lock.withLock { _extrasMenuBar != nil }
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
                (_extrasMenuBar, _checkedWithNoResult)
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
                    if _extrasMenuBar == nil {
                        _checkedWithNoResult = true
                    }
                }
                return nil
            }
            lock.withLock { _extrasMenuBar = bar }
            return bar
        }

        /// Resets the negative cache so the app will be re-checked
        /// on the next scan. Called during cleanup to discover apps
        /// that register status items after launch. Preserves a
        /// valid `_extrasMenuBar` to avoid unnecessary AX re-queries.
        func resetNegativeCache() {
            lock.withLock {
                if _extrasMenuBar == nil {
                    _checkedWithNoResult = false
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
    static let shared = SourcePIDCache()

    /// The cache's protected state.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Lock to prevent multiple concurrent full scans of all applications.
    private let scanLock = NSLock()

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
                    result.pids.merge(pids) { _, new in new }
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

        let finalPID = state.withLock { $0.pids[window.windowID] }
        SourcePIDCache.diagLog.debug("SourcePIDCache.pid: batch resolution finished. Found \(totalMatchesFound) matches. Requested windowID \(window.windowID) -> PID \(finalPID.map { "\($0)" } ?? "nil") (checked \(appsChecked) apps, \(appsWithBar) with extras bar, \(totalChildrenChecked) children)")

        return finalPID
    }
}
