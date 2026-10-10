//
//  Permission.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import SwiftUI
import ThawCapture

// MARK: - Permission

/// Checks and requests one app permission.
@MainActor
@Observable
class Permission: Identifiable {
    private(set) var hasPermission = false {
        didSet {
            // The polling timer reassigns this every few seconds; only an
            // actual transition should notify the owner.
            guard oldValue != hasPermission else { return }
            if hasPermission {
                wasDeclined = false
                awaitingPromptAnswer = false
            }
            onChange?()
        }
    }

    /// A shown prompt remained ungranted, so surfaces may offer System Settings instead of waiting.
    /// Persists across ungranted requests until a grant; requests without a prompt open Settings directly and do not count.
    private(set) var wasDeclined = false

    /// Set by a request that showed the system prompt, cleared by the poll
    /// tick that turns it into wasDeclined or by the grant landing.
    private var awaitingPromptAnswer = false

    /// Notify owners only after a changed permission value is stored.
    @ObservationIgnored
    var onChange: (() -> Void)?

    let title: String

    let iconName: String

    let iconColor: Color

    let details: [String]

    /// Shorter copy for onboarding cards; falls back to details when unset.
    let shortDetails: [String]?

    /// Details shown in compact onboarding layouts.
    var onboardingDetails: [String] {
        shortDetails ?? details
    }

    /// Whether the app requires this permission to work.
    let isRequired: Bool

    /// The URL of the settings pane to open.
    private let settingsURL: URL?

    /// The function that checks permissions.
    private let check: () -> Bool

    /// An asynchronous fallback for permissions whose running-process state
    /// can lag behind their synchronous system check.
    private let asyncCheck: (() async -> Bool)?

    /// Reports granted, then prompted; back off on declined prompts and fall back to System Settings when no prompt appeared.
    private let request: (@escaping @MainActor @Sendable (Bool, Bool) -> Void) -> Void

    /// Observer that runs on a timer to check permissions.
    @ObservationIgnored
    private var timerCancellable: AnyCancellable?

    /// Refreshes permission state when the app becomes active after opening
    /// settingsURL (e.g. returning from System Settings).
    @ObservationIgnored
    private var settingsReturnCancellable: AnyCancellable?

    /// Injectable polling interval lets tests avoid real-time waits; production uses the default.
    @ObservationIgnored
    private let pollInterval: TimeInterval

    /// Stop polling after consecutive ungranted ticks (three minutes by default) to avoid session-long wakes after decline.
    /// Settings-return observation catches late grants; visible permission surfaces can rearm polling.
    @ObservationIgnored
    private let ungrantedPollBudget: Int

    /// Consecutive ungranted ticks since the poll was (re)armed.
    @ObservationIgnored
    private var ungrantedTickCount = 0

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - shortDetails: Optional shorter onboarding copy.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions, reporting whether
    ///     access was granted and whether a system prompt was surfaced.
    ///   - pollInterval: Seconds between ungranted re-checks. Defaults to 3.
    ///   - ungrantedPollBudget: Consecutive ungranted re-checks before the
    ///     poll stops itself. At the default interval, three minutes.
    init(
        title: String,
        iconName: String,
        iconColor: Color,
        details: [String],
        shortDetails: [String]? = nil,
        isRequired: Bool,
        settingsURL: URL?,
        check: @escaping () -> Bool,
        asyncCheck: (() async -> Bool)? = nil,
        request: @escaping (@escaping @MainActor @Sendable (Bool, Bool) -> Void) -> Void,
        pollInterval: TimeInterval = 3,
        ungrantedPollBudget: Int = 60
    ) {
        self.title = title
        self.iconName = iconName
        self.iconColor = iconColor
        self.details = details
        self.shortDetails = shortDetails
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.check = check
        self.asyncCheck = asyncCheck
        self.request = request
        self.pollInterval = pollInterval
        self.ungrantedPollBudget = ungrantedPollBudget
        self.hasPermission = check()
        configureCancellables()
    }

    /// Poll until granted or the ungranted budget expires; avoid needless wakes after grant or decline.
    private func configureCancellables() {
        ungrantedTickCount = 0
        // Check before subscribing; a setup-time sink tick cannot cancel a subscription that has not been stored yet.
        handlePollTick()
        guard !hasPermission, ungrantedTickCount < ungrantedPollBudget else { return }
        timerCancellable = Timer.publish(every: pollInterval, tolerance: 0.5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handlePollTick()
            }
    }

    /// Publish only transitions and stop at the ungranted budget; internal access lets tests drive ticks without timers.
    func handlePollTick() {
        let granted = check()
        setHasPermissionIfChanged(granted)
        if granted {
            stopCheck()
            return
        }
        ungrantedTickCount += 1
        if awaitingPromptAnswer {
            awaitingPromptAnswer = false
            wasDeclined = true
        }
        if ungrantedTickCount >= ungrantedPollBudget {
            timerCancellable?.cancel()
            timerCancellable = nil
            // Keep the settings-return observer armed to catch grants after the polling budget expires.
        }
    }

