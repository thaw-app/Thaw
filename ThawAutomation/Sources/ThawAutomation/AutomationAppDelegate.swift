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
    private var window: NSWindow?

    private let hostBundleIdentifier = ModuleLaunchEnvironment.hostBundleIdentifier()

    func applicationDidFinishLaunching(_: Notification) {
        store.importFromThaw(hostDefaults: hostBundleIdentifier.flatMap(UserDefaults.init(suiteName:)), catalog: catalog)
        let store = store
        runner = ProfileSwitchRunner(
            configuration: { store.configuration },
            run: { hook, context in await HookRunner.runIfEnabled(hook, context: context) }
        )
        observeProfileSwitches()
        if CommandLine.arguments.contains(ModuleLaunchEnvironment.showWindowArgument) {
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
    }

    private func profileDidSwitch(_ phase: ProfileSwitch.Phase, _ event: ProfileSwitch) {
        // A profile imported since launch may carry scripts of its own.
        if phase == .willApply {
            store.importFromThaw(hostDefaults: nil, catalog: catalog)
        }
        runner?.handle(phase, event)
    }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: ScriptsView(store: store, catalog: catalog)
            ))
            window.title = String(localized: "Scripts")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
