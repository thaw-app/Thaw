//
//  AppDelegate.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import MenuBarModel
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState = AppState()
    private var isPreparingForTermination = false
    private var hasRepliedToTerminationRequest = false
    private var terminationAttemptID = UUID()
    private var terminationTimeoutTask: Task<Void, Never>?

    #if DEBUG
        /// Whether the app is running as an Xcode preview/playground.
        ///
        /// Xcode sets one of these environment variables depending on the
        /// Tools version and execution mode (newer versions report
        /// `XCODE_RUNNING_FOR_PLAYGROUNDS` for SwiftUI previews). Checking
        /// both keeps the guard working across versions.
        private var isRunningForPreviews: Bool {
            let environment = ProcessInfo.processInfo.environment
            return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        }
    #endif

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_: Notification) {
        #if DEBUG
            // Don't perform setup if running as a preview.
            if isRunningForPreviews {
                return
            }
        #endif

        // Bound accessibility messaging before anything can create an element.
        // Every AX call is synchronous IPC tied to the target's event loop, so an
        // app that stops pumping it blocks us for the system default of six
        // seconds — the delay behind #767. Healthy calls return in well under
        // 100 ms, so a one second ceiling costs nothing and lets the fallback
        // paths run while the user is still watching. Override with:
        //   defaults write com.stonerl.Thaw axMessagingTimeout -float <seconds>
        UIElement.defaultMessagingTimeout = Float(
            max(0, (Defaults.object(forKey: .axMessagingTimeout) as? Double) ?? Defaults.DefaultValue.axMessagingTimeout)
        )

        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager(appState: appState).migrateAll()

        // Debug-only overflow spacer (chevron-herding experiment).
        // Inert unless `Thaw.debugOverflowSpacerWidth` is set to a positive
        // width; observes the default live so no relaunch is needed.
        OverflowSpacerExperiment.shared.performSetup(with: appState)

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
            if isRunningForPreviews {
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

        // If required permissions are already granted despite this looking
        // like a first launch by our own bookkeeping (e.g. after `defaults
        // delete`, which wipes our UserDefaults but not the system's TCC
        // grants), the user has clearly used Thaw before — skip the
        // onboarding tour and only resurface the permissions screen.
        if isFirstLaunch, appState.permissions.permissionsState != .missing {
            Defaults.set(true, forKey: .hasSeenOnboarding)
        }

        // On first launch, show the feature onboarding and then request
        // permissions in the same window. Later, resurface this window only
        // when required permissions have been revoked.
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
            // macOS 27 doesn't reliably remove our status items when the process
            // exits, leaving a ghost icon with a dead (grayed-out) menu. Remove
            // them explicitly while we're still alive, and give MenuBarAgent a
            // moment to reclaim them before we actually quit.
            if #available(macOS 27, *) {
                appState.menuBarManager.tearDownControlItemsForTermination()
                try? await Task.sleep(for: .milliseconds(150))
                guard terminationAttemptID == attemptID else {
                    return
                }
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
        let keySenderPID = AEKeyword(keySenderPIDAttr)

        guard let pidDesc = event.attributeDescriptor(forKeyword: keySenderPID) else {
            return nil
        }

        // macOS 26 stores keySenderPIDAttr as typeUInt32 ('magn') on arm64.
        // Accept any numeric type and extract the PID from raw descriptor data.
        let integerTypes: Set<OSType> = [
            typeSInt16, typeSInt32, typeSInt64,
            typeUInt16, typeUInt32, typeUInt64,
            typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint,
        ]

        var pid: pid_t = 0

        if integerTypes.contains(pidDesc.descriptorType) {
            // Copy raw bytes regardless of storage type (typeUInt32, typeSInt64, etc.)
            let data = pidDesc.data
            let copyCount = min(data.count, MemoryLayout<pid_t>.size)
            data.withUnsafeBytes { src in
                withUnsafeMutableBytes(of: &pid) { dest in
                    guard let srcPtr = src.baseAddress, let destPtr = dest.baseAddress else { return }
                    memcpy(destPtr, srcPtr, copyCount)
                }
            }
        } else {
            // Fallback: try coercion for unknown types
            let coerced = pidDesc.int32Value
            guard coerced > 0 else { return nil }
            pid = pid_t(coerced)
        }

        guard pid > 0 else { return nil }

        guard let app = NSRunningApplication(processIdentifier: pid) else {
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
    /// - `thaw://reveal-item?bundle=X` or `?item-id=Y` — temporarily reveal a hidden menu bar item
    private func handleURL(_ url: URL, senderBundleId: String? = nil) {
        let host = url.host?.lowercased() ?? ""

        // Handle settings manipulation URLs
        switch host {
        case "set", "toggle", "get", "authorize", "reveal-item":
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

        // Handle version get request without auth (read-only metadata)
        if host == "get",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.queryItems?.first(where: { $0.name == "key" })?.value == "version"
        {
            handleGetURL(url, sender: nil)
            return
        }

        // Determine effective bundle ID (auto-detected or manual override)
        guard let effectiveBundleId = determineEffectiveBundleId(url: url, senderBundleId: senderBundleId) else {
            appState.diagLog.debug("Settings URI: Cannot determine sender bundle ID, ignoring: \(url.absoluteString)")
            return
        }

        // Handle authorize request - triggers auth dialog if not already authorized
        if host == "authorize" {
            if !SettingsURIHandler.isWhitelisted(bundleIdentifier: effectiveBundleId) {
                _ = SettingsURIHandler.promptForAuthorization(bundleId: effectiveBundleId)
            }
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
        case "reveal-item":
            handleRevealItemURL(url, sender: effectiveBundleId)
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

    /// Handles thaw://reveal-item?bundle=X or ?item-id=Y URL.
    /// Temporarily reveals a single hidden/always-hidden menu bar item without
    /// revealing the rest of its section; it auto-reconceals via the same
    /// menu-open-aware delay used by the Thaw Bar click path.
    private func handleRevealItemURL(_ url: URL, sender: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            appState.diagLog.warning("Settings URI reveal-item: invalid URL \(url.absoluteString)")
            return
        }

        let bundle = components.queryItems?.first(where: { $0.name == "bundle" })?.value
        let itemID = components.queryItems?.first(where: { $0.name == "item-id" })?.value

        guard let sectionController = appState.menuBarManager.sectionController else {
            appState.diagLog.warning("Settings URI reveal-item: per-item reveal is unavailable on this OS")
            return
        }

        guard let identifier = SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: bundle,
            itemID: itemID,
            sectionAssignment: sectionController.sectionAssignment
        ) else {
            appState.diagLog.warning("Settings URI reveal-item: missing or ambiguous bundle/item-id in \(url.absoluteString)")
            return
        }

        sectionController.revealItemTemporarily(identifier)
        sectionController.scheduleTemporaryItemConceal(identifier)
        appState.diagLog.info("Settings URI reveal-item: revealed \(identifier) for sender \(sender ?? "unknown")")
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

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }
}
