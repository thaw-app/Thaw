//
//  Permission.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import SwiftUI

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
class Permission: ObservableObject, Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    @Published private(set) var hasPermission = false

    /// The title of the permission.
    let title: String

    /// The name of the system symbol image to display next to the title.
    let iconName: String

    /// The color of the icon displayed next to the title.
    let iconColor: Color

    /// Descriptive details for the permission.
    let details: [String]

    /// Shorter copy for onboarding cards; falls back to ``details`` when unset.
    let shortDetails: [String]?

    /// Details shown in compact onboarding layouts.
    var onboardingDetails: [String] {
        shortDetails ?? details
    }

    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool

    /// The URL of the settings pane to open.
    private let settingsURL: URL?

    /// The function that checks permissions.
    private let check: () -> Bool

    /// The function that requests permissions.
    private let request: () -> Void

    /// Observer that runs on a timer to check permissions.
    private var timerCancellable: AnyCancellable?

    /// Refreshes permission state when the app becomes active after opening
    /// ``settingsURL`` (e.g. returning from System Settings).
    private var settingsReturnCancellable: AnyCancellable?

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - shortDetails: Optional shorter onboarding copy.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    init(
        title: String,
        iconName: String,
        iconColor: Color,
        details: [String],
        shortDetails: [String]? = nil,
        isRequired: Bool,
        settingsURL: URL?,
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.iconColor = iconColor
        self.details = details
        self.shortDetails = shortDetails
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.check = check
        self.request = request
        self.hasPermission = check()
        configureCancellables()
    }

    /// Sets up the internal observers for the permission.
    ///
    /// Polls ``check`` on a timer until the permission is granted, at which
    /// point the timer cancels itself — there's no need to keep checking once
    /// the app already has what it needs.
    private func configureCancellables() {
        timerCancellable = Timer.publish(every: 3, tolerance: 0.5, on: .main, in: .default)
            .autoconnect()
            .merge(with: Just(.now))
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                let granted = check()
                hasPermission = granted
                if granted {
                    timerCancellable?.cancel()
                    timerCancellable = nil
                    settingsReturnCancellable?.cancel()
                    settingsReturnCancellable = nil
                }
            }
    }

    /// Performs the request and opens the System Settings app to the appropriate pane.
    func performRequest() {
        request()
        configureCancellables()
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
            settingsReturnCancellable?.cancel()
            settingsReturnCancellable = NotificationCenter.default
                .publisher(for: NSApplication.didBecomeActiveNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.refreshStatus()
                }
        }
    }

    /// Re-checks current system authorization immediately.
    func refreshStatus() {
        hasPermission = check()
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
            settingsURL: nil,
            check: {
                AXHelpers.isProcessTrusted()
            },
            request: {
                AXHelpers.isProcessTrusted(prompt: true)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

/// The Screen Recording permission, used for sampling menu bar colors,
/// previewing menu bar items, and visual search. Optional — Thaw can run in
/// a limited mode without it.
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
                ScreenCapture.cachedCheckPermissions(reset: true)
            },
            request: {
                ScreenCapture.requestPermissions()
            }
        )
    }
}
