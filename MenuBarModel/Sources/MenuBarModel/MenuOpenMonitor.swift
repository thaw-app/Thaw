//
//  MenuOpenMonitor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation

/// Caches both probe results and joins in-flight work off the main actor so window-server stalls do not block it.
/// Shared by engine and frontend, with inventory supplied by closure; only newly appearing windows become menus, tracked until disappearance.
@MainActor
public final class MenuOpenMonitor {
    private static nonisolated let diagLog = DiagLog(category: "MenuOpenMonitor")

    /// Cache negative answers too: rehide polls at 4 Hz, and each uncached result costs a window enumeration.
    private let cacheFreshness: Duration

    /// Allow attachment slack for menu shadows and rounded edges.
    private static nonisolated let menuBarAttachmentSlack: CGFloat = 8

    private let onScreenItems: @MainActor () -> [MenuBarItem]
    private let windowSnapshot: @Sendable () async -> [WindowInfo]
    private let menuBarStrips: @MainActor () -> [CGRect]

    private var checkTask: Task<Bool, Never>?
    private var cachedResult: Bool?
    private var cachedAt: ContinuousClock.Instant?

    /// Previous candidates include unknown owners, so discovery cannot turn an existing banner into a menu.
    /// Seeded on the first probe and reconciled on the main actor as monitor state.
    private var priorCandidateWindowIDs: Set<CGWindowID> = []

    /// Only new windows of known owners enter; tracked menus survive item-cache gaps until their windows disappear.
    private var openMenuWindowIDs: Set<CGWindowID> = []

    /// The owning process of each candidate window in the last probe.
    private var candidateOwnerPIDs: [CGWindowID: pid_t] = [:]

    /// The first probe seeds the baseline rather than treating every existing candidate as new.
    private var hasBaseline = false

    public convenience init(onScreenItems: @escaping @MainActor () -> [MenuBarItem]) {
        self.init(
            onScreenItems: onScreenItems,
            cacheFreshness: .milliseconds(250),
            windowSnapshot: { await Self.readOnScreenWindows() },
            menuBarStrips: { Self.liveMenuBarStrips() }
        )
    }

    init(
        onScreenItems: @escaping @MainActor () -> [MenuBarItem],
        cacheFreshness: Duration,
        windowSnapshot: @escaping @Sendable () async -> [WindowInfo],
        menuBarStrips: @escaping @MainActor () -> [CGRect]
    ) {
        self.onScreenItems = onScreenItems
        self.cacheFreshness = cacheFreshness
        self.windowSnapshot = windowSnapshot
        self.menuBarStrips = menuBarStrips
    }

    /// Cancels any in-flight probe. Called on teardown paths.
    public func cancel() {
        checkTask?.cancel()
        checkTask = nil
    }

