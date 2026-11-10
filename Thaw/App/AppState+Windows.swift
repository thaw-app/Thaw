//
//  AppState+Windows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Darwin
import Observation

@MainActor
final class ThawWindowDelegate: NSObject, NSWindowDelegate {
    private let id: ThawWindowIdentifier
    private weak var appState: AppState?

    init(id: ThawWindowIdentifier, appState: AppState) {
        self.id = id
        self.appState = appState
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        appState?.handleManagedWindowWillClose(id: id, window: window)
    }
}

extension AppState {
    // MARK: - Windows

    /// Emits the live window or nil when closed, starting with the current value and never finishing.
    func windowPublisher(for id: ThawWindowIdentifier) -> some Publisher<NSWindow?, Never> {
        let subject = CurrentValueSubject<NSWindow?, Never>(trackedWindows[id])
        let task = Task { @MainActor [weak self] in
            let changes = Observations { self?.trackedWindows[id] }
            for await window in changes {
                guard self != nil else { return }
                subject.send(window)
            }
        }
        return subject.handleEvents(receiveCancel: { task.cancel() })
    }

    func prepareSettingsPresentation() {
        guard let id = navigationState.beginSettingsPresentation() else { return }
        imageCache.prepareForPresentation()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.navigationState.finishSettingsPresentation(id)
        }
    }

    func openWindow(_ id: ThawWindowIdentifier, allowSettingsProcess: Bool = true) {
        if allowSettingsProcess, showsInSettingsProcess(id, isOpenHere: isWindowOpen(id)) {
            return
        }
        windowTeardownTasks.removeValue(forKey: id)?.cancel()
        if id == .settings {
            prepareSettingsPresentation()
        }

        if let existing = trackedWindows[id], shouldReuseWindow(existing, id: id) {
            openWindows.insert(id)
            if id == .settings {
                applySettingsOpenedState()
            }
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            diagLog.debug("Reusing window with id: \(id)")
            presentManagedWindow(existing, id: id)
            return
        }

        if let stale = trackedWindows.removeValue(forKey: id) {
            stale.delegate = nil
            stale.close()
            Self.tearDownWindowHierarchy(stale)
            windowDelegates[id] = nil
        }

        let delegate = ThawWindowDelegate(id: id, appState: self)
        windowDelegates[id] = delegate
        if id == .settings {
            applySettingsOpenedState()
        }
        openWindows.insert(id)
        let window = windowFactory(id, self, delegate)
        trackedWindows[id] = window
        diagLog.debug("Created and opened lazy window with id: \(id)")
        presentManagedWindow(window, id: id)
    }

    func dismissWindow(_ id: ThawWindowIdentifier) {
        diagLog.debug("Dismissing window with id: \(id)")
        openWindows.remove(id)
        if id == .settings {
            navigationState.cancelSettingsPresentation()
            navigationState.isSettingsPresented = false
        }
        guard let window = trackedWindows[id] else { return }
        Task { @MainActor [weak self, weak window] in
            guard
                let self, let window, !self.isWindowOpen(id), self.trackedWindows[id] === window
            else {
                return
            }
            window.close()
        }
    }

    /// Tracks whether the given managed window is currently open.
    func isWindowOpen(_ id: ThawWindowIdentifier) -> Bool {
        openWindows.contains(id)
    }

    func handleManagedWindowWillClose(id: ThawWindowIdentifier, window: NSWindow) {
        guard trackedWindows[id] === window else { return }
        openWindows.remove(id)
        if id == .settings {
            navigationState.cancelSettingsPresentation()
            navigationState.isSettingsPresented = false
        }
        if id == .whatsNew {
            pendingUpdateVersion = nil
        }
        if !SettingsProcessApp.isRequested, !hasOpenWindow, !navigationState.isThawBarPresented, !navigationState.isSearchPresented {
            deactivate(withPolicy: .accessory)
        }
        scheduleWindowTeardown(for: id)
        MemoryReclaimer.scheduleRelief(reason: "\(id) closed")
    }

    /// Releases AppKit/SwiftUI structures and backing surfaces retained by a closed window after the grace period.
    func tearDownClosedWindow(for id: ThawWindowIdentifier) {
        windowTeardownTasks.removeValue(forKey: id)?.cancel()
        guard
            !isWindowOpen(id), let window = trackedWindows[id], !window.isVisible, !window.isMiniaturized
        else {
            return
        }
        autoreleasepool {
            Self.tearDownWindowHierarchy(window)
        }
        windowDelegates[id] = nil
        trackedWindows[id] = nil
        _ = malloc_zone_pressure_relief(nil, 0)
        MemoryReclaimer.scheduleRelief(reason: "\(id) teardown")
    }

    static func tearDownWindowHierarchy(_ window: NSWindow, clearDelegate: Bool = true) {
        window.initialFirstResponder = nil
        window.makeFirstResponder(nil)
        window.unregisterDraggedTypes()
        window.orderOut(nil)
        if window.styleMask.contains(.titled) {
            for index in window.titlebarAccessoryViewControllers.indices.reversed() {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            window.toolbar?.isVisible = false
            window.toolbar = nil
        }
        window.contentViewController?.view.unregisterDraggedTypes()
        window.contentViewController?.view.layer?.contents = nil
        window.contentViewController = nil
        window.contentView?.unregisterDraggedTypes()
        window.contentView?.nextKeyView = nil
        window.contentView?.layer?.contents = nil
        window.contentView = nil
        if clearDelegate {
            window.delegate = nil
        }
    }

    static func defaultMakeManagedWindow(
        id: ThawWindowIdentifier,
        appState: AppState,
        delegate: NSWindowDelegate
    ) -> NSWindow {
        switch id {
        case .settings:
            SettingsWindow.makeWindow(appState: appState, delegate: delegate)
        case .permissions:
            PermissionsWindow.makeWindow(appState: appState, delegate: delegate)
        case .whatsNew:
            WhatsNewWindow.makeWindow(appState: appState, delegate: delegate)
        case .acknowledgements:
            AcknowledgementsWindow.makeWindow(appState: appState, delegate: delegate)
        }
    }

    // MARK: - Private helpers

    private func shouldReuseWindow(_ window: NSWindow, id: ThawWindowIdentifier) -> Bool {
        if id == .permissions, !window.isVisible {
            // Onboarding / permission recovery re-evaluates its stage cleanly on each opening.
            return false
        }
        return window.contentViewController != nil || window.contentView != nil
    }

    private func presentManagedWindow(_ window: NSWindow, id: ThawWindowIdentifier) {
        if !SettingsProcessApp.isRequested {
            activate(withPolicy: .regular)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
        // Re-assert key window once AppKit finishes any .accessory -> .regular policy transition.
        Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(60))
            guard
                let self, let window, self.isWindowOpen(id), self.trackedWindows[id] === window, window.isVisible, !window.isKeyWindow
            else {
                return
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func scheduleWindowTeardown(for id: ThawWindowIdentifier) {
        windowTeardownTasks.removeValue(forKey: id)?.cancel()
        windowTeardownTasks[id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.windowTeardownDelay)
            } catch {
                return
            }
            self?.tearDownClosedWindow(for: id)
        }
    }

    private func applySettingsOpenedState() {
        navigationState.isSettingsPresented = true

        // Show consent only for completed tours without an update answer.
        // Unseen tours answer in the permissions window, even alongside restored Settings; wait for consent.
        if Constants.supportsSparkleUpdates, Defaults.bool(forKey: .hasSeenOnboarding), !Defaults.bool(forKey: .hasSeenUpdateConsent) {
            isUpdateConsentPresented = true
        } else if Defaults.bool(forKey: .hasSeenUpdateConsent) {
            startUpdaterIfNeeded()
        }

        // Select About after construction to avoid losing sidebar rendering; defer What's New while the consent sheet is open.
        if navigationState.isWhatsNewRequested, !isUpdateConsentPresented {
            navigationState.settingsNavigationIdentifier = .about
        }
    }

    // MARK: - Activation, restart, and permissions

    /// exit(0) bypasses termination teardown; run it here to prevent macOS 27 ghost icons with dead menus after relaunch.
    func restartSelf() {
        guard !isRestarting else { return }
        isRestarting = true

        // Save image cache to disk before restarting so new instance can load it
        imageCache.saveToDisk()

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        config.promptsUserIfNeeded = false
        config.arguments = SingleInstanceRule.relaunchArguments(replacing: ProcessInfo.processInfo.processIdentifier)

        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
                // Restore blocked items before exit so none remain off-screen; this is a no-op on macOS 27.
                _ = await itemManager.restoreBlockedItemsToVisible()
                menuBarManager.tearDownControlItemsForTermination()
                diagLog.info("Restart: tore down control items, waiting for MenuBarAgent to reclaim")
                try? await Task.sleep(for: .milliseconds(150))
                try? await Task.sleep(for: .milliseconds(500))
                exit(0)
            } catch {
                // Report asynchronous relaunch failures here so every triggering control gets visible feedback.
                diagLog.error("Failed to relaunch app: \(error.localizedDescription)")
                isRestarting = false
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn’t relaunch \(Constants.displayName)")
                alert.informativeText = String(
                    localized: "\(Constants.displayName) could not open a second copy of itself, so it stayed open and nothing changed. Quit and open it again to finish."
                )
                alert.runModal()
            }
        }
    }

    /// Centralizes policy changes for focus-drop attribution; DiagLog avoids stack-capture cost when diagnostics are off.
    func applyActivationPolicy(
        _ policy: NSApplication.ActivationPolicy,
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace setActivationPolicy \(policy.rawValue) from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )
        NSApp.setActivationPolicy(policy)
    }

    func restoreAccessoryPolicyIfUnused(
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace restoreAccessoryPolicyIfUnused from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )
        guard NSApp.activationPolicy() == .regular, openWindows.isEmpty, !navigationState.isSettingsPresented, !navigationState.isThawBarPresented, !navigationState.isSearchPresented, !(menuBarManager.layoutEditorPanelIfCreated?.isShown == true), !menuBarManager.isHidingApplicationMenus, NSApp.modalWindow == nil, !NSApp.windows.contains(where: {
            ($0.isVisible || $0.isMiniaturized) && ($0.canBecomeKey || $0.canBecomeMain)
        })
        else { return }

        diagLog.debug("No windows or panels need activation, switching to accessory policy")
        applyActivationPolicy(.accessory)
    }

    /// Reassert activation through NSRunningApplication after policy changes because NSApp.activate alone is unreliable.
    /// Prefer handoff from the frontmost app to avoid a Dock bounce.
    func activate(
        withPolicy policy: NSApplication.ActivationPolicy? = nil,
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace activate policy=\(String(describing: policy)) from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )

        if let policy {
            applyActivationPolicy(policy)
        }

        NSApp.activate(ignoringOtherApps: true)

        Task {
            try? await Task.sleep(for: .milliseconds(50))
            let frontmost = NSWorkspace.shared.frontmostApplication
            diagLog.debug(
                "focus-trace activate re-assert after 50ms frontmost=\(frontmost?.bundleIdentifier ?? "nil") stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
            )
            if let frontmost {
                NSRunningApplication.current.activate(from: frontmost)
            } else {
                NSRunningApplication.current.activate()
            }
        }
    }

    /// Gives up focus, optionally dropping back to an accessory process on the
    /// way out so the app leaves the Dock and the app switcher.
    func deactivate(
        withPolicy policy: NSApplication.ActivationPolicy? = nil,
        callerFile: String = #fileID,
        callerLine: Int = #line
    ) {
        diagLog.debug(
            "focus-trace deactivate policy=\(String(describing: policy)) from \(callerFile):\(callerLine) stack=\(Thread.callStackSymbols.prefix(8).joined(separator: " | "))"
        )

        if let policy {
            applyActivationPolicy(policy)
        }
        NSApp.deactivate()
    }

    /// Whether the app currently holds the grant named by key.
    func isPermissionGranted(_ key: AppPermissions.PermissionKey) -> Bool {
        switch key {
        case .accessibility: permissions.accessibility.hasPermission
        case .screenRecording: permissions.screenRecording.hasPermission
        case .fullDiskAccess: permissions.fullDiskAccess.hasPermission
        case .controlCenterAppList: permissions.controlCenterAppList.hasPermission
        }
    }
}
