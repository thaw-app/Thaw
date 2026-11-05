//
//  ProfileSwitchAnnouncer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawModuleKit

/// Tells modules that Thaw is switching profiles, so the Scripts module can run
/// the user's scripts. Thaw doesn't wait for any module to answer.
enum ProfileSwitchAnnouncer {
    private static var backlog = ProfileSwitchBacklog()
    private static var listeningObserver: NSObjectProtocol?

    /// The notification for one phase of a switch, or nil without a bundle ID to scope it to.
    static func notification(
        _ phase: ProfileSwitch.Phase,
        _ event: ProfileSwitch,
        hostBundleIdentifier: String?
    ) -> (name: Notification.Name, userInfo: [String: String])? {
        guard let hostBundleIdentifier else { return nil }
        return (ProfileSwitch.notificationName(phase, hostBundleIdentifier: hostBundleIdentifier), event.userInfo)
    }

    /// Waits for the Scripts module to say it listens, and sends it the switch held until then.
    /// Call before modules start, so the first answer isn't missed.
    static func startListeningForScripts() {
        guard listeningObserver == nil, let host = Bundle.main.bundleIdentifier else { return }
        listeningObserver = DistributedNotificationCenter.default().addObserver(
            forName: ProfileSwitch.listeningNotificationName(hostBundleIdentifier: host),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                for (phase, event) in backlog.moduleListening(at: .now) {
                    send(phase, event)
                }
            }
        }
    }

    /// A module quit. Switches made while the Scripts module is gone wait for it to listen again.
    static func moduleQuit(bundleIdentifier: String) {
        guard let host = Bundle.main.bundleIdentifier, bundleIdentifier == SavedScripts.domain(hostBundleIdentifier: host)
        else {
            return
        }
        backlog.moduleStopped()
    }

    static func post(_ phase: ProfileSwitch.Phase, _ event: ProfileSwitch) {
        if backlog.shouldSend(phase, event, at: .now) {
            send(phase, event)
        }
    }

    private static func send(_ phase: ProfileSwitch.Phase, _ event: ProfileSwitch) {
        guard let notification = notification(phase, event, hostBundleIdentifier: Bundle.main.bundleIdentifier) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            notification.name,
            object: nil,
            userInfo: notification.userInfo,
            deliverImmediately: true
        )
    }
}
