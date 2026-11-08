//
//  NotificationPermissionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw
import UserNotifications

@MainActor
@Suite("Notification permission")
struct NotificationPermissionTests {
    @Test("macOS's answer maps to allowed, off or not asked", arguments: [
        (UNAuthorizationStatus.notDetermined, UNNotificationSetting.notSupported, NotificationAuthorization.notAsked),
        (.denied, .disabled, .off),
        (.authorized, .enabled, .allowed),
        (.authorized, .disabled, .off),
        (.provisional, .enabled, .allowed),
        (.provisional, .disabled, .off),
    ])
    func mapping(status: UNAuthorizationStatus, alert: UNNotificationSetting, expected: NotificationAuthorization) {
        #expect(NotificationAuthorization(status: status, alertSetting: alert) == expected)
    }

    @Test("Not asked offers the request; off leads to System Settings; allowed is granted")
    func rowStates() {
        let permission = NotificationPermission()
        var requested = 0
        permission.request = { requested += 1 }

        #expect(!permission.hasPermission)
        #expect(!permission.wasDeclined, "not asked yet asks rather than sending people to System Settings")
        permission.performRequest()
        #expect(requested == 1)

        permission.update(.off)
        #expect(permission.wasDeclined)
        #expect(permission.hasSettingsPane)

        permission.update(.allowed)
        #expect(permission.hasPermission)
        #expect(!permission.isRequired)
    }

    @Test("Each state explains itself differently")
    func notes() {
        let notes = [NotificationAuthorization.allowed, .off, .notAsked].map { "\(PrivacySettingsPane.notificationsNote($0))" }
        #expect(Set(notes).count == 3)
    }
}
