//
//  AppDelegate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import ThawAXCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var isPreparingForTermination = false
    private var hasRepliedToTerminationRequest = false
    private var terminationAttemptID = UUID()
    private var terminationTimeoutTask: Task<Void, Never>?
    /// Per-item descenders; inert unless the setting is turned on.
    private let notchPanelController = NotchPanelController()

    #if DEBUG
        /// Check both Xcode flags because previews may use either the preview or playground environment.
        private var isRunningForPreviews: Bool {
            let environment = ProcessInfo.processInfo.environment
            return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        }
    #endif

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_: Notification) {
        LiveApp.register(self)
        #if DEBUG
            // Don't perform setup if running as a preview.
            if isRunningForPreviews {
                return
            }
        #endif

        // Another copy must be resolved before this one touches the menu bar, permissions or native hiding.
        guard SingleInstanceGuard.enforce() else { return }

        // Set AX timeout before creating elements: synchronous IPC can stall when a target stops pumping events.
        // Override with defaults write com.stonerl.Thaw axMessagingTimeout -float <seconds>.
        AXElement.defaultMessagingTimeout = Float(
            max(0, (Defaults.object(forKey: .axMessagingTimeout) as? Double) ?? 0)
        )

        NSSplitViewItem.swizzle()
        MigrationManager().migrateAll()

        // Overflow spacer is inert unless Thaw.debugOverflowSpacerWidth is positive; once the key exists, changes apply without relaunch.
        OverflowSpacer.shared.performSetup(with: appState)

        // Descenders observe their setting live and use app state to hit-test on-screen items.
        notchPanelController.performSetup(with: appState, displayInvalidations: appState.displayEnvironment.invalidations)

        // Register thaw:// early so external tools can trigger background actions; individual actions may activate Thaw.
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
        WindowMenuTrimmer.shared.watch { [weak appState] in appState?.hasOpenWindow ?? false }

        // Allow hiding the mouse while the app is in the background
        // to make menu bar item movement less jarring.
        Bridging.setConnectionProperty(true, forKey: "SetsCursorInBackground")

        #if DEBUG
            // Don't perform setup if running as a preview.
            if isRunningForPreviews {
                return
            }
        #endif

        ConflictingAppDetector.showWarningIfNeeded()

        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.diagLog.debug("Passed all permissions checks")
            appState.launch(withPermissions: true)
        case .hasRequired:
            appState.permissions.diagLog.debug("Passed required permissions checks")
            appState.launch(withPermissions: true)
        case .missing:
            appState.permissions.diagLog.debug("Failed required permissions checks")
            appState.launch(withPermissions: false)
        }

        // Share the window's onboarding inputs so the delegate neither opens an empty window nor skips a needed one.
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: Defaults.bool(forKey: .hasCompletedFirstLaunch),
            hasSeenOnboarding: Defaults.bool(forKey: .hasSeenOnboarding),
            accessibilityGranted: appState.permissions.permissionsState != .missing,
            seenOnboardingVersion: Defaults.integer(forKey: .onboardingVersion),
            currentOnboardingVersion: Constants.currentOnboardingVersion
        )

        // Never show onboarding and What's New together; onboarding already includes release notes.
        if ReducedModeController.shared.isRunning {
            // The reduced mode has no windows of its own and asks for nothing.
        } else if stage != .none {
            appState.openWindow(.permissions)
        } else {
            // Upgrade notes appear once per version, only outside the onboarding/permissions path.
            appState.presentWhatsNewForUpgradeIfNeeded()
        }
    }

    /// Diagnostic-only focus traces attribute self-deactivation to preceding work.
    func applicationDidBecomeActive(_: Notification) {
        appState.diagLog.debug(
            "focus-trace didBecomeActive uptime=\(ProcessInfo.processInfo.systemUptime) policy=\(NSApp.activationPolicy().rawValue)"
        )
    }

    func applicationDidResignActive(_: Notification) {
        appState.diagLog.debug(
            "focus-trace didResignActive uptime=\(ProcessInfo.processInfo.systemUptime) policy=\(NSApp.activationPolicy().rawValue) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil") stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Background reopens from another app's activation cycle, such as Siri sends, must not steal focus with Settings.
        guard !hasVisibleWindows else { return true }
        guard NSWorkspace.shared.frontmostApplication == NSRunningApplication.current else {
            appState.diagLog.debug("Ignoring reopen: another app is frontmost (likely an activation cycle)")
            return true
        }
        appState.diagLog.debug("Handling reopen from app icon click")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        appState.restoreAccessoryPolicyIfUnused()
        return false
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        // This only declares secure coding for restorable state; window
        // restoration itself is switched off per scene in ThawWindow.
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if NativeVisibilityRecoveryLaunch.isHandingOff {
            // Do not release reveal holds or run layout reconciliation during recovery handoff.
            appState.menuBarManager.tearDownControlItemsForTermination()
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
        appState.diagLog.info("Application asked to terminate \(QuitRequestSource.current()) - restoring blocked items asynchronously")
        appState.appRunningTriggers.stop()

        Task { @MainActor in
            _ = await appState.itemManager.restoreBlockedItemsToVisible()
            guard terminationAttemptID == attemptID else {
                return
            }
            // macOS 27 can leave dead status icons on exit; remove them explicitly and let MenuBarAgent reclaim them before quitting.
            appState.menuBarManager.tearDownControlItemsForTermination()
            try? await Task.sleep(for: .milliseconds(150))
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
        if NativeVisibilityRecoveryLaunch.isHandingOff {
            // Capture changes since launch began. Leave the original journal intact
            // for recovery instead of clearing it through the normal cached reader.
            do {
                try NativeAppVisibilityRecovery().preserveRecoveryRecords()
            } catch {
                appState.diagLog.error("Could not checkpoint visibility recovery; original journal retained: \(error.localizedDescription)")
            }
        } else {
            appState.menuBarManager.nativeAppHidingExperiment.prepareForTermination()
        }
        appState.menuBarManager.systemExtraTakeover.prepareForTermination()
        // Balance the layout-table security scope before exit.
        MenuBarLayoutTableAccess.shared.release()
    }

    // MARK: Other Methods

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

    /// Routes thaw:// actions and settings requests; requests that need authorization go through handleSettingsURL.
    private func handleURL(_ url: URL, sender: SettingsURISender? = nil) {
        // Nothing below is set up while the reduced mode runs.
        if ReducedModeController.shared.isRunning {
            ReducedModeController.shared.handle(url)
            return
        }

        let request = SettingsURIParser.parse(url)
        if request.requiresAuthorization {
            handleSettingsURL(url, request: request, sender: sender)
            return
        }

        switch request.route {
        case .action(.openSettings):
            openSettingsWindow()
        case .action(.itemHints):
            appState.itemHints.toggle()
        case let .action(action):
            // The hotkey's actions, so toggle-layout-editor opens the quick-edit panel, not Settings.
            action.hotkeyAction?.perform(appState: appState)
        default:
            appState.diagLog.warning("Received unrecognized thaw:// URL: \(url.absoluteString)")
        }
    }

    /// Handles thaw://proxy-press?bundle=X, AXPresses a hosted menu bar item
    /// by owner bundle, materializing it even when the host has parked it.
    private func handleProxyPressRequest(bundle: String, sender: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            appState.diagLog.warning("proxy-press: \(bundle) is not running")
            return
        }
        let pid = app.processIdentifier
        let state = appState
        appState.diagLog.info("proxy-press: pressing hosted item for \(bundle) (pid \(pid)) for sender \(sender)")
        Task {
            let pressed = await MenuBarAXQueries.pressHostedItem(sourcePID: pid)
            await MainActor.run {
                if pressed {
                    state.diagLog.info("proxy-press: pressed \(bundle)'s hosted item")
                } else {
                    state.diagLog.error("proxy-press: could not press \(bundle)'s hosted item")
                }
            }
        }
    }

    /// Writes the item dump for an approved sender and returns its path only to a callback that sender handles.
    private func handleDumpItemsRequest(callback requested: String?, sender: String) {
        let callback = ItemEnumerationDump.deliverableCallback(requested, senderBundleIdentifier: sender) { target in
            NSWorkspace.shared.urlForApplication(toOpen: target).flatMap { Bundle(url: $0)?.bundleIdentifier }
        }
        if requested != nil, callback == nil {
            appState.diagLog.warning("dump-items: refusing callback that \(sender) does not handle")
        }
        guard let fileURL = ItemEnumerationDump.run(), let callback else {
            return
        }
        ItemEnumerationDump.respond(fileURL: fileURL, callback: callback)
    }

    /// Runs a request that needs the Settings URI switch and an approved sender.
    private func handleSettingsURL(_ url: URL, request: SettingsURIRequest, sender: SettingsURISender?) {
        // A built-in trusted sender works out of the box; everyone else needs the feature on.
        guard SettingsURIHandler.isEnabled()
            || SettingsURIHandler.isBuiltInTrustedSender(sender)
        else {
            appState.diagLog.debug("Settings URI is disabled, ignoring: \(url.absoluteString)")
            return
        }

        // Handle version get request without auth (read-only metadata)
        if request.isVersionRead, case let .get(query) = request.route {
            handleGetRequest(query, sender: nil)
            return
        }

        guard let identity = determineEffectiveSender(url: url, sender: sender) else {
            appState.diagLog.debug("Settings URI: Cannot identify the sender, ignoring: \(url.absoluteString)")
            return
        }

        if request.route == .authorize {
            if !SettingsURIHandler.isWhitelisted(sender: identity) {
                _ = SettingsURIHandler.promptForAuthorization(sender: identity)
            }
            return
        }

        // Verify sender is whitelisted, or prompt for first-time authorization
        if !SettingsURIHandler.isWhitelisted(sender: identity) {
            let approved = SettingsURIHandler.promptForAuthorization(sender: identity)
            guard approved else {
                // Declined authorization fails silently.
                return
            }
        }

        if case let .malformed(host) = request.route {
            appState.diagLog.warning("Settings URI \(host): missing required parameters in \(url.absoluteString)")
            return
        }
        dispatchAuthorizedRoute(request.route, sender: identity.bundleIdentifier)
    }

    /// Runs a route whose sender passed the whitelist check.
    private func dispatchAuthorizedRoute(_ route: SettingsURIRoute, sender effectiveBundleId: String) {
        switch route {
        case let .set(key, value, displayUUID):
            handleSetRequest(key: key, value: value, displayUUID: displayUUID, sender: effectiveBundleId)
        case let .toggle(key, displayUUID):
            handleToggleRequest(key: key, displayUUID: displayUUID, sender: effectiveBundleId)
        case let .get(query):
            handleGetRequest(query, sender: effectiveBundleId)
        case let .revealItem(bundle, itemID):
            handleRevealItemRequest(bundle: bundle, itemID: itemID, sender: effectiveBundleId)
        case let .launcher(operation, query):
            handleLauncherRequest(LauncherURIRequest(operation: operation, query: query), sender: effectiveBundleId)
        case let .proxyPress(bundle):
            handleProxyPressRequest(bundle: bundle, sender: effectiveBundleId)
        case .toggleThawBar:
            // It saves the active display's Thaw Bar setting, so it answers to the same gate as set and toggle.
            HotkeyAction.enableThawBar.perform(appState: appState)
        case let .dumpItems(callback):
            handleDumpItemsRequest(callback: callback, sender: effectiveBundleId)
        case .authorize, .action, .malformed, .unrecognized:
            break
        }
    }

    /// The sender identified from its code signature, or in DEBUG builds a manual override
    /// that carries no signature and so never matches a stored approval.
    private func determineEffectiveSender(url: URL, sender: SettingsURISender?) -> SettingsURISender? {
        if let sender {
            return sender
        }

        #if DEBUG
            // Debug-only override supports Terminal 'open' testing when sender detection fails.
            if let manualBundleId = extractManualBundleId(from: url) {
                appState.diagLog.warning("Settings URI: Using DEBUG manual bundleId=\(manualBundleId) - FOR TESTING ONLY")
                return SettingsURISender(bundleIdentifier: manualBundleId, teamIdentifier: nil, codeHash: nil)
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

    /// Handles thaw://set?key=X&value=Y.
    private func handleSetRequest(key: String, value: String, displayUUID: String?, sender: String) {
        if !SettingsURIHandler.handleSet(key: key, value: value, sender: sender, displayUUID: displayUUID) {
            appState.diagLog.warning("Settings URI set: failed to set \(key) = \(value)")
        }
    }

    /// Handles thaw://toggle?key=X.
    private func handleToggleRequest(key: String, displayUUID: String?, sender: String) {
        if !SettingsURIHandler.handleToggle(key: key, sender: sender, displayUUID: displayUUID) {
            appState.diagLog.warning("Settings URI toggle: failed to toggle \(key)")
        }
    }

    /// thaw://reveal-item?bundle=X or ?item-id=Y reveals one item without its section.
    /// Reconceals with the Thaw Bar click path's menu-open-aware delay.
    private func handleRevealItemRequest(bundle: String?, itemID: String?, sender: String) {
        let sectionController = appState.menuBarManager.sectionController
        guard sectionController.isOperational else {
            appState.diagLog.warning("Settings URI reveal-item: per-item reveal is unavailable on this OS")
            return
        }

        guard let identifier = SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: bundle,
            itemID: itemID,
            sectionAssignment: sectionController.sectionAssignment
        ) else {
            appState.diagLog.warning("Settings URI reveal-item: missing or ambiguous bundle/item-id")
            return
        }

        sectionController.revealItemTemporarily(identifier)
        sectionController.scheduleTemporaryItemConceal(identifier)
        appState.diagLog.info("Settings URI reveal-item: revealed \(identifier) for sender \(sender)")
    }

    /// Handles the launcher operations, including get-appearance.
    /// The work is async because activation and profile layout report an outcome once they finish.
    private func handleLauncherRequest(_ request: LauncherURIRequest, sender: String) {
        let state = appState
        Task {
            await SettingsURIHandler.handleLauncherRequest(request, sender: sender, appState: state)
        }
    }

    /// Handles thaw://get?key=X&callback=Y.
    private func handleGetRequest(_ query: SettingsURIGetQuery, sender _: String?) {
        let success = SettingsURIHandler.handleGet(
            key: query.key,
            displayUUID: query.displayUUID,
            callback: query.callback,
            broadcast: query.broadcast,
            requestId: query.requestId
        )

        if !success {
            appState.diagLog.warning("Settings URI get: failed to get \(query.key ?? "unknown")")
        }
    }

    @objc func openWhatsNewWindow() {
        Task { @MainActor in
            appState.activate(withPolicy: .regular)
            appState.openWindow(.whatsNew)
        }
    }

    @objc func openSettingsWindow() {
        appState.prepareSettingsPresentation()
        appState.diagLog.debug("Opening settings window from app icon/dock/menu click")

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }
}
