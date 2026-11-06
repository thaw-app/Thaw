//
//  RehideController+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

extension RehideController.Environment {
    /// Reads the live pointer, spaces and windows and hides the app's sections.
    static func live(appState: AppState) -> Self {
        let configuration: any MenuBarEngineConfiguration = appState.settings
        let menuOpenMonitor = appState.itemManager.menuOpenMonitor
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
            }
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
