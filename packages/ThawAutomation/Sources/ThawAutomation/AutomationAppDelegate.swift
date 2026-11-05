//
//  AutomationAppDelegate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import AutomationCore
import SwiftUI
import ThawModuleKit

/// Listens for Thaw's profile switches and runs the user's scripts. Thaw
/// launches it in the background; opening it shows the Scripts window.
@MainActor
final class AutomationAppDelegate: NSObject, NSApplicationDelegate {
    private let store = HookStore(defaults: .standard)
    private let catalog = ProfileCatalog.thaw
    private var runner: ProfileSwitchRunner?
    private lazy var window = ModuleWindowController(title: String(localized: "Scripts")) { [store, catalog] in
        ScriptsView(store: store, catalog: catalog)
    }

    private let hostBundleIdentifier = ModuleLaunchEnvironment.hostBundleIdentifier()

    func applicationDidFinishLaunching(_: Notification) {
        store.importFromThaw(hostDefaults: hostBundleIdentifier.flatMap(UserDefaults.init(suiteName:)), catalog: catalog)
        let store = store
        runner = ProfileSwitchRunner(
            configuration: { store.configuration },
            run: { hook, context in await HookRunner.runIfEnabled(hook, context: context) }
        )
        observeProfileSwitches()
        if ModuleWindowController.isRequestedAtLaunch {
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showWindow()
        return false
    }

    private func observeProfileSwitches() {
        guard let host = hostBundleIdentifier else { return }
        let center = DistributedNotificationCenter.default()
        for phase in [ProfileSwitch.Phase.willApply, .didApply] {
            center.addObserver(
                forName: ProfileSwitch.notificationName(phase, hostBundleIdentifier: host),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = ProfileSwitch(userInfo: notification.userInfo) else { return }
                MainActor.assumeIsolated {
                    self?.profileDidSwitch(phase, event)
                }
            }
        }
        // A Thaw that started after this module asks again, or it would hold every switch.
        center.addObserver(
            forName: ProfileSwitch.listeningQueryNotificationName(hostBundleIdentifier: host),
            object: nil,
            queue: .main
        ) { _ in
            Self.announceListening(to: host)
        }
        // Thaw holds a switch made before this point and sends it now.
        Self.announceListening(to: host)
    }

    /// Tells Thaw this module hears its profile switches.
    private static nonisolated func announceListening(to host: String) {
        DistributedNotificationCenter.default().postNotificationName(
            ProfileSwitch.listeningNotificationName(hostBundleIdentifier: host),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func profileDidSwitch(_ phase: ProfileSwitch.Phase, _ event: ProfileSwitch) {
        // A profile imported since launch may carry scripts of its own.
        if phase == .willApply {
            store.importFromThaw(hostDefaults: nil, catalog: catalog)
        }
        runner?.handle(phase, event)
    }

    private func showWindow() {
        window.show()
    }
}
