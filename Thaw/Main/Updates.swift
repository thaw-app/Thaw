//
//  Updates.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import Sparkle
import SwiftUI

/// Manager for app updates.
@MainActor
final class UpdatesManager: NSObject, ObservableObject {
    /// A Boolean value that indicates whether the user can check for updates.
    @Published var canCheckForUpdates = false

    /// The date of the last update check.
    @Published var lastUpdateCheckDate: Date?

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Whether the user has already handled the permission prompt.
    private var hasHandledPermission = Defaults.bool(forKey: .hasSeenUpdateConsent)

    /// Tracks whether the updater has been started.
    private var hasStartedUpdater = false

    private var debugUpdateMessage: String {
        String(localized: "Checking for updates is not supported in debug mode.")
    }

    /// The underlying updater controller.
    private(set) lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    /// The underlying updater.
    var updater: SPUUpdater {
        updaterController.updater
    }

    /// A Boolean value that indicates whether the user wants to receive beta updates.
    var allowsBetaUpdates: Bool {
        get {
            UserDefaults.standard.bool(forKey: "AllowsBetaUpdates")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "AllowsBetaUpdates")
            Task {
                guard hasStartedUpdater else { return }
                updater.checkForUpdatesInBackground()
            }
        }
    }

    /// A Boolean value that indicates whether to automatically check for updates.
    var automaticallyChecksForUpdates: Bool {
        get {
            updater.automaticallyChecksForUpdates
        }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
            if newValue {
                Defaults.set(true, forKey: .hasSeenUpdateConsent)
            }
        }
    }

    /// A Boolean value that indicates whether to automatically download updates.
    var automaticallyDownloadsUpdates: Bool {
        get {
            updater.automaticallyDownloadsUpdates
        }
        set {
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
            if newValue {
                Defaults.set(true, forKey: .hasSeenUpdateConsent)
            }
        }
    }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        _ = updaterController
        configureCancellables()
    }

    /// Starts the updater if it hasn't been started yet.
    func startUpdaterIfNeeded() {
        guard !hasStartedUpdater else {
            return
        }
        hasStartedUpdater = true
        updaterController.startUpdater()
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }

    /// Checks for app updates.
    @objc func checkForUpdates() {
        #if DEBUG
            // Checking for updates hangs in debug mode.
            let alert = NSAlert()
            alert.messageText = debugUpdateMessage
            alert.runModal()
        #else
            guard let appState else {
                return
            }
            startUpdaterIfNeeded()
            // Activate the app in case an alert needs to be displayed.
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
            updater.checkForUpdates()
        #endif
    }
}

// MARK: UpdatesManager: SPUUpdaterDelegate

extension UpdatesManager: SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        // We show our own blocking sheet; if consent already handled, skip Sparkle prompt.
        if Defaults.bool(forKey: .hasSeenUpdateConsent) {
            return false
        }
        // If somehow Sparkle asks before our sheet, block and let our UI drive the choice.
        return false
    }

    /// Determines which update channels are allowed.
    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        if UserDefaults.standard.bool(forKey: "AllowsBetaUpdates") {
            return ["beta"]
        }
        return []
    }

    func updater(_: SPUUpdater, willScheduleUpdateCheckAfterDelay _: TimeInterval) {
        guard let appState else {
            return
        }
        appState.userNotificationManager.requestAuthorization()
    }
}

// MARK: UpdatesManager: SPUStandardUserDriverDelegate

extension UpdatesManager: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        if NSApp.isActive {
            return immediateFocus
        } else {
            return false
        }
    }

    func standardUserDriverWillHandleShowingUpdate(
        _: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard let appState else {
            return
        }
        if !state.userInitiated {
            appState.userNotificationManager.addRequest(
                with: .updateCheck,
                title: String(localized: "A new update is available"),
                body: String(localized: "Version \(update.displayVersionString) (\(update.versionString)) is now available")
            )
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        guard let appState else {
            return
        }
        appState.userNotificationManager.removeDeliveredNotifications(with: [.updateCheck])
    }
}
