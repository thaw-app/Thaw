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
    let appState = AppState()
    private var isPreparingForTermination = false
    private var hasRepliedToTerminationRequest = false
    private var terminationAttemptID = UUID()
    private var terminationTimeoutTask: Task<Void, Never>?

    #if DEBUG
        /// Whether the app is running as an Xcode preview/playground.
        ///
        /// Newer Xcode versions report `XCODE_RUNNING_FOR_PLAYGROUNDS` for
        /// previews, so both variables are checked.
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

        // Bound AX messaging before any element exists, or a stalled app blocks
        // us for the six-second default (#767). Override with:
        //   defaults write com.stonerl.Thaw axMessagingTimeout -float <seconds>
        UIElement.defaultMessagingTimeout = Float(
            max(0, (Defaults.object(forKey: .axMessagingTimeout) as? Double) ?? Defaults.DefaultValue.axMessagingTimeout)
        )

        // A direct launch (e.g. from Xcode) can bypass single-instance behavior,
        // and two instances fight over layouts. The newest one wins.
        terminateOtherInstances()

        NSSplitViewItem.swizzle()
        MigrationManager().migrateAll()

        // Register thaw:// early so tools like Raycast work while Thaw is in the background.
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

        // First launch shows onboarding, whose last step handles permissions.
        // Afterward, show the permissions window only if permissions are missing.
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

    /// Handles kAEGetURL Apple Events and forwards thaw:// URLs to handleURL(_:sender:).
    @objc private func handleURLAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "thaw"
        else { return }

        handleURL(url, sender: SettingsURISender.identify(from: event))
    }

    /// Dispatches an incoming `thaw://` URL to the appropriate action.
    ///
    /// Supported Action URLs:
    /// - `thaw://toggle-hidden` — toggle the hidden menu bar section
    /// - `thaw://toggle-always-hidden` — toggle the always-hidden menu bar section
    /// - `thaw://search` — open the menu bar item search panel
    /// - `thaw://toggle-thawbar` — toggle the IceBar on the active display; it saves the
    ///   setting, so it needs settings access and an approved sender like the Settings URLs
    /// - `thaw://toggle-application-menus` — toggle application menus
    /// - `thaw://open-settings` — open the Thaw settings window
    ///
    /// Supported Settings URLs (requires whitelist authorization):
    /// - `thaw://set?key=X&value=Y` — set a boolean setting
    /// - `thaw://toggle?key=X` — toggle a boolean setting
    private func handleURL(_ url: URL, sender: SettingsURISender? = nil) {
        let request = SettingsURIParser.parse(url)

        switch request.route {
        case .set, .toggle, .get, .authorize:
            handleSettingsURL(url, request: request, sender: sender)
        case let .action(action):
            // A persistent change answers to the same switch and approval as a settings URL.
            if action.persistsSettings {
                guard SettingsURIHandler.isEnabled(),
                      authorizeSender(request: request, sender: sender, url: url) != nil
                else {
                    appState.diagLog.debug("Settings URI: refusing \(url.absoluteString) without settings access")
                    return
                }
            }
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
    private func handleSettingsURL(_ url: URL, request: SettingsURIRequest, sender: SettingsURISender?) {
        guard SettingsURIHandler.isEnabled() else {
            appState.diagLog.debug("Settings URI is disabled, ignoring: \(url.absoluteString)")
            return
        }

        // Handle version get request without auth (read-only metadata)
        if request.isVersionQuery {
            handleGet(request)
            return
        }

        // An authorize request only raises the dialog, so it stops here either way.
        guard let effectiveBundleId = authorizeSender(request: request, sender: sender, url: url),
              request.route != .authorize
        else {
            return
        }

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
    /// The approved sender's bundle identifier, prompting once for a sender that isn't
    /// approved yet. Nil when it can't be identified or the user refuses.
    private func authorizeSender(request: SettingsURIRequest, sender: SettingsURISender?, url: URL) -> String? {
        let bundleId: String
        let identity: SettingsURIHandler.TeamIdentifierLookup?
        if let sender {
            bundleId = sender.bundleIdentifier
            identity = sender.team
        } else {
            #if DEBUG
                // When the sender can't be identified (e.g. Terminal's open), a debug
                // build may name one by hand.
                guard let manualBundleId = request.bundleIdOverride else {
                    appState.diagLog.debug("Settings URI: Cannot identify the sender, ignoring: \(url.absoluteString)")
                    return nil
                }
                appState.diagLog.warning("Settings URI: Using DEBUG manual bundleId=\(manualBundleId) - FOR TESTING ONLY")
                bundleId = manualBundleId
                identity = nil
            #else
                appState.diagLog.debug("Settings URI: Cannot identify the sender, ignoring: \(url.absoluteString)")
                return nil
            #endif
        }

        if SettingsURIHandler.isWhitelisted(bundleIdentifier: bundleId, senderIdentity: identity) {
            return bundleId
        }
        return SettingsURIHandler.promptForAuthorization(
            bundleId: bundleId,
            senderIdentity: identity,
            senderName: sender?.displayName
        ) ? bundleId : nil
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
        // Always allow opening settings from the app, Dock, or menu bar icon.
        appState.diagLog.debug("Opening settings window from app icon/dock/menu click")

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            appState.activateForUserWindow()
            appState.openWindow(.settings)
        }
    }
}
