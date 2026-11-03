//
//  WidgetsApplication.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawModuleKit

/// The Widgets module app. While it runs, the widget icon is in the menu bar;
/// opening it shows the builder.
public enum WidgetsApplication {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = WidgetsAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

/// Copies the widget design Thaw saved before widgets became a module.
enum WidgetSettingsImport {
    private static let importedKey = "ImportedThawWidgetSettings"

    /// Copies the settings once, the first time the module runs.
    static func importFromThaw(into store: UserDefaults, hostDefaults: UserDefaults?) {
        guard !store.bool(forKey: importedKey) else { return }
        store.set(true, forKey: importedKey)
        guard let host = hostDefaults else { return }
        for (key, value) in host.dictionaryRepresentation() where key.hasPrefix(WidgetKeys.prefix) {
            store.set(value, forKey: key)
        }
    }
}

@MainActor
final class WidgetsAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    private let hostBundleIdentifier = ModuleLaunchEnvironment.hostBundleIdentifier()

    func applicationDidFinishLaunching(_: Notification) {
        WidgetSettingsImport.importFromThaw(
            into: .standard,
            hostDefaults: hostBundleIdentifier.flatMap(UserDefaults.init(suiteName:))
        )
        StatusIconWidgetController.shared.start()
        if CommandLine.arguments.contains(ModuleLaunchEnvironment.showWindowArgument) {
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showWindow()
        return false
    }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: WidgetsView()))
            window.title = String(localized: "Widgets")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
