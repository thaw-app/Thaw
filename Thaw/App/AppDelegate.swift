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
        #if DEBUG
            // Don't perform setup if running as a preview.
            if isRunningForPreviews {
                return
            }
        #endif

        // Set AX timeout before creating elements: synchronous IPC can stall when a target stops pumping events.
        // Override with defaults write com.stonerl.Thaw axMessagingTimeout -float <seconds>.
        AXElement.defaultMessagingTimeout = Float(
            max(0, (Defaults.object(forKey: .axMessagingTimeout) as? Double) ?? 0)
        )

        NSSplitViewItem.swizzle()
        MigrationManager().migrateAll()

        // Overflow spacer is inert unless Thaw.debugOverflowSpacerWidth is positive; changes apply without relaunch.
        OverflowSpacer.shared.performSetup(with: appState)

        // Descenders observe their setting live and use app state to hit-test on-screen items.
        notchPanelController.performSetup(with: appState)

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
        if stage != .none {
            appState.openWindow(.permissions)
        } else {
            // Upgrade notes appear once per version, only outside the onboarding/permissions path.
            NativeAppHidingOffer.presentIfNeeded(settings: appState.settings.advanced)
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
        appState.diagLog.info("Application asked to terminate - restoring blocked items asynchronously")
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

    /// Handles kAEGetURL Apple Events and forwards thaw:// URLs to handleURL(_:senderBundleId:).
    @objc private func handleURLAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "thaw"
        else { return }

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
            let data = pidDesc.data
            let copyCount = min(data.count, MemoryLayout<pid_t>.size)
            data.withUnsafeBytes { src in
                withUnsafeMutableBytes(of: &pid) { dest in
                    guard let srcPtr = src.baseAddress, let destPtr = dest.baseAddress else { return }
                    memcpy(destPtr, srcPtr, copyCount)
                }
            }
        } else {
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

    /// Routes thaw:// actions and settings requests; settings changes and per-item reveals require whitelist authorization.
    /// proxy-press?bundle=X presses a hosted item by owner, while toggle-layout-editor opens quick edit without Settings.
    private func handleURL(_ url: URL, senderBundleId: String? = nil) {
        let host = url.host?.lowercased() ?? ""

        switch host {
        case "set", "toggle", "get", "authorize", "reveal-item",
             "list-items", "activate-item", "list-profiles", "apply-profile", "get-appearance":
            handleSettingsURL(url, host: host, senderBundleId: senderBundleId)
            return
        default:
            break
        }

        switch host {
        case "toggle-hidden":
            HotkeyAction.toggleHiddenSection.perform(appState: appState)
        case "proxy-press":
            handleProxyPressURL(url)
        case "toggle-always-hidden":
            HotkeyAction.toggleAlwaysHiddenSection.perform(appState: appState)
        case "toggle-swap":
            HotkeyAction.toggleSwap.perform(appState: appState)
        case "search":
            HotkeyAction.searchMenuBarItems.perform(appState: appState)
        case "toggle-thawbar":
            HotkeyAction.enableThawBar.perform(appState: appState)
        case "toggle-application-menus":
            HotkeyAction.toggleApplicationMenus.perform(appState: appState)
        case "toggle-zen-mode":
            HotkeyAction.toggleZenMode.perform(appState: appState)
        case "toggle-layout-editor":
            // Use the hotkey's "Edit Layout" quick-edit panel, not the Settings window.
            HotkeyAction.toggleLayoutEditor.perform(appState: appState)
        case "dump-items":
            let callback = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "callback" }?.value
            if let fileURL = ItemEnumerationDump.run() {
                ItemEnumerationDump.respond(fileURL: fileURL, callback: callback)
            }
        case "open-settings":
            openSettingsWindow()
        case "item-hints":
            appState.itemHints.toggle()
        default:
            appState.diagLog.warning("Received unrecognized thaw:// URL: \(url.absoluteString)")
        }
    }

    /// Handles thaw://proxy-press?bundle=X, AXPresses a hosted menu bar item
    /// by owner bundle, materializing it even when the host has parked it.
    private func handleProxyPressURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let bundle = components.queryItems?.first(where: { $0.name == "bundle" })?.value,
              !bundle.isEmpty
        else {
            appState.diagLog.warning("proxy-press: missing bundle in \(url.absoluteString)")
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            appState.diagLog.warning("proxy-press: \(bundle) is not running")
            return
        }
        let pid = app.processIdentifier
        let state = appState
        appState.diagLog.info("proxy-press: pressing hosted item for \(bundle) (pid \(pid))")
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

    /// Handles settings manipulation URLs (set/toggle).
    private func handleSettingsURL(_ url: URL, host: String, senderBundleId: String?) {
        // A built-in trusted sender works out of the box; everyone else needs the feature on.
        guard SettingsURIHandler.isEnabled()
            || SettingsURIHandler.isBuiltInTrustedSender(bundleIdentifier: senderBundleId)
        else {
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

        guard let effectiveBundleId = determineEffectiveBundleId(url: url, senderBundleId: senderBundleId) else {
            appState.diagLog.debug("Settings URI: Cannot determine sender bundle ID, ignoring: \(url.absoluteString)")
            return
        }

        if host == "authorize" {
            if !SettingsURIHandler.isWhitelisted(bundleIdentifier: effectiveBundleId) {
                _ = SettingsURIHandler.promptForAuthorization(bundleId: effectiveBundleId)
            }
            return
        }

        // Verify sender is whitelisted, or prompt for first-time authorization
        if !SettingsURIHandler.isWhitelisted(bundleIdentifier: effectiveBundleId) {
            let approved = SettingsURIHandler.promptForAuthorization(bundleId: effectiveBundleId)
            guard approved else {
                // Declined authorization fails silently.
                return
            }
        }

        switch host {
        case "set":
            handleSetURL(url, sender: effectiveBundleId)
        case "toggle":
            handleToggleURL(url, sender: effectiveBundleId)
        case "get":
            handleGetURL(url, sender: effectiveBundleId)
        case "reveal-item":
            handleRevealItemURL(url, sender: effectiveBundleId)
        case "list-items", "activate-item", "list-profiles", "apply-profile", "get-appearance":
            handleLauncherURL(url, sender: effectiveBundleId)
        default:
            break
        }
    }

    /// Determines the effective bundle ID for authorization.
    /// Uses manual override (DEBUG only) if auto-detection fails.
    private func determineEffectiveBundleId(url: URL, senderBundleId: String?) -> String? {
        if let sender = senderBundleId {
            return sender
        }

        #if DEBUG
            // Debug-only override supports Terminal 'open' testing when sender detection fails.
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

    /// thaw://reveal-item?bundle=X or ?item-id=Y reveals one item without its section.
    /// Reconceals with the Thaw Bar click path's menu-open-aware delay.
    private func handleRevealItemURL(_ url: URL, sender: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            appState.diagLog.warning("Settings URI reveal-item: invalid URL \(url.absoluteString)")
            return
        }

        let bundle = components.queryItems?.first(where: { $0.name == "bundle" })?.value
        let itemID = components.queryItems?.first(where: { $0.name == "item-id" })?.value

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
            appState.diagLog.warning("Settings URI reveal-item: missing or ambiguous bundle/item-id in \(url.absoluteString)")
            return
        }

        sectionController.revealItemTemporarily(identifier)
        sectionController.scheduleTemporaryItemConceal(identifier)
        appState.diagLog.info("Settings URI reveal-item: revealed \(identifier) for sender \(sender ?? "unknown")")
    }

    /// Handles the launcher operations, including get-appearance.
    /// The work is async because activation and profile layout report an outcome once they finish.
    private func handleLauncherURL(_ url: URL, sender: String?) {
        guard let request = LauncherURIRequest(url: url) else {
            appState.diagLog.warning("Launcher URI: invalid URL \(url.absoluteString)")
            return
        }
        let state = appState
        Task {
            await SettingsURIHandler.handleLauncherRequest(request, sender: sender, appState: state)
        }
    }

    /// Handles thaw://get?key=X&callback=Y URLs.
    private func handleGetURL(_ url: URL, sender _: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            appState.diagLog.warning("Settings URI get: invalid URL \(url.absoluteString)")
            return
        }

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
