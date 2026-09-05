//
//  UserNotificationManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import UserNotifications

/// Manager for user notifications.
@MainActor
final class UserNotificationManager: NSObject {
    private let diagLog = DiagLog(category: "UserNotificationManager")
    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The current notification center.
    var notificationCenter: UNUserNotificationCenter {
        .current()
    }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        notificationCenter.delegate = self
    }

    /// Requests authorization to allow user notifications for the app.
    func requestAuthorization() {
        Task {
            do {
                try await notificationCenter.requestAuthorization(options: [.badge, .alert, .sound])
            } catch {
                diagLog.error("Failed to request notification authorization: \(error)")
            }
        }
    }

    /// Schedules the delivery of a local notification.
    func addRequest(
        with identifier: UserNotificationIdentifier,
        title: String,
        body: String,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: identifier.rawValue,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }

    /// Removes the notifications from Notification Center that match the given identifiers.
    func removeDeliveredNotifications(with identifiers: [UserNotificationIdentifier]) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers.map(\.rawValue))
    }
}

extension UserNotificationManager {
    /// What opening a failed-move notification should do.
    nonisolated enum MoveFailureOpenAction: Equatable {
        case revealReport(URL)
        case openSettings
    }

    /// Resolves notification payload state without invoking AppKit, so a
    /// pruned or malformed report path safely falls back to Settings.
    static nonisolated func moveFailureOpenAction(
        reportPath: String?,
        reportExists: Bool
    ) -> MoveFailureOpenAction {
        guard let reportPath, !reportPath.isEmpty, reportExists else {
            return .openSettings
        }
        return .revealReport(URL(fileURLWithPath: reportPath))
    }
}

// MARK: UserNotificationManager: UNUserNotificationCenterDelegate

extension UserNotificationManager: @MainActor UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }

        guard let appState else {
            return
        }

        switch UserNotificationIdentifier(rawValue: response.notification.request.identifier) {
        case .updateCheck:
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
                break
            }
            appState.updatesManager.checkForUpdates()
        case .triggerFired:
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
                break
            }
            // Tapping a trigger notification opens Settings to the Triggers pane.
            appState.navigationState.settingsNavigationIdentifier = .triggers
            appState.openWindow(.settings)
        case .hotkeyToggleFeedback:
            // Pure feedback banner; tapping it carries no action.
            break
        case .moveFailed:
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
                break
            }
            let reportPath = response.notification.request.content.userInfo["reportPath"] as? String
            let reportExists = reportPath.map(FileManager.default.fileExists(atPath:)) ?? false
            switch Self.moveFailureOpenAction(
                reportPath: reportPath,
                reportExists: reportExists
            ) {
            case let .revealReport(url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .openSettings:
                appState.openWindow(.settings)
            }
        case nil:
            break
        }
    }
}
