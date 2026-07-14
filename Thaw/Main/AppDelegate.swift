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

    /// Set when this process discovers that a newer Thaw instance already
    /// owns the menu bar. Termination is asynchronous, so lifecycle callbacks
    /// can still arrive before the process exits; every launch path must
    /// observe this flag and avoid initializing a competing instance.
    private var isYieldingToNewerInstance = false

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

        // Enforce a single running instance. Two live instances each
        // register their own control items and fight over the same menu
        // bar: both apply their saved layouts on their own cadence, and
        // each classifies the other's control item windows as ordinary
        // items to be relocated — including parking the other instance's
        // chevron offscreen. LaunchServices doesn't prevent this when the
        // binary is launched directly (e.g. an Xcode debug session while
        // a copy launched at login is still running). The newest instance
        // wins so restart and update flows keep working.
        guard terminateOtherInstances() else {
            return
        }

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
        // `NSApp.terminate` is asynchronous when the delegate returns
        // `.terminateLater`, so did-finish can be delivered before the
        // termination reply. Never start setup in the instance that yielded.
        guard !isYieldingToNewerInstance else {
            return
        }

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
        // This instance has not initialized its menu-bar controls yet. Reply
        // immediately so a newer instance does not have to wait for a
        // pointless blocked-item restore from a process that is yielding.
        if isYieldingToNewerInstance {
            return .terminateNow
        }

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

    /// Returns true when `other` launched before this process, so "newest
    /// instance wins" has an actual ordering to act on. Falls back to PID
    /// comparison when either launch date is unavailable (PIDs aren't
    /// guaranteed monotonic, but combined with the bundle-ID filter this is
    /// only ever a tie-break between two live copies of this app).
    private func isOlderInstance(_ other: NSRunningApplication) -> Bool {
        let ourLaunchDate = NSRunningApplication.current.launchDate
        if let otherDate = other.launchDate, let ourDate = ourLaunchDate {
            if otherDate != ourDate {
                return otherDate < ourDate
            }
            // Identical timestamps: fall through to the PID tie-break.
        }
        return other.processIdentifier < ProcessInfo.processInfo.processIdentifier
    }

    /// Terminates any older running instances of this app and waits (bounded)
    /// for them to exit before returning, escalating to a force-terminate if
    /// an instance ignores the polite request.
    ///
    /// Only OLDER instances are terminated — the newest instance wins, so two
    /// copies launching simultaneously can't kill each other and leave zero
    /// running (each computes the same ordering; exactly one survives). If a
    /// NEWER instance is already running, this instance bows out instead:
    /// that's the restart/update flow arriving from the other side.
    ///
    /// The bounded wait matters as much as the terminate: the old instance's
    /// applicationShouldTerminate runs an async restore for up to 2 seconds,
    /// during which it still moves its own menu bar items. Proceeding into
    /// migration and menu bar setup while that's in flight recreates the
    /// two-instances-fighting race this guard exists to prevent, so we spin
    /// the run loop until the others are gone (or a ~3.5s budget expires,
    /// after which they're force-terminated and we proceed).
    /// - Returns: `false` when this instance yielded to a newer copy and must
    ///   not continue launch setup.
    private func terminateOtherInstances() -> Bool {
        // Never enforce single-instance under XCTest: parallel testing
        // launches several host app instances that would kill each other,
        // failing the run with "test runner exited before establishing
        // connection".
        guard NSClassFromString("XCTestCase") == nil else { return true }
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
        guard !otherInstances.isEmpty else { return true }

        if let newer = otherInstances.first(where: { !isOlderInstance($0) }) {
            appState.diagLog.warning(
                "A newer instance is already running (PID \(newer.processIdentifier)); terminating this one"
            )
            isYieldingToNewerInstance = true
            NSApp.terminate(nil)
            return false
        }

        for other in otherInstances {
            appState.diagLog.warning(
                "An older instance is already running (PID \(other.processIdentifier)); terminating it"
            )
            if !other.terminate() {
                other.forceTerminate()
            }
        }

        // Bounded wait for the older instances to actually exit. Their
        // termination flow (blocked-item restore) takes up to 2s by design;
        // budget slightly more, then force-terminate stragglers and give
        // them a final moment to die.
        let politeDeadline = Date(timeIntervalSinceNow: 2.5)
        while otherInstances.contains(where: { !$0.isTerminated }), Date() < politeDeadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        let stragglers = otherInstances.filter { !$0.isTerminated }
        guard !stragglers.isEmpty else { return true }
        for straggler in stragglers {
            appState.diagLog.warning(
                "Older instance (PID \(straggler.processIdentifier)) did not terminate in time; force-terminating"
            )
            straggler.forceTerminate()
        }
        let forceDeadline = Date(timeIntervalSinceNow: 1.0)
        while stragglers.contains(where: { !$0.isTerminated }), Date() < forceDeadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return true
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
        let host = url.host?.lowercased() ?? ""

        // Handle settings manipulation URLs
        switch host {
        case "set", "toggle", "get", "authorize":
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

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }
}
