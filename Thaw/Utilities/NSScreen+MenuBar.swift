//
//  NSScreen+MenuBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import os.lock
import SwiftUI

extension NSScreen {
    private static nonisolated let diagLog = DiagLog(category: "NSScreen")

    /// The screen the pointer is currently over.
    static var screenWithMouse: NSScreen? {
        screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    /// The screen whose menu bar is currently the active one.
    static var screenWithActiveMenuBar: NSScreen? {
        guard let activeDisplayID = Bridging.getActiveMenuBarDisplayID() else {
            return nil
        }
        return screen(for: activeDisplayID)
    }

    /// The connected screen for a display, or nil when it is not connected.
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    /// The screen whose display contains point, in Core Graphics global
    /// coordinates (top-left origin).
    static func screen(containingCGPoint point: CGPoint) -> NSScreen? {
        screens.first { CGDisplayBounds($0.displayID).contains(point) }
    }

    /// Every connected display's bounds, in Core Graphics global coordinates.
    static var allDisplayBoundsCG: [CGRect] {
        screens.map { CGDisplayBounds($0.displayID) }
    }

    /// The connected screens that Thaw manages per-display state for (its
    /// Displays settings, overlay panels, average-color capture, screen-count
    /// logic).
    static var managedScreens: [NSScreen] {
        screens
    }

    /// A screen held across a topology change must not schedule retries for
    /// a display that will never grow a menu bar window again.
    static nonisolated func isDisplayActive(_ displayID: CGDirectDisplayID) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else {
            // Enumeration failed: assume the display is there, or a legitimate
            // retry would be suppressed.
            return true
        }
        return (0 ..< Int(count)).contains { ids[$0] == displayID }
    }

