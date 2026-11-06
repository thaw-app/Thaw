//
//  RehideController+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import os
import QuartzCore

extension RehideController.Environment {
    /// Reads the live pointer, spaces and windows and hides the app's sections.
    static func live(appState: AppState) -> Self {
        let configuration: any MenuBarEngineConfiguration = appState.settings
        let menuOpenMonitor = appState.itemManager.menuOpenMonitor
        let pointerMonitors = RehidePointerMonitors()
        return Self(
            settings: {
                RehideController.Settings(
                    autoRehide: configuration.autoRehide,
                    strategy: configuration.rehideStrategy,
                    interval: configuration.rehideInterval
                )
            },
            isAnyMenuOpen: { await menuOpenMonitor.isAnyMenuOpen() },
            isPointerAwayFromBars: { [weak appState] in
                guard let appState, let screen = appState.hidEventManager.bestScreen(appState: appState) else {
                    return false
                }
                return !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen)
                    && !appState.hidEventManager.isMouseInsideThawBar(appState: appState)
            },
            activeSpaceID: { Bridging.getActiveSpaceID() },
            isPointerOverFrontmostApp: {
                guard let owner = applicationOwningWindowUnderCursor() else {
                    return false
                }
                // The Dock never becomes the active app, yet clicking it is still a move away from the bar.
                return owner.bundleIdentifier == "com.apple.dock"
                    || (owner.isActive && owner.activationPolicy == .regular)
            },
            hideHiddenSection: { [weak appState] in
                appState?.menuBarManager.section(withName: .hidden)?.hide()
            },
            hideEverySection: { [weak appState] in
                for section in appState?.menuBarManager.sections ?? [] {
                    section.hide()
                }
            },
            isPointerInActiveArea: { [weak appState] in
                guard let appState else { return false }
                let hidEventManager = appState.hidEventManager
                return NSScreen.screens.contains {
                    hidEventManager.isMouseInsideMenuBarHoverBand(appState: appState, screen: $0)
                } || hidEventManager.isMouseInsideThawBar(appState: appState)
            },
            hideSection: { [weak appState] name in
                appState?.menuBarManager.section(withName: name)?.hide()
            },
            startPointerMonitor: pointerMonitors.start,
            stopPointerMonitor: pointerMonitors.stop
        )
    }

    /// Skips the cursor layer and above, and untitled windows such as overlays and shadows.
    private static func applicationOwningWindowUnderCursor() -> NSRunningApplication? {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return nil
        }
        return WindowInfo.createWindows(option: .onScreen)
            .first { window in
                window.layer < CGWindowLevelForKey(.cursorWindow)
                    && window.bounds.contains(mouseLocation)
                    && window.title?.isEmpty == false
            }?
            .owningApplication
    }
}

/// One mouse-moved monitor per section with a timed rehide.
@MainActor
final class RehidePointerMonitors {
    /// Shared by every section's monitor, so one event reaches at most one of them.
    private static let lastTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))

    private var monitors: [MenuBarSection.Name: EventMonitor] = [:]

    func start(_ section: MenuBarSection.Name, onMove: @escaping @MainActor () -> Void) {
        let monitor = EventMonitor.universal(for: .mouseMoved) { event in
            // At most about 20 updates a second, whatever the mouse polling rate.
            let now = CACurrentMediaTime()
            guard now - Self.lastTime.withLock({ $0 }) > 0.05 else { return event }
            Self.lastTime.withLock { $0 = now }
            onMove()
            return event
        }
        monitors[section] = monitor
        monitor.start()
    }

    func stop(_ section: MenuBarSection.Name) {
        monitors[section]?.stop()
        monitors[section] = nil
    }
}
