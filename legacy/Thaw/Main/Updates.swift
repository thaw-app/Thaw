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
    /// A background check that finds nothing is silent, so this flag keeps the
    /// alert's promise: an empty alpha feed opens the releases page instead.
    @ObservationIgnored
    private var isCheckingAfterCompatibilityWarning = false

    /// Opens a URL on the user's behalf.
    ///
    /// Injectable so a test can watch the compatibility alert's fallback fire
    /// without handing the running system a browser window.
    @ObservationIgnored
    var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }

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
            // Computed over UserDefaults, so Observation is registered by hand.
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
    /// The old "Development" flag migrates to beta, not alpha: alpha is now a
    /// different app, and moving users onto it unasked would swap the product.
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
        // A channel this system can't be offered falls back to beta, so alpha
        // users back on a supported macOS aren't stranded. Beta, since they left stable.
        guard stored.isAvailable(on: version) else {
            return .beta
        }
        return stored
    }

    /// A Boolean value that indicates whether to automatically check for updates.
    ///
    /// Backed by Sparkle's `updater`, so Observation is registered by hand
    /// with `access(keyPath:)`/`withMutation(keyPath:)`.
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
        // Weak self: KVO publishers can outlive us.
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

    /// Subscribes to the beta channel and looks for the build that supports
    /// the running macOS, falling back to the releases page.
    ///
    /// Called from ``MacOSCompatibilityWarning`` once the user accepts. The
    /// check runs in the background, so the user only sees the new build
    /// or the releases page.
    func checkForBetaUpdateAfterCompatibilityWarning() {
        beginCompatibilityCheck()
        #if DEBUG
            // Checking for updates hangs in debug mode, so the promise is
            // answered here rather than by a check that never runs.
            updateChannel = .beta
            resolveCompatibilityCheckWithReleasesPage()
        #else
            // Storing the channel schedules the check; asking again would open a
            // second session that Sparkle drops.
            startUpdaterIfNeeded()
            updateChannel = .beta
        #endif
    }

    /// Arms the promise the compatibility alert just made, so that whichever
    /// way the check ends, the ending is recognized as this one's.
    func beginCompatibilityCheck() {
        isCheckingAfterCompatibilityWarning = true
    }

    /// Answers the compatibility alert's promise with the releases page, if
    /// the check it started is the one that just ended empty.
    ///
    /// An empty check also aborts with `SUNoUpdateError`, so both endings call
    /// this and the flag decides which arrived first.
    func resolveCompatibilityCheckWithReleasesPage() {
        guard isCheckingAfterCompatibilityWarning else {
            return
        }
        isCheckingAfterCompatibilityWarning = false
        openURL(Constants.releasesURL)
    }

    /// Whether a scheduled update should be shown now rather than deferred.
    ///
    /// The compatibility alert asked for its check on the user's behalf, so
    /// its result is shown rather than deferred to a notification they may
    /// never have granted.
    func shouldShowScheduledUpdate(inImmediateFocus immediateFocus: Bool, appIsActive: Bool) -> Bool {
        if isCheckingAfterCompatibilityWarning {
            return true
        }
        return appIsActive ? immediateFocus : false
    }

    /// Whether an update being shown should also be announced by notification,
    /// closing the compatibility check on the way.
    ///
    /// The update window itself answers the alert, so a notification beside it
    /// would say the same thing twice.
    func shouldNotifyAboutUpdate(userInitiated: Bool) -> Bool {
        let answersCompatibilityWarning = isCheckingAfterCompatibilityWarning
        isCheckingAfterCompatibilityWarning = false
        return !userInitiated && !answersCompatibilityWarning
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
    /// Otherwise Sparkle prefers a `SUFeedURL` user default over Info.plist,
    /// so anything writing the app's defaults could redirect update checks.
    func feedURLString(for _: SPUUpdater) -> String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    /// Determines which update channels are allowed.
    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        Self.storedUpdateChannel().allowedSparkleChannels(on: ProcessInfo.processInfo.operatingSystemVersion)
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
        shouldShowScheduledUpdate(inImmediateFocus: immediateFocus, appIsActive: NSApp.isActive)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard shouldNotifyAboutUpdate(userInitiated: state.userInitiated), let appState else {
            return
        }
        appState.userNotificationManager.addRequest(
            with: .updateCheck,
            title: String(localized: "A new update is available"),
            body: String(localized: "Version \(update.displayVersionString) (\(update.versionString)) is now available")
        )
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
/// All three share the `SUFeedURL` feed and differ only in the
/// `sparkle:channel` tags they accept. Alpha is the rewrite for the next macOS.
///
/// Sparkle always allows the default (untagged, stable) channel, so every
/// subscriber sees stable items; the alpha version line runs ahead, so stable
/// never outranks it.
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
    /// Alpha is offered only on the macOS this build doesn't support, since
    /// elsewhere its builds can't run.
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
    /// Sparkle always adds the untagged stable items too, which is harmless
    /// while stable stays on 2.x and alpha on 3.x.
    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .beta: ["beta"]
        case .alpha: ["alpha"]
        }
    }

    /// The tags to accept on a system running `version`.
    ///
    /// On a macOS this build doesn't support, beta also takes alpha. Every
    /// 2.x beta there is a build that can't run, and the rewrite's items all
    /// require that macOS, so beta reaches the newest 3.x build whichever
    /// channel it was published on.
    func allowedSparkleChannels(on version: OperatingSystemVersion) -> Set<String> {
        guard self == .beta, UpdateChannel.alpha.isAvailable(on: version) else {
            return allowedSparkleChannels
        }
        return allowedSparkleChannels.union(UpdateChannel.alpha.allowedSparkleChannels)
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
