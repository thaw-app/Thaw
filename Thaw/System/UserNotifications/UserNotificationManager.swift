//
//  UserNotificationManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import UserNotifications

@MainActor
final class UserNotificationManager: NSObject {
    private let diagLog = DiagLog(category: "UserNotificationManager")
    private(set) weak var appState: AppState?
    private var activationObserver: (any NSObjectProtocol)?

    /// Whether a notification Thaw posts can show an alert, read at setup and each time
    /// Thaw becomes active. Optimistic until the first read returns.
    private(set) var canAlert = true

    var notificationCenter: UNUserNotificationCenter {
        .current()
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        notificationCenter.delegate = self
        refreshAlertPermission()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAlertPermission() }
        }
    }

    private func refreshAlertPermission() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            canAlert = [.authorized, .provisional].contains(settings.authorizationStatus)
                && settings.alertSetting == .enabled
        }
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
    func addRequest(with identifier: UserNotificationIdentifier, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

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
        case .hotkeyToggleFeedback:
            break
        case nil:
            break
        }
    }
}
