//
//  AppDelegate.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
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

        // A direct launch (for example from Xcode) can bypass the usual
        // single-instance behavior. Two live Thaw instances each register
        // control items and then fight to restore their own saved layouts.
        // Let the newly launched instance win so restart and update flows
        // remain reliable.
        terminateOtherInstances()

        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager().migrateAll()

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

        MacOSCompatibilityWarning.showIfNeeded(updatesManager: appState.updatesManager)

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

        // On first launch, walk the user through onboarding — its final step
        // is where they decide whether to grant permissions, so there's no
        // separate need to surface the permissions window here (PermissionsWindow
        // shows the onboarding tour until first launch completes). Afterward,
        // only resurface the plain permissions window if required permissions
        // are missing (e.g. they were revoked), so a reset doesn't drag the
        // user back through onboarding.
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

    /// Asks any other live copy of this bundle to terminate, escalating after
    /// a short grace period if it does not respond. XCTest hosts are exempt so
    /// parallel test processes never terminate one another.
    private func terminateOtherInstances() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier

        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where other.processIdentifier != currentPID
        {
            appState.diagLog.warning(
                "Another instance is already running (PID \(other.processIdentifier)); terminating it"
            )
            if !other.terminate() {
                other.forceTerminate()
                continue
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !other.isTerminated {
                    self.appState.diagLog.warning(
                        "Other instance (PID \(other.processIdentifier)) did not terminate; force-terminating"
                    )
                    other.forceTerminate()
                }
            }
        }
    }

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
    private func handleURL(_ url: URL, senderBundleId: String? = nil) {
        let request = SettingsURIParser.parse(url)

        switch request.route {
        case .set, .toggle, .get, .authorize:
            handleSettingsURL(url, request: request, senderBundleId: senderBundleId)
        case let .action(action):
            perform(action)
        case let .malformed(host):
            // Rejected ahead of the authorization gate: an incomplete URL must
            // not be able to raise an approval dialog.
            appState.diagLog.warning(
                "Settings URI \(host): missing required parameters in \(url.absoluteString)"
            )
        case .unrecognized:
            appState.diagLog.warning("Received unrecognized thaw:// URL: \(url.absoluteString)")
        }
    }

    /// Performs a parameterless `thaw://` action.
    private func perform(_ action: SettingsURIAction) {
        switch action {
        case .toggleHidden:
            HotkeyAction.toggleHiddenSection.perform(appState: appState)
        case .toggleAlwaysHidden:
            HotkeyAction.toggleAlwaysHiddenSection.perform(appState: appState)
        case .search:
            HotkeyAction.searchMenuBarItems.perform(appState: appState)
        case .toggleThawbar:
            HotkeyAction.enableIceBar.perform(appState: appState)
        case .toggleApplicationMenus:
            HotkeyAction.toggleApplicationMenus.perform(appState: appState)
        case .openSettings:
            openSettingsWindow()
        }
    }

    /// Handles settings manipulation URLs (set/toggle).
    private func handleSettingsURL(_ url: URL, request: SettingsURIRequest, senderBundleId: String?) {
        // Check if Settings URI feature is enabled
        guard SettingsURIHandler.isEnabled() else {
            appState.diagLog.debug("Settings URI is disabled, ignoring: \(url.absoluteString)")
            return
        }

        // Handle version get request without auth (read-only metadata)
        if request.isVersionQuery {
            handleGet(request)
            return
        }

        // Determine effective bundle ID (auto-detected or manual override)
        guard let effectiveBundleId = determineEffectiveBundleId(
            request: request,
            senderBundleId: senderBundleId
        ) else {
            appState.diagLog.debug("Settings URI: Cannot determine sender bundle ID, ignoring: \(url.absoluteString)")
            return
        }

        // Handle authorize request - triggers auth dialog if not already authorized
        if case .authorize = request.route {
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
        switch request.route {
        case let .set(key, value, displayUUID):
            let success = SettingsURIHandler.handleSet(
                key: key,
                value: value,
                sender: effectiveBundleId,
                displayUUID: displayUUID
            )
            if !success {
                appState.diagLog.warning("Settings URI set: failed to set \(key) = \(value)")
            }
        case let .toggle(key, displayUUID):
            let success = SettingsURIHandler.handleToggle(
                key: key,
                sender: effectiveBundleId,
                displayUUID: displayUUID
            )
            if !success {
                appState.diagLog.warning("Settings URI toggle: failed to toggle \(key)")
            }
        case .get:
            handleGet(request)
        default:
            break
        }
    }

    /// Determines the effective bundle ID for authorization.
    /// Uses manual override (DEBUG only) if auto-detection fails.
    private func determineEffectiveBundleId(
        request: SettingsURIRequest,
        senderBundleId: String?
    ) -> String? {
        // If we have auto-detected sender, use it
        if let sender = senderBundleId {
            return sender
        }

        #if DEBUG
            // In DEBUG builds, allow manual bundleId override for testing
            // when auto-detection fails (e.g., from Terminal 'open' command)
            if let manualBundleId = request.bundleIdOverride {
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

    /// Handles `thaw://get?key=X&callback=Y`.
    private func handleGet(_ request: SettingsURIRequest) {
        guard case let .get(key, displayUUID, callback, broadcast, requestId) = request.route else {
            return
        }

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
