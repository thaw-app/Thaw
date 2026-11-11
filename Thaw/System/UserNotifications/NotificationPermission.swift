//
//  NotificationPermission.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Observation
import SwiftUI
import ThawUI
import UserNotifications

/// Whether Thaw may show notifications, as macOS last reported it.
nonisolated enum NotificationAuthorization: Equatable, Sendable {
    case allowed
    case off
    case notAsked

    /// Provisional and ephemeral grants count as allowed only while alerts are on.
    init(status: UNAuthorizationStatus, alertSetting: UNNotificationSetting) {
        switch status {
        case .notDetermined: self = .notAsked
        case .denied: self = .off
        default: self = alertSetting == .enabled ? .allowed : .off
        }
    }
}

/// The notifications row on Privacy, in the same row as the other permissions.
/// Thaw asks only when it first needs to notify, so this is where a refusal shows.
@MainActor
@Observable
final class NotificationPermission: PermissionPresentable {
    private(set) var authorization = NotificationAuthorization.notAsked

    /// Asks macOS, then reads the answer back. Set by UserNotificationManager.
    @ObservationIgnored var request: () -> Void = { /* Does nothing until the owner sets it. */ }

    func update(_ authorization: NotificationAuthorization) {
        if self.authorization != authorization {
            self.authorization = authorization
        }
    }

    var titleText: Text {
        Text("Notifications")
    }

    var iconName: String {
        "bell.badge"
    }

    var iconColor: Color {
        .red
    }

    var isRequired: Bool {
        false
    }

    var hasPermission: Bool {
        authorization == .allowed
    }

    var wasDeclined: Bool {
        authorization == .off
    }

    var hasSettingsPane: Bool {
        true
    }

    func performRequest() {
        request()
    }

    func openSettingsPane() {
        let id = Bundle.main.bundleIdentifier ?? Constants.bundleIdentifier
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
