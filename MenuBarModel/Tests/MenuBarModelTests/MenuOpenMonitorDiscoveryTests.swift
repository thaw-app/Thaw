//
//  MenuOpenMonitorDiscoveryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

/// The test display's menu bar, in window server coordinates. All the synthetic
/// windows that should count hang from it.
private let mainBarStrip = CGRect(x: 0, y: 0, width: 3000, height: 24)

/// A second display's bar, to the right of the first, for the multi-display
/// geometry tests.
private let secondBarStrip = CGRect(x: 3000, y: 0, width: 1920, height: 24)

@Suite("Menu open monitor discovery")
@MainActor
struct MenuOpenMonitorDiscoveryTests {
    @MainActor
    private final class Scene {
        var items: [MenuBarItem] = []
        var windows: [WindowInfo] = []
        var strips: [CGRect] = [mainBarStrip]

        func monitor() -> MenuOpenMonitor {
            MenuOpenMonitor(
                onScreenItems: { self.items },
                cacheFreshness: .zero,
                windowSnapshot: { await self.windows },
                menuBarStrips: { self.strips }
            )
        }
    }

    private func item() -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .null, title: "panel-owner"),
            windowID: 900,
            ownerPID: 123_456,
            sourcePID: 123_456,
            bounds: CGRect(x: 1400, y: 0, width: 24, height: 24),
            title: "panel-owner",
            isOnScreen: true
        )
    }

    private func panel(id: CGWindowID = 11498) -> WindowInfo {
        // Geometry and layer from the read-only Droppy window capture.
        WindowInfo(
            windowID: id,
            ownerPID: 123_456,
            bounds: CGRect(x: 973, y: 0, width: 1062, height: 334),
            layer: 100,
            title: ""
        )
    }

    @Test("Droppy's captured layer-100 overlay does not block re-hiding")
    func droppyOverlayIsNotAMenu() {
        #expect(!MenuOpenMonitor.isCandidateMenuWindow(
            panel(),
            ownerBundleIdentifier: "iordv.Droppy",
            menuBarStrips: [mainBarStrip]
        ))
    }

    @Test("Droppy's standard popup menus still block re-hiding")
    func droppyPopupMenuRemainsProtected() {
        let menu = WindowInfo(
            windowID: 2,
            ownerPID: 123_456,
            bounds: CGRect(x: 1400, y: 24, width: 220, height: 300),
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            title: ""
        )
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            menu,
            ownerBundleIdentifier: "iordv.Droppy",
            menuBarStrips: [mainBarStrip]
        ))
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            panel(),
            ownerBundleIdentifier: "another.app",
            menuBarStrips: [mainBarStrip]
        ))
    }

    /// DockDoor parks a layer-101 popup at (420, 924) for its window previews.
    /// It is nowhere near the menu bar, so it is not somebody's open menu and
    /// must not hold the rehide timer open.
    @Test("A popup parked away from the menu bar is not a menu")
    func popupAwayFromBarIsNotAMenu() {
        let popup = WindowInfo(
            windowID: 5256,
            ownerPID: 7033,
            bounds: CGRect(x: 420, y: 924, width: 331, height: 207),
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            title: ""
        )
        #expect(!MenuOpenMonitor.isCandidateMenuWindow(
            popup,
            ownerBundleIdentifier: "com.ethanbills.DockDoor",
            menuBarStrips: [mainBarStrip]
        ))
    }

    @Test("A menu hanging from the menu bar is a menu")
    func menuHangingFromBarIsAMenu() {
        let menu = WindowInfo(
            windowID: 2,
            ownerPID: 123_456,
            bounds: CGRect(x: 1400, y: 24, width: 220, height: 300),
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            title: ""
        )
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            menu,
            ownerBundleIdentifier: "another.app",
            menuBarStrips: [mainBarStrip]
        ))
    }

    @Test("A menu on the second display's bar is a menu")
    func menuOnSecondDisplayBarIsAMenu() {
        let menu = WindowInfo(
            windowID: 3,
            ownerPID: 123_456,
            bounds: CGRect(x: 3100, y: 24, width: 220, height: 300),
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            title: ""
        )
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            menu,
            ownerBundleIdentifier: "another.app",
            menuBarStrips: [mainBarStrip, secondBarStrip]
        ))
        // The same kind of popup parked low on the second display must not
        // borrow the bar above it.
        let away = WindowInfo(
            windowID: 4,
            ownerPID: 123_456,
            bounds: CGRect(x: 3100, y: 924, width: 331, height: 207),
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            title: ""
        )
        #expect(!MenuOpenMonitor.isCandidateMenuWindow(
            away,
            ownerBundleIdentifier: "another.app",
            menuBarStrips: [mainBarStrip, secondBarStrip]
        ))
    }

    /// The reveal mask: Thaw's own window over the whole bar at menu level.
    /// Counting it made the prewarm that raised it wait for itself.
    private func revealMask(id: CGWindowID = 3752) -> WindowInfo {
        WindowInfo(
            windowID: id,
            ownerPID: 123_456,
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 40),
            layer: 25,
            title: ""
        )
    }

    @Test("A registered Thaw overlay does not block re-hiding")
    func registeredOverlayIsNotAMenu() {
        let mask = revealMask()
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            mask,
            ownerBundleIdentifier: "com.stonerl.Thaw",
            menuBarStrips: [mainBarStrip],
            overlayWindowIDs: []
        ))
        #expect(!MenuOpenMonitor.isCandidateMenuWindow(
            mask,
            ownerBundleIdentifier: "com.stonerl.Thaw",
            menuBarStrips: [mainBarStrip],
            overlayWindowIDs: [mask.windowID]
        ))
    }

    /// The general rule: an unregistered panel of ours at menu-bar level is
    /// still not a menu. An unregistered tooltip at layer 25 would otherwise
    /// hold the prewarm open.
    @Test("An unregistered overlay of ours at menu-bar level is not a menu")
    func ownMenuBarLevelWindowIsNotAMenu() {
        let tooltip = WindowInfo(
            windowID: 5061,
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            bounds: CGRect(x: 2400, y: 30, width: 160, height: 58),
            layer: 25,
            title: ""
        )
        #expect(!MenuOpenMonitor.isCandidateMenuWindow(
            tooltip,
            ownerBundleIdentifier: "com.stonerl.Thaw",
            menuBarStrips: [mainBarStrip],
            overlayWindowIDs: []
        ))
    }

    /// Our own popup-level menu still counts, or concealment would fire while
    /// the user has our status menu open.
    @Test("Our own popup-level menu still blocks re-hiding")
    func ownPopupMenuIsStillAMenu() {
        let menu = WindowInfo(
            windowID: 5062,
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            bounds: CGRect(x: 2400, y: 30, width: 220, height: 300),
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            title: ""
        )
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            menu,
            ownerBundleIdentifier: "com.stonerl.Thaw",
            menuBarStrips: [mainBarStrip],
            overlayWindowIDs: []
        ))
    }

    /// Thaw's status item has a real menu, so registering the overlays must not
    /// stop Thaw's own menus registering as open.
    @Test("An unregistered Thaw window still blocks re-hiding")
    func unregisteredThawMenuIsStillAMenu() {
        let menu = WindowInfo(
            windowID: 4096,
            ownerPID: 123_456,
            bounds: CGRect(x: 1400, y: 24, width: 220, height: 300),
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            title: ""
        )
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            menu,
            ownerBundleIdentifier: "com.stonerl.Thaw",
            menuBarStrips: [mainBarStrip],
            overlayWindowIDs: [revealMask().windowID]
        ))
    }

    /// Window numbers are recycled, so a stale registration would silence a
    /// real menu that later takes the same ID.
    @Test("Unregistering restores the window")
    func unregisteringRestoresTheWindow() {
        let mask = revealMask(id: 5150)
        MenuBarOverlayWindows.register(mask.windowID)
        #expect(MenuBarOverlayWindows.current.contains(mask.windowID))
        MenuBarOverlayWindows.unregister(mask.windowID)
        #expect(!MenuBarOverlayWindows.current.contains(mask.windowID))
        #expect(MenuOpenMonitor.isCandidateMenuWindow(
            mask,
            ownerBundleIdentifier: "com.stonerl.Thaw",
            menuBarStrips: [mainBarStrip]
        ))
    }

    @Test("Discovering an owner does not turn its existing panel into an open menu")
    func discoveryDoesNotOpenExistingPanel() async {
        let scene = Scene()
        scene.windows = [panel()]
        let monitor = scene.monitor()
        #expect(await monitor.isAnyMenuOpen() == false)

        scene.items = [item()]
        for _ in 0 ..< 125 {
            #expect(await monitor.isAnyMenuOpen() == false)
        }
    }

    @Test("A cache gap does not turn a persistent panel into an open menu")
    func cacheGapDoesNotOpenExistingPanel() async {
        let scene = Scene()
        scene.windows = [panel()]
        scene.items = [item()]
        let monitor = scene.monitor()
        #expect(await monitor.isAnyMenuOpen() == false)

        scene.items = []
        #expect(await monitor.isAnyMenuOpen() == false)
        scene.items = [item()]
        #expect(await monitor.isAnyMenuOpen() == false)
    }

    @Test("A window from an unknown owner does not block re-hiding")
    func unrelatedWindowDoesNotOpenMenu() async {
        let scene = Scene()
        let monitor = scene.monitor()
        #expect(await monitor.isAnyMenuOpen() == false)
        scene.windows = [panel()]
        #expect(await monitor.isAnyMenuOpen() == false)
    }

    @Test("A popup away from the menu bar never reads as an open menu")
    func popupAwayFromBarNeverOpensMenu() async {
        let scene = Scene()
        scene.items = [item()]
        scene.windows = [
            WindowInfo(
                windowID: 5256,
                ownerPID: 123_456,
                bounds: CGRect(x: 420, y: 924, width: 331, height: 207),
                layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                title: ""
            ),
        ]
        let monitor = scene.monitor()
        #expect(await monitor.isAnyMenuOpen() == false)
        // The popup belongs to the discovered owner, so only the geometry
        // keeps it from reading as a menu across every poll.
        for _ in 0 ..< 5 {
            #expect(await monitor.isAnyMenuOpen() == false)
        }
    }

    @Test("An open menu stays protected across an item-cache gap")
    func openMenuSurvivesCacheGap() async {
        let scene = Scene()
        scene.items = [item()]
        let monitor = scene.monitor()
        #expect(await monitor.isAnyMenuOpen() == false)
        scene.windows = [panel(id: 2)]
        #expect(await monitor.isAnyMenuOpen())

        scene.items = []
        #expect(await monitor.isAnyMenuOpen())
        scene.windows = []
        #expect(await monitor.isAnyMenuOpen() == false)
    }

    @Test("A new menu from a discovered owner remains open until its window closes")
    func realMenuLifecycleAfterDiscovery() async {
        let scene = Scene()
        scene.windows = [panel()]
        let monitor = scene.monitor()
        #expect(await monitor.isAnyMenuOpen() == false)
        scene.items = [item()]
        #expect(await monitor.isAnyMenuOpen() == false)

        scene.windows.append(panel(id: 2))
        for _ in 0 ..< 5 {
            #expect(await monitor.isAnyMenuOpen())
        }
        scene.windows.removeLast()
        #expect(await monitor.isAnyMenuOpen() == false)
        scene.windows.append(panel(id: 2))
        #expect(await monitor.isAnyMenuOpen())
    }
}
