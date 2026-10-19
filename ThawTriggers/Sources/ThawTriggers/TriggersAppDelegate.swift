//
//  TriggersAppDelegate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import os
import SwiftUI
import ThawModuleKit
import TriggersCore

/// Watches running apps and asks Thaw to hold their chosen items shown.
/// Thaw launches it in the background; opening it shows the Triggers window.
@MainActor
final class TriggersAppDelegate: NSObject, NSApplicationDelegate {
    private static nonisolated let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Thaw Triggers", category: "App")

    private var manager: AppRunningTriggersManager?
    private let itemSource = ThawItemSource()
    private var window: NSWindow?

    private let hostBundleIdentifier = ModuleLaunchEnvironment.hostBundleIdentifier()

    func applicationDidFinishLaunching(_: Notification) {
        AppRunningTriggersManager.importFromThaw(
            into: .standard,
            hostDefaults: hostBundleIdentifier.flatMap(UserDefaults.init(suiteName:))
        )
        let manager = AppRunningTriggersManager()
        manager.start(
            reveal: { [weak self] in self?.send(ThawCommands.hold(itemID: $0)) },
            release: { [weak self] in self?.send(ThawCommands.release(itemID: $0)) }
        )
        self.manager = manager
        itemSource.request = { [weak self] requestID in
            guard let scheme = Bundle.main.bundleIdentifier?.lowercased() else { return }
            self?.send(ThawCommands.listItems(callbackScheme: scheme, requestID: requestID))
        }
        if CommandLine.arguments.contains(ModuleLaunchEnvironment.showWindowArgument) {
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showWindow()
        return false
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            if let reply = ThawItemList.reply(fromCallback: url) {
                itemSource.receive(reply)
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        // Thaw drops a module's holds when it quits, so this only tidies up.
        manager?.stop()
    }

    /// Sends a request to this module's own Thaw rather than to whichever app
    /// registered thaw://: the running copy with the host's bundle ID when
    /// there is one, so a second copy elsewhere on disk isn't woken instead.
    private func send(_ url: URL) {
        guard let host = hostBundleIdentifier,
              let thaw = NSRunningApplication.runningApplications(withBundleIdentifier: host).first?.bundleURL
              ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: host)
        else {
            Self.log.error("No Thaw to send \(url.host ?? "", privacy: .public) to")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: thaw, configuration: configuration) { _, error in
            if let error {
                Self.log.error("Could not send \(url.host ?? "", privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func showWindow() {
        guard let manager else { return }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: TriggersView(manager: manager, itemSource: itemSource)
            ))
            window.title = String(localized: "Triggers")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        itemSource.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
