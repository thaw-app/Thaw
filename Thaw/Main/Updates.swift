//
//  Updates.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation
import Sparkle
import SwiftUI

/// Manager for app updates.
@MainActor
@Observable
final class UpdatesManager: NSObject {
    /// A Boolean value that indicates whether the user can check for updates.
    var canCheckForUpdates = false

    /// The date of the last update check.
    var lastUpdateCheckDate: Date?

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Tracks whether the updater has been started.
    private var hasStartedUpdater = false

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    private var debugUpdateMessage: String {
        String(localized: "Checking for updates is not supported in debug mode.")
    }

    /// The underlying updater controller.
    @ObservationIgnored
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
            // Computed over UserDefaults, so the @Observable macro cannot
            // track it automatically; register/notify Observation manually
            // (same pattern as the Sparkle-backed properties below).
            access(keyPath: \.allowsBetaUpdates)
            return Defaults.store.bool(forKey: "AllowsBetaUpdates")
        }
        set {
            withMutation(keyPath: \.allowsBetaUpdates) {
                Defaults.store.set(newValue, forKey: "AllowsBetaUpdates")
            }
            Task {
                guard hasStartedUpdater else { return }
                updater.checkForUpdatesInBackground()
            }
        }
    }

    /// `automaticallyChecksForUpdates`/`automaticallyDownloadsUpdates` are
    /// computed properties backed by Sparkle's `updater`, not by a stored
    /// property the @Observable macro can track automatically. The old
    /// Combine `objectWillChange.send()` poke is replaced with the macro-
    /// synthesized `access(keyPath:)`/`withMutation(keyPath:)` calls, which
    /// register/notify Observation access for a specific property exactly
    /// like a stored property would.
    /// A Boolean value that indicates whether to automatically check for updates.
    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                updater.automaticallyChecksForUpdates = newValue
                if newValue {
                    Defaults.set(true, forKey: .hasSeenUpdateConsent)
                }
            }
        }
    }

    /// A Boolean value that indicates whether to automatically download updates.
    var automaticallyDownloadsUpdates: Bool {
        get {
            access(keyPath: \.automaticallyDownloadsUpdates)
            return updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyDownloadsUpdates) {
                updater.automaticallyDownloadsUpdates = newValue
                if newValue {
                    Defaults.set(true, forKey: .hasSeenUpdateConsent)
                }
            }
        }
    }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        _ = updaterController
        // A `SUFeedURL` user-defaults entry would otherwise take precedence
        // over Info.plist and silently redirect update checks; the delegate's
        // `feedURLString(for:)` already ignores it, this just scrubs the key.
        updater.clearFeedURLFromUserDefaults()
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
        var c = Set<AnyCancellable>()
        // `assign(to: &$property)` relied on the Combine `@Published`
        // projection, which no longer exists now that this class is
        // @Observable. Replaced with an explicit `.sink` that writes the
        // plain property (weak self, since KVO publishers can outlive us).
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &c)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in
                self?.lastUpdateCheckDate = value
            }
            .store(in: &c)
        cancellables = c
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

    /// Pins the appcast feed to the URL declared in Info.plist.
    ///
    /// Without this, Sparkle resolves the feed as user defaults → Info.plist,
    /// so a stray `defaults write … SUFeedURL …` (or any process writing to
    /// the app's defaults) could point update checks at a foreign server.
    /// Answering from the delegate short-circuits that lookup.
    func feedURLString(for _: SPUUpdater) -> String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    /// Determines which update channels are allowed.
    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        if Defaults.store.bool(forKey: "AllowsBetaUpdates") {
            return ["alpha", "beta"]
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

extension UpdatesManager: @MainActor SPUStandardUserDriverDelegate {
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
