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

    /// Tracks whether the running check was started by the macOS
    /// compatibility alert.
    ///
    /// That alert promises the user a build for a macOS this one does not
    /// support. A background check that finds nothing is silent, so the
    /// promise has to survive the check to be kept: an empty alpha feed
    /// sends them to the releases page rather than nowhere.
    @ObservationIgnored
    private var isCheckingAfterCompatibilityWarning = false

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

    /// The update channel the user is subscribed to.
    var updateChannel: UpdateChannel {
        get {
            // Computed over UserDefaults, so the @Observable macro cannot
            // track it automatically; register/notify Observation manually
            // (same pattern as the Sparkle-backed properties below).
            access(keyPath: \.updateChannel)
            return Self.storedUpdateChannel()
        }
        set {
            withMutation(keyPath: \.updateChannel) {
                Defaults.store.set(newValue.rawValue, forKey: "UpdateChannel")
                // Keep the superseded flag in step so downgrading to a build
                // that only knows the Bool leaves the user off stable rather
                // than silently back on it.
                Defaults.store.set(newValue != .stable, forKey: "AllowsBetaUpdates")
            }
            Task {
                guard hasStartedUpdater else { return }
                updater.checkForUpdatesInBackground()
            }
        }
    }

    /// Reads the stored channel, falling back to the flag that preceded it.
    ///
    /// Builds before the split offered a single "Development" setting whose
    /// subscribers received alpha and beta together. They migrate to beta,
    /// not alpha: alpha is now a different app on a different feed, and
    /// moving someone onto it without them asking would swap the product
    /// out from under them.
    static nonisolated func storedUpdateChannel(
        on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> UpdateChannel {
        let stored: UpdateChannel = if let raw = Defaults.store.string(forKey: "UpdateChannel"),
                                       let channel = UpdateChannel(rawValue: raw)
        {
            channel
        } else {
            Defaults.store.bool(forKey: "AllowsBetaUpdates") ? .beta : .stable
        }
        // A channel the running system cannot be offered is not honored
        // either, or a user who selected alpha and then moved back to a
        // supported macOS would stay pinned to the rewrite's feed and be
        // offered nothing at all. Beta rather than stable: they had opted
        // out of stable, and that much of the choice still applies.
        guard stored.isAvailable(on: version) else {
            return .beta
        }
        return stored
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

    /// Subscribes to the alpha channel and looks for the build that supports
    /// the running macOS, falling back to the releases page.
    ///
    /// Called from ``MacOSCompatibilityWarning`` once the user accepts the
    /// offer. The check runs in the background so that the only thing the
    /// user sees is its outcome: either Sparkle presenting the alpha build,
    /// or the releases page, which is where the promise lands while the feed
    /// still carries no alpha item.
    func checkForAlphaUpdateAfterCompatibilityWarning() {
        #if DEBUG
            // Checking for updates hangs in debug mode.
            NSWorkspace.shared.open(Constants.releasesURL)
        #else
            updateChannel = .alpha
            isCheckingAfterCompatibilityWarning = true
            startUpdaterIfNeeded()
            updater.checkForUpdatesInBackground()
        #endif
    }

    /// Answers the compatibility alert's promise with the releases page, if
    /// the check it started is the one that just ended empty.
    ///
    /// A check that finds nothing also aborts with `SUNoUpdateError`, and one
    /// that never reaches the feed only aborts, so both endings call this and
    /// the flag decides which of them arrived first.
    private func resolveCompatibilityCheckWithReleasesPage() {
        guard isCheckingAfterCompatibilityWarning else {
            return
        }
        isCheckingAfterCompatibilityWarning = false
        NSWorkspace.shared.open(Constants.releasesURL)
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
        Self.storedUpdateChannel().allowedSparkleChannels
    }

    func updaterDidNotFindUpdate(_: SPUUpdater) {
        resolveCompatibilityCheckWithReleasesPage()
    }

    func updater(_: SPUUpdater, didAbortWithError _: any Error) {
        resolveCompatibilityCheckWithReleasesPage()
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
        // The compatibility alert asked for this check on the user's behalf,
        // so its result is shown rather than deferred to a notification they
        // may never have granted.
        if isCheckingAfterCompatibilityWarning {
            return true
        }
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
        // The update window itself answers the compatibility alert, so a
        // notification beside it would say the same thing twice.
        let answersCompatibilityWarning = isCheckingAfterCompatibilityWarning
        isCheckingAfterCompatibilityWarning = false
        guard let appState else {
            return
        }
        if !state.userInitiated, !answersCompatibilityWarning {
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

// MARK: - UpdateChannel

/// A stream of releases the user can subscribe to.
///
/// All three share the feed named by `SUFeedURL` and differ only in which
/// `sparkle:channel` tags they accept: beta takes `beta`, alpha takes
/// `alpha`, and neither takes the other. Alpha is not the same product as
/// the other two, being the rewrite built against the next macOS, but it
/// does not need a feed of its own to stay apart from beta.
///
/// It cannot stay apart from stable, though. Sparkle's `allowedChannels`
/// only widens what an updater accepts: an item carrying no `sparkle:channel`
/// is on the default channel, and per `SPUUpdaterDelegate`, "the default
/// channel is always included in the allowed set". Every subscriber therefore
/// sees the stable items. They stop mattering because Sparkle offers the
/// newest allowed item, and the rewrite's version line runs ahead of the
/// shipping app's, so a stable release can never outrank an alpha one.
nonisolated enum UpdateChannel: String, CaseIterable, Identifiable {
    /// Released builds.
    case stable
    /// Release candidates and betas of the shipping app.
    case beta
    /// The rewritten app, for testing against a new macOS.
    case alpha

    var id: String {
        rawValue
    }

    /// The channels that can be offered on a system running `version`.
    static func availableCases(on version: OperatingSystemVersion) -> [UpdateChannel] {
        allCases.filter { $0.isAvailable(on: version) }
    }

    /// Whether this channel can be offered on a system running `version`.
    ///
    /// Alpha is the rewrite built against the macOS this build does not
    /// support, so it is offered only there. Showing it earlier would
    /// advertise a track whose builds the user cannot run, and hide the
    /// shipping app behind an update that would never arrive.
    func isAvailable(on version: OperatingSystemVersion) -> Bool {
        switch self {
        case .stable, .beta:
            true
        case .alpha:
            version.majorVersion >= MacOSCompatibilityWarning.firstUnsupportedMajorVersion
        }
    }

    /// The `sparkle:channel` values an appcast item may carry and still be
    /// offered to a subscriber of this channel.
    ///
    /// Sparkle always adds the default channel to the allowed set, so every
    /// subscriber sees the untagged stable items too. That is harmless while
    /// stable stays on the 2.x line: Sparkle offers the newest allowed item,
    /// and an alpha subscriber's 3.x item outranks anything stable can carry.
    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .beta: ["beta"]
        case .alpha: ["alpha"]
        }
    }

    /// A string to show in the interface.
    var localized: LocalizedStringKey {
        switch self {
        case .stable: LocalizedStringKey("Stable")
        case .beta: LocalizedStringKey("Beta")
        case .alpha: LocalizedStringKey("Alpha")
        }
    }
}
