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
    private var isPreparingForTermination = false
    private var hasRepliedToTerminationRequest = false
    private var terminationAttemptID = UUID()
    private var terminationTimeoutTask: Task<Void, Never>?

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_: Notification) {
        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager(appState: appState).migrateAll()

        // Register thaw:// URL events early so external tools (e.g. Raycast)
        // can trigger actions even when Thaw is not currently in the foreground;
        // depending on the action, the app may still be activated as needed.
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingForTermination else {
            return .terminateLater
        }

        let attemptID = UUID()
        terminationAttemptID = attemptID
        terminationTimeoutTask?.cancel()
        isPreparingForTermination = true
        hasRepliedToTerminationRequest = false
        appState.diagLog.info("Application asked to terminate - restoring blocked items asynchronously")

        Task { @MainActor in
            _ = await appState.itemManager.restoreBlockedItemsToVisible()
            guard terminationAttemptID == attemptID else {
                return
            }
            terminationTimeoutTask?.cancel()
            replyToTerminationRequest(sender, timedOut: false)
        }

        terminationTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard terminationAttemptID == attemptID else {
                return
            }
            replyToTerminationRequest(sender, timedOut: true)
        }

        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        appState.diagLog.info("Application will terminate")
    }

    // MARK: Other Methods

    /// Handles `kAEGetURL` Apple Events and forwards `thaw://` URLs to `handleURL(_:senderBundleId:)`.
    @objc private func handleURLAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "thaw"
        else { return }

        // Extract sender bundle ID from the Apple Event
        let senderBundleId = extractSenderBundleId(from: event)
        handleURL(url, senderBundleId: senderBundleId)
    }

    /// Extracts the sender's bundle identifier from an Apple Event.
    private func extractSenderBundleId(from event: NSAppleEventDescriptor) -> String? {
        // Try to get the sender's process ID from the event attributes
        // keySenderPID is the attribute keyword for sender's process ID
        let keySenderPID = AEKeyword(keySenderPIDAttr)

        guard let pidDesc = event.attributeDescriptor(forKeyword: keySenderPID),
              pidDesc.descriptorType == typeSInt32 || pidDesc.descriptorType == typeSInt64
        else {
            return nil
        }

        let pid = pidDesc.int32Value

        // Get the running application
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
            return nil
        }

        return app.bundleIdentifier
    }

    /// Dispatches an incoming `thaw://` URL to the appropriate action.
    ///
    /// Supported Action URLs:
    /// - `thaw://toggle-hidden` — toggle the hidden menu bar section
    /// - `thaw://toggle-always-hidden` — toggle the always-hidden menu bar section
    /// - `thaw://search` — open the menu bar item search panel
    /// - `thaw://toggle-thawbar` — toggle the IceBar on the active display
    /// - `thaw://toggle-application-menus` — toggle application menus
    /// - `thaw://open-settings` — open the Thaw settings window
    ///
    /// Supported Settings URLs (requires whitelist authorization):
    /// - `thaw://set?key=X&value=Y` — set a boolean setting
    /// - `thaw://toggle?key=X` — toggle a boolean setting
    private func handleURL(_ url: URL, senderBundleId: String? = nil) {
        let host = url.host?.lowercased() ?? ""

        // Handle settings manipulation URLs
        switch host {
        case "set", "toggle", "get":
            handleSettingsURL(url, host: host, senderBundleId: senderBundleId)
            return
        default:
            break
        }

        // Handle action URLs
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

    /// Handles settings manipulation URLs (set/toggle).
    private func handleSettingsURL(_ url: URL, host: String, senderBundleId: String?) {
        // Check if Settings URI feature is enabled
        guard SettingsURIHandler.isEnabled() else {
            appState.diagLog.debug("Settings URI is disabled, ignoring: \(url.absoluteString)")
            return
        }

        // Determine effective bundle ID (auto-detected or manual override)
        guard let effectiveBundleId = determineEffectiveBundleId(url: url, senderBundleId: senderBundleId) else {
            appState.diagLog.debug("Settings URI: Cannot determine sender bundle ID, ignoring: \(url.absoluteString)")
            return
        }

        // Verify sender is whitelisted, or prompt for first-time authorization
        if !SettingsURIHandler.isWhitelisted(bundleIdentifier: effectiveBundleId) {
            // Show confirmation dialog
            let approved = SettingsURIHandler.promptForAuthorization(bundleId: effectiveBundleId)
            guard approved else {
                // Unauthorized - silent fail
                return
            }
        }

        // Process the settings URL
        switch host {
        case "set":
            handleSetURL(url, sender: effectiveBundleId)
        case "toggle":
            handleToggleURL(url, sender: effectiveBundleId)
        case "get":
            handleGetURL(url, sender: effectiveBundleId)
        default:
            break
        }
    }

    /// Determines the effective bundle ID for authorization.
    /// Uses manual override (DEBUG only) if auto-detection fails.
    private func determineEffectiveBundleId(url: URL, senderBundleId: String?) -> String? {
        // If we have auto-detected sender, use it
        if let sender = senderBundleId {
            return sender
        }

        #if DEBUG
            // In DEBUG builds, allow manual bundleId override for testing
            // when auto-detection fails (e.g., from Terminal 'open' command)
            if let manualBundleId = extractManualBundleId(from: url) {
                appState.diagLog.warning("Settings URI: Using DEBUG manual bundleId=\(manualBundleId) - FOR TESTING ONLY")
                return manualBundleId
            }
        #endif

        return nil
    }

    private func replyToTerminationRequest(
        _ sender: NSApplication,
        timedOut: Bool
    ) {
        guard !hasRepliedToTerminationRequest else {
            return
        }

        hasRepliedToTerminationRequest = true
        isPreparingForTermination = false
        terminationTimeoutTask?.cancel()
        terminationTimeoutTask = nil

        if timedOut {
            appState.diagLog.warning("Blocked item restore operation timed out during app termination")
        } else {
            appState.diagLog.info("Blocked item restore operation completed during app termination")
        }

        sender.reply(toApplicationShouldTerminate: true)
    }

    #if DEBUG
        /// Extracts manual bundleId from URL query parameter (DEBUG builds only).
        private func extractManualBundleId(from url: URL) -> String? {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let bundleId = components.queryItems?.first(where: { $0.name == "bundleId" })?.value,
                  !bundleId.isEmpty
            else {
                return nil
            }
            return bundleId
        }
    #endif

    /// Handles thaw://set?key=X&value=Y URL.
    private func handleSetURL(_ url: URL, sender: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let key = components.queryItems?.first(where: { $0.name == "key" })?.value,
              let value = components.queryItems?.first(where: { $0.name == "value" })?.value
        else {
            appState.diagLog.warning("Settings URI set: missing key or value in \(url.absoluteString)")
            return
        }

        // Extract optional display UUID parameter for per-display settings
        let displayUUID = components.queryItems?.first(where: { $0.name == "display" })?.value

        let success = SettingsURIHandler.handleSet(key: key, value: value, sender: sender, displayUUID: displayUUID)
        if !success {
            appState.diagLog.warning("Settings URI set: failed to set \(key) = \(value)")
        }
    }

    /// Handles thaw://toggle?key=X URL.
    private func handleToggleURL(_ url: URL, sender: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let key = components.queryItems?.first(where: { $0.name == "key" })?.value
        else {
            appState.diagLog.warning("Settings URI toggle: missing key in \(url.absoluteString)")
            return
        }

        // Extract optional display UUID parameter for per-display settings
        let displayUUID = components.queryItems?.first(where: { $0.name == "display" })?.value

        let success = SettingsURIHandler.handleToggle(key: key, sender: sender, displayUUID: displayUUID)
        if !success {
            appState.diagLog.warning("Settings URI toggle: failed to toggle \(key)")
        }
    }

    /// Handles thaw://get?key=X&callback=Y URLs.
    private func handleGetURL(_ url: URL, sender _: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            appState.diagLog.warning("Settings URI get: invalid URL \(url.absoluteString)")
            return
        }

        // Extract parameters
        let key = components.queryItems?.first(where: { $0.name == "key" })?.value
        let displayUUID = components.queryItems?.first(where: { $0.name == "display" })?.value
        let callback = components.queryItems?.first(where: { $0.name == "callback" })?.value
        let broadcast = components.queryItems?.first(where: { $0.name == "broadcast" })?.value == "true"
        let requestId = components.queryItems?.first(where: { $0.name == "requestId" })?.value

        let success = SettingsURIHandler.handleGet(
            key: key,
            displayUUID: displayUUID,
            callback: callback,
            broadcast: broadcast,
            requestId: requestId
        )

        if !success {
            appState.diagLog.warning("Settings URI get: failed to get \(key ?? "unknown")")
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