    public func isAnyMenuOpen() async -> Bool {
        if let cachedAt,
           let cachedResult,
           cachedAt.duration(to: .now) <= cacheFreshness
        {
            Self.diagLog.debug("Menu open check: using cached result \(cachedResult)")
            return cachedResult
        }

        if let existingTask = checkTask {
            Self.diagLog.debug("Menu open check: joining in-flight probe")
            return await existingTask.value
        }

        let cachedItems = onScreenItems()
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description
        let strips = menuBarStrips()

        let task = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return false }
            let candidates = await Self.candidateMenuWindows(
                cachedItems: cachedItems,
                controlCenterBundleID: controlCenterBundleID,
                menuBarStrips: strips,
                windowSnapshot: self.windowSnapshot
            )
            self.candidateOwnerPIDs = candidates.ownerPIDs
            return self.reconcileAgainstBaseline(candidates: (candidates.allIDs, candidates.ownedIDs))
        }

        checkTask = task
        let result = await task.value
        checkTask = nil
        cachedResult = result
        cachedAt = ContinuousClock.now
        return result
    }

    /// Whether one of these processes has a menu open. Another app's menu does
    /// not count, so a window that never closes cannot hold someone else's item.
    public func isMenuOpen(ownedBy pids: Set<pid_t>) async -> Bool {
        guard await isAnyMenuOpen() else { return false }
        return openMenuWindowIDs.contains { candidateOwnerPIDs[$0].map(pids.contains) == true }
    }

    @concurrent
    private static nonisolated func readOnScreenWindows() async -> [WindowInfo] {
        WindowInfo.createWindows(option: .onScreen)
    }

    /// NSScreen's full-minus-visible height gives the bar strip; CGDisplayBounds anchors it in top-left window-server coordinates.
    @MainActor
    private static func liveMenuBarStrips() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else {
                return nil
            }
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            guard menuBarHeight > 0 else { return nil }
            let displayFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            return CGRect(
                x: displayFrame.minX,
                y: displayFrame.minY,
                width: displayFrame.width,
                height: menuBarHeight
            )
        }
    }

    /// Menus hang from the bar's bottom edge within attachment slack; desktop popups such as DockDoor previews do not count.
    /// Panels reaching through the bar from above need separate exclusions.
    private static nonisolated func touchesMenuBar(_ bounds: CGRect, strips: [CGRect]) -> Bool {
        strips.contains { strip in
            let reachesBelowBar = bounds.maxY > strip.maxY
            let startsAtOrAboveBarBottom = bounds.minY <= strip.maxY + menuBarAttachmentSlack
            let overlapsHorizontally = bounds.maxX > strip.minX && bounds.minX < strip.maxX
            return reachesBelowBar && startsAtOrAboveBarBottom && overlapsHorizontally
        }
    }

    static nonisolated func isCandidateMenuWindow(
        _ window: WindowInfo,
        ownerBundleIdentifier: String?,
        menuBarStrips: [CGRect],
        overlayWindowIDs: Set<CGWindowID> = MenuBarOverlayWindows.current
    ) -> Bool {
        // Counting Thaw's menu-level reveal overlays would make conceal wait on itself; see MenuBarOverlayWindows.
        guard !overlayWindowIDs.contains(window.windowID) else { return false }

        // Exclude unregistered Thaw overlays at menu-bar level; real NSMenus sit at popup level.
        if window.ownerPID == ProcessInfo.processInfo.processIdentifier,
           window.layer < Int(CGWindowLevelForKey(.popUpMenuWindow))
        {
            return false
        }

        guard window.isMenuRelated, window.title?.isEmpty ?? true,
              ownerBundleIdentifier != MenuBarItemTag.Namespace.controlCenter.description
        else { return false }

        // Droppy's persistent notch/HUD surface was captured at layer 100.
        // Keep the standard popup-menu level (101) eligible.
        if ownerBundleIdentifier == "iordv.Droppy",
           window.layer == Int(CGWindowLevelForKey(.popUpMenuWindow) - 1)
        {
            return false
        }

        // Only a window that touches a menu bar is somebody's open menu;
        // a menu-level popup parked elsewhere on the desktop is not.
        return touchesMenuBar(window.bounds, strips: menuBarStrips)
    }

    /// Probes captured inputs off the main actor to avoid window-server stalls.
    /// Returns all candidates for the baseline and known-owner candidates eligible to open a menu.
    @concurrent
    private static nonisolated func candidateMenuWindows(
        cachedItems: [MenuBarItem],
        controlCenterBundleID: String,
        menuBarStrips: [CGRect],
        windowSnapshot: @Sendable () async -> [WindowInfo]
    ) async -> (allIDs: Set<CGWindowID>, ownedIDs: Set<CGWindowID>, ownerPIDs: [CGWindowID: pid_t]) {
        let windows = await windowSnapshot()
        let potentialMenuWindows = windows.filter { window in
            guard window.isMenuRelated else { return false }
            return isCandidateMenuWindow(
                window,
                ownerBundleIdentifier: window.owningApplication?.bundleIdentifier,
                menuBarStrips: menuBarStrips
            )
        }

        guard !potentialMenuWindows.isEmpty else {
            diagLog.debug(
                "Menu open check: no candidate menu windows on screen"
            )
            return ([], [], [:])
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

        diagLog.debug(
            """
            Checking for open menus - fast path with \(cachedItems.count) cached menu bar items, \
            \(fastPathPIDs.count) candidate PIDs, \(potentialMenuWindows.count) candidate menu windows
            """
        )

        let owned = potentialMenuWindows.filter { window in
            fastPathPIDs.contains(window.ownerPID)
        }

        for window in owned {
            diagLog.debug(
                """
                Found candidate menu window: id=\(window.windowID), PID \(window.ownerPID), \
                owner: \(window.ownerName as NSObject?), layer=\(window.layer), bounds=\(window.bounds)
                """
            )
        }
        return (
            Set(potentialMenuWindows.map(\.windowID)),
            Set(owned.map(\.windowID)),
            Dictionary(potentialMenuWindows.map { ($0.windowID, $0.ownerPID) }) { first, _ in first }
        )
    }

    /// New eligible windows enter the open set; baseline banners do not, and tracked menus remain until disappearance.
    /// Refreshing the baseline allows closed windows to be detected again when reopened.
    @MainActor
    private func reconcileAgainstBaseline(candidates: (allIDs: Set<CGWindowID>, ownedIDs: Set<CGWindowID>)) -> Bool {
        return Self.reconcile(
            currentIDs: candidates.allIDs,
            eligibleIDs: candidates.ownedIDs,
            hasBaseline: &hasBaseline,
            priorCandidateWindowIDs: &priorCandidateWindowIDs,
            openMenuWindowIDs: &openMenuWindowIDs
        )
    }

    /// Pure reconciliation of the persistence baseline, split out so the logic
    /// can be exercised without a live window server.
    ///
    /// - Returns: whether any genuinely-open menu window is currently on
    ///   screen.
    @MainActor
    static func reconcile(
        currentIDs: Set<CGWindowID>,
        eligibleIDs: Set<CGWindowID>,
        hasBaseline: inout Bool,
        priorCandidateWindowIDs: inout Set<CGWindowID>,
        openMenuWindowIDs: inout Set<CGWindowID>
    ) -> Bool {
        if !hasBaseline {
            // Seed existing windows as persistent so preexisting menus and banners do not count.
            hasBaseline = true
            priorCandidateWindowIDs = currentIDs
            diagLog.debug(
                "Menu open check: seeded baseline with \(currentIDs.count) persistent window(s)"
            )
            return false
        }

        // Owner discovery (or a concealed item returning to the cache) is not
        // evidence that a window opened. Only a new window can enter the set.
        let newlyOpened = eligibleIDs.subtracting(priorCandidateWindowIDs)
        openMenuWindowIDs = openMenuWindowIDs.intersection(currentIDs)
            .union(newlyOpened)
        priorCandidateWindowIDs = currentIDs

        if openMenuWindowIDs.isEmpty {
            diagLog.debug(
                "Menu open check result: false (fast path); \(currentIDs.count) persistent window(s) filtered"
            )
            return false
        }

        diagLog.debug(
            "Menu open check result: true (fast path); \(openMenuWindowIDs.count) open window(s), \(newlyOpened.count) newly-appeared"
        )
        return true
    }
}