    var displayID: CGDirectDisplayID {
        // A guard rather than a force cast, so a broken AppKit contract names itself.
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            preconditionFailure("NSScreenNumber missing or not a display ID")
        }
        return displayID
    }

    /// Whether this screen has a notch cut into its menu bar.
    var hasNotch: Bool {
        guard !UserDefaults.standard.bool(forKey: Defaults.Key.debugSimulateNotch.rawValue) else {
            return true
        }
        return auxiliaryTopLeftArea != nil
    }

    /// The rectangle the screen's notch occupies, or nil when it has none.
    var frameOfNotch: CGRect? {
        guard let leftOfNotch = auxiliaryTopLeftArea, let rightOfNotch = auxiliaryTopRightArea else {
            guard UserDefaults.standard.bool(forKey: Defaults.Key.debugSimulateNotch.rawValue) else {
                return nil
            }
            let notchWidth: CGFloat = 120
            let notchHeight = safeAreaInsets.top > 0 ? safeAreaInsets.top : NSStatusBar.system.thickness
            return CGRect(
                x: frame.midX - (notchWidth / 2),
                y: frame.maxY - notchHeight,
                width: notchWidth,
                height: notchHeight
            )
        }
        return CGRect(
            x: leftOfNotch.maxX,
            y: frame.maxY - safeAreaInsets.top,
            width: rightOfNotch.minX - leftOfNotch.maxX,
            height: safeAreaInsets.top
        )
    }

    private nonisolated struct DisplayCache {
        var menuFrames = [CGDirectDisplayID: CGRect]()
        var menuFramePID: pid_t?
        var menuBarHeights = [CGDirectDisplayID: CGFloat]()
    }

    private static nonisolated let displayCache = OSAllocatedUnfairLock(initialState: DisplayCache())

    private static func invalidateApplicationMenuFrameCacheIfNeeded() {
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        displayCache.withLock { cache in
            if currentPID != cache.menuFramePID {
                cache.menuFrames.removeAll()
                cache.menuFramePID = currentPID
            }
        }
    }

    /// The tallest live menu bar height cached for any display, readable off the
    /// main actor. Nil until getMenuBarHeight() has read one.
    static nonisolated var tallestCachedMenuBarHeight: CGFloat? {
        displayCache.withLock { $0.menuBarHeights.values.max() }
    }

    static func invalidateMenuBarHeightCache() {
        displayCache.withLock { $0.menuBarHeights.removeAll() }
    }

    /// Reconnected displays get new IDs, so stale entries would pile up.
    static func cleanupDisconnectedDisplayCaches() {
        let connectedDisplayIDs = Set(NSScreen.managedScreens.map(\.displayID))
        displayCache.withLock { cache in
            cache.menuBarHeights = cache.menuBarHeights.filter { connectedDisplayIDs.contains($0.key) }
            cache.menuFrames = cache.menuFrames.filter { connectedDisplayIDs.contains($0.key) }
        }
        pendingRetryDisplays.withLock { $0 = $0.filter { connectedDisplayIDs.contains($0) } }
    }

    private static nonisolated let pendingRetryDisplays = OSAllocatedUnfairLock(initialState: Set<CGDirectDisplayID>())

    /// One pending retry per display, for when the Menubar window is not yet
    /// listed, such as at startup.
    private static func scheduleMenuBarHeightRetry(for displayID: CGDirectDisplayID) {
        // A disconnected display never grows a menu bar window.
        guard isDisplayActive(displayID) else { return }
        let shouldSchedule = pendingRetryDisplays.withLock { $0.insert(displayID).inserted }
        guard shouldSchedule else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(500)) {
            if let menuBarWindow = WindowInfo.menuBarWindow(for: displayID) {
                let height = menuBarWindow.bounds.height
                if height > 0 {
                    NSScreen.displayCache.withLock { $0.menuBarHeights[displayID] = height }
                    NSScreen.diagLog.debug("getMenuBarHeight: retry succeeded for display=\(displayID) height=\(Double(height))")
                }
            }
            _ = pendingRetryDisplays.withLock { $0.remove(displayID) }
        }
    }

    /// Cached per display. With no Menubar window yet, returns nil and
    /// schedules a retry rather than caching a sentinel.
    func getMenuBarHeight() -> CGFloat? {
        let id = displayID
        if let cached = NSScreen.displayCache.withLock({ $0.menuBarHeights[id] }), cached > 0 {
            return cached
        }
        // A display that is gone gets no warning or retry; those are for startup.
        guard NSScreen.isDisplayActive(id) else {
            return nil
        }
        guard let menuBarWindow = WindowInfo.menuBarWindow(for: id) else {
            Self.diagLog.warning("getMenuBarHeight: display=\(id) no menu bar window found, scheduling retry")
            NSScreen.scheduleMenuBarHeightRetry(for: id)
            return nil
        }
        let height = menuBarWindow.bounds.height
        guard height > 0 else {
            Self.diagLog.warning("getMenuBarHeight: display=\(id) menu bar window has zero height, scheduling retry")
            NSScreen.scheduleMenuBarHeightRetry(for: id)
            return nil
        }
        NSScreen.displayCache.withLock { $0.menuBarHeights[id] = height }
        Self.diagLog.debug("getMenuBarHeight: display=\(id) liveHeight=\(Double(height)) windowID=\(menuBarWindow.windowID)")
        return height
    }

    /// The live height, else the cached one, else a notch-aware estimate.
    func getMenuBarHeightEstimate() -> CGFloat {
        if let live = getMenuBarHeight() {
            Self.diagLog.debug("getMenuBarHeightEstimate: display=\(displayID) live=\(Double(live))")
            return live
        }
        let id = displayID
        if let cached = NSScreen.displayCache.withLock({ $0.menuBarHeights[id] }), cached > 0 {
            Self.diagLog.debug("getMenuBarHeightEstimate: display=\(id) cacheHit=\(Double(cached))")
            return cached
        }
        // Notched bars are about 37 pt; others use the status bar thickness.
        let fallback = hasNotch ? 37.0 : NSStatusBar.system.thickness
        Self.diagLog.notice("getMenuBarHeightEstimate: display=\(displayID) FALLBACK hasNotch=\(hasNotch) fallback=\(Double(fallback))")
        return fallback
    }

    /// False while the bar is auto-hidden behind a fullscreen app.
    func isSystemMenuBarVisible() -> Bool {
        // macOS 27 has no status-item windows, so an .itemsOnly list is always
        // empty. The bar window's on-screen state still tracks fullscreen auto-hide.
        return !Bridging.getMenuBarWindowList(option: [.onScreen]).isEmpty
    }

    /// The application menu frame from AX, not notch-capped. Cached per display
    /// until the frontmost app changes.
    ///
    /// - Parameter bypassCache: Always query AX; use when polling for changes.
    func getApplicationMenuFrame(bypassCache: Bool = false) -> CGRect? {
        NSScreen.invalidateApplicationMenuFrameCacheIfNeeded()
        let id = displayID
        if !bypassCache, let cached = NSScreen.displayCache.withLock({ $0.menuFrames[id] }) {
            return cached
        }

        let result = computeApplicationMenuFrame()
        if !bypassCache, let result {
            NSScreen.displayCache.withLock { $0.menuFrames[id] = result }
        }
        return result
    }

    private func computeApplicationMenuFrame() -> CGRect? {
        // Treat the degenerate no-main-screen case like the main screen.
        let isMainScreen = NSScreen.main.map { self == $0 } ?? true

        if let menuFrame = axApplicationMenuFrame(allowOwnerFallback: isMainScreen) {
            // AX may report display-local coordinates; anchor to this screen's
            // global origin to match status-item bounds.
            return CGRect(x: frame.minX, y: menuFrame.minY, width: menuFrame.width, height: menuFrame.height)
        }

        // AX often reports nothing for secondary screens; borrow the main
        // screen's menu width.
        guard !isMainScreen, let mainFrame = NSScreen.main?.getApplicationMenuFrame() else {
            return nil
        }
        return CGRect(x: frame.minX, y: mainFrame.minY, width: mainFrame.width, height: mainFrame.height)
    }

    /// The frame union of the menu bar's app-menu children on this screen,
    /// found through an AX hit test at the display origin.
    ///
    /// - Parameter allowOwnerFallback: Whether a failed hit test may fall back
    ///   to the menu bar owner's AX tree, which only describes the main display.
    private func axApplicationMenuFrame(allowOwnerFallback: Bool) -> CGRect? {
        var menuBar = AXHelpers.element(at: CGDisplayBounds(displayID).origin).flatMap { element in
            AXHelpers.roleString(for: element) == kAXMenuBarRole ? element : nil
        }
        if menuBar == nil, allowOwnerFallback {
            menuBar = NSWorkspace.shared.menuBarOwningApplication
                .flatMap(AXHelpers.application(for:))
                .flatMap(AXHelpers.menuBar(for:))
        }
        guard let menuBar else {
            return nil
        }

        let menuFrame = AXHelpers.applicationMenuChildFrameUnion(for: menuBar)
        guard !menuFrame.isNull, menuFrame.width > 0 else {
            return nil
        }
        return menuFrame
    }
}
