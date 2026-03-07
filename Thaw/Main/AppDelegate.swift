//
//  AppDelegate.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState = AppState()

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_: Notification) {
        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager(appState: appState).migrateAll()

        // Register thaw:// URL events early so external tools (e.g. Raycast)
        // can trigger actions without bringing Thaw to the foreground.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Hide the main menu's items to add additional space to the
        // menu bar when we are the focused app.
        for item in NSApp.mainMenu?.items ?? [] {
            item.isHidden = true
        }

        // Allow hiding the mouse while the app is in the background
        // to make menu bar item movement less jarring.
        Bridging.setConnectionProperty(true, forKey: "SetsCursorInBackground")

        #if DEBUG
            // Don't perform setup if running as a preview.
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return
            }
        #endif

        // Warn if another menu bar manager is running.
        ConflictingAppDetector.showWarningIfNeeded()

        // Check if this is the first launch
        let isFirstLaunch = !Defaults.bool(forKey: .hasCompletedFirstLaunch)

        // Depending on the permissions state, either perform setup
        // or prompt to grant permissions.
        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.diagLog.debug("Passed all permissions checks")
            appState.performSetup(hasPermissions: true)
        case .hasRequired:
            appState.permissions.diagLog.debug("Passed required permissions checks")
            appState.performSetup(hasPermissions: true)
        case .missing:
            appState.permissions.diagLog.debug("Failed required permissions checks")
            appState.performSetup(hasPermissions: false)
        }

        // Show permissions window on first launch or if missing required permissions
        if isFirstLaunch || appState.permissions.permissionsState == .missing {
            appState.openWindow(.permissions)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        appState.diagLog.debug("Handling reopen from app icon click")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if sender.isActive, sender.activationPolicy() != .accessory, appState.navigationState.isAppFrontmost {
            appState.diagLog.debug("All windows closed - deactivating with accessory activation policy")
            appState.deactivate(withPolicy: .accessory)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        return true
    }

    // MARK: Other Methods

    /// Handles `kAEGetURL` Apple Events and forwards `thaw://` URLs to `handleURL(_:)`.
    @objc private func handleURLAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "thaw"
        else { return }
        handleURL(url)
    }

    /// Dispatches an incoming `thaw://` URL to the appropriate action.
    ///
    /// Supported URLs:
    /// - `thaw://toggle-hidden` — toggle the hidden menu bar section
    /// - `thaw://toggle-always-hidden` — toggle the always-hidden menu bar section
    /// - `thaw://search` — open the menu bar item search panel
    /// - `thaw://toggle-icebar` — toggle the IceBar on the active display
    /// - `thaw://toggle-application-menus` — toggle application menus
    /// - `thaw://open-settings` — open the Thaw settings window
    private func handleURL(_ url: URL) {
        let host = url.host?.lowercased() ?? ""
        switch host {
        case "toggle-hidden":
            HotkeyAction.toggleHiddenSection.perform(appState: appState)
        case "toggle-always-hidden":
            HotkeyAction.toggleAlwaysHiddenSection.perform(appState: appState)
        case "search":
            HotkeyAction.searchMenuBarItems.perform(appState: appState)
        case "toggle-thawbar":
            HotkeyAction.enableIceBar.perform(appState: appState)
        case "toggle-application-menus":
            HotkeyAction.toggleApplicationMenus.perform(appState: appState)
        case "open-settings":
            openSettingsWindow()
        default:
            appState.diagLog.warning("Received unrecognized thaw:// URL: \(url.absoluteString)")
        }
    }

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        // Always allow opening settings window from menu item clicks
        // This ensures clicking app icon, dock icon or menu bar item works correctly
        appState.diagLog.debug("Opening settings window from app icon/dock/menu click")

        // Delay makes this more reliable for some reason.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [appState] in
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }
}
