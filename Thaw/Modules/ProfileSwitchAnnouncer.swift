//
//  ProfileSwitchAnnouncer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawModuleKit

/// Tells modules that Thaw is switching profiles, so Thaw Scripts can run
/// the user's scripts. Thaw doesn't wait for any module to answer.
enum ProfileSwitchAnnouncer {
    /// The notification for one phase of a switch, or nil without a bundle ID to scope it to.
    static func notification(
        _ phase: ProfileSwitch.Phase,
        _ event: ProfileSwitch,
        hostBundleIdentifier: String?
    ) -> (name: Notification.Name, userInfo: [String: String])? {
        guard let hostBundleIdentifier else { return nil }
        return (ProfileSwitch.notificationName(phase, hostBundleIdentifier: hostBundleIdentifier), event.userInfo)
    }

    static func post(_ phase: ProfileSwitch.Phase, _ event: ProfileSwitch) {
        guard let notification = notification(phase, event, hostBundleIdentifier: Bundle.main.bundleIdentifier) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            notification.name,
            object: nil,
            userInfo: notification.userInfo,
            deliverImmediately: true
        )
    }
}