    /// Visible onboarding or permission surfaces rearm polling through AppPermissions, not for the lifetime of a declined prompt.
    func resumePollingIfNeeded() {
        guard !hasPermission, timerCancellable == nil else { return }
        configureCancellables()
    }

    /// Whether the ungranted poll is currently armed.
    var isPolling: Bool {
        timerCancellable != nil
    }

    /// Observable notifies on every assignment; skip unchanged values to avoid rerendering permission views on every tick.
    private func setHasPermissionIfChanged(_ granted: Bool) {
        guard granted != hasPermission else { return }
        hasPermission = granted
    }

    /// Open Settings automatically only when no prompt appeared; respect decline until the user requests again or chooses Settings.
    /// Arm preflight-only activation checks either way to recognize later grants without prompting.
    func performRequest() {
        configureCancellables()
        if settingsURL != nil {
            armSettingsReturnObserver()
        }
        request { [weak self] granted, prompted in
            guard let self else { return }
            if granted {
                setHasPermissionIfChanged(true)
                stopCheck()
                return
            }
            if prompted {
                // Prompt requests return before the user's answer; defer the ungranted verdict to the next poll tick.
                awaitingPromptAnswer = true
            } else {
                openSettingsPane()
            }
        }
    }

    /// Whether openSettingsPane() has a pane to open.
    var hasSettingsPane: Bool {
        settingsURL != nil
    }

    /// No-op without a pane URL; call only for no-prompt fallback or an explicit user choice after decline.
    /// Never open Settings alongside a prompt or automatically after decline.
    func openSettingsPane() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    /// Re-checks (preflight only) whenever the app becomes active again, so
    /// a grant made in System Settings is recognized on return.
    private func armSettingsReturnObserver() {
        settingsReturnCancellable?.cancel()
        settingsReturnCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Activation checks must be synchronous and preflight-only; reserve asynchronous probes for explicit user actions.
                self?.refreshStatus()
            }
    }

    /// Re-checks current system authorization immediately.
    func refreshStatus() {
        setHasPermissionIfChanged(check())
    }

    /// Re-checks current system authorization, including any asynchronous
    /// system probe needed to observe a grant without relaunching.
    func refreshStatus() async {
        let synchronouslyGranted = check()
        guard !synchronouslyGranted, let asyncCheck else {
            setHasPermissionIfChanged(synchronouslyGranted)
            return
        }
        let asynchronouslyGranted = await asyncCheck()
        setHasPermissionIfChanged(asynchronouslyGranted)
    }

    /// Stops running the permission check.
    func stopCheck() {
        timerCancellable?.cancel()
        timerCancellable = nil
        settingsReturnCancellable?.cancel()
        settingsReturnCancellable = nil
    }
}

// MARK: - AccessibilityPermission

/// The Accessibility permission, required for Thaw to detect, move, and
/// interact with menu bar items on the user's behalf.
final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Accessibility"),
            iconName: "accessibility",
            iconColor: .blue,
            details: [
                String(localized: "Detect the menu bar items on your Mac and where they're positioned."),
                String(localized: "Move menu bar items to rearrange or hide them."),
                String(localized: "Click menu bar items on your behalf, such as when using the search bar."),
            ],
            shortDetails: [
                String(localized: "Detect menu bar items on your Mac and where they're positioned."),
                String(localized: "Move menu bar items to rearrange or hide them."),
            ],
            isRequired: true,
            // Ungranted AX trust checks always report prompted, so this URL is only for explicit Settings choices and return checks.
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            check: {
                AXHelpers.isProcessTrusted()
            },
            request: { completion in
                // Untrusted checks show guidance and return immediately; ungranted means prompted, not necessarily refused.
                let granted = AXHelpers.isProcessTrusted(prompt: true)
                completion(granted, !granted)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

/// Optional permission for menu bar colors, item previews and visual search; Thaw still runs without it.
final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Screen Recording"),
            iconName: "record.circle",
            iconColor: .red,
            details: [
                String(localized: "Show live previews of your menu bar items."),
                String(localized: "Sample colors from the menu bar to adjust its tint and appearance."),
                String(localized: "Find menu bar items visually when searching."),
            ],
            shortDetails: [
                String(localized: "Show live previews of your menu bar items."),
                String(localized: "Sample colors from the menu bar to adjust tint."),
            ],
            isRequired: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            check: {
                ScreenCapture.recomputeCachedScreenRecordingPermission()
            },
            asyncCheck: {
                await ScreenCapture.refreshPermissions()
            },
            request: { completion in
                ScreenCapture.requestPermissions(completion: completion)
            }
        )
    }
}
