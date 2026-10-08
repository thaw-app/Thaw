//
//  ReducedModeController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import OSLog

/// Thaw without Accessibility: one status item. A click shows or hides the chosen apps, as a click
/// on the Thaw icon does in the full app, and a right click opens the menu that picks them.
/// Nothing here reads the menu bar. Arranging, the Thaw Bar and search need the full app.
///
/// This file holds the decisions. The status item, its icon and the hand-over to the full app
/// are in ReducedModeController+Live.swift.
@MainActor
final class ReducedModeController: NSObject, NSMenuDelegate {

    /// What the controller needs from outside, so a test can drive the menu without touching
    /// the menu bar or the app's saved settings.
    struct Environment {
        var hidingIsAvailable: () -> Bool
        var hide: (Set<String>) -> Void
        var apps: () -> [ReducedModeApp]
        var loadHidden: () -> Set<String>
        var saveHidden: (Set<String>) -> Void
    }

    let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    static let diagLog = Logger(subsystem: Constants.bundleIdentifier, category: "ReducedMode")

    /// Whether the user chose to run without Accessibility.
    static var isChosen: Bool {
        get { Defaults.bool(forKey: .reducedModeChosen) }
        set { Defaults.set(newValue, forKey: .reducedModeChosen) }
    }

    var statusItem: NSStatusItem?
    let menu = NSMenu()
    weak var appState: AppState?

    private var hiddenBundleIDs: Set<String> {
        get { environment.loadHidden() }
        set { environment.saveHidden(newValue) }
    }

    var isRunning: Bool { statusItem != nil }

    /// False while the user has asked to see the hidden apps.
    private var isHiding = true

    func applyHiding() {
        let hidden = isHiding ? hiddenBundleIDs : []
        environment.hide(hidden)
        updateIcon(isHidingSomething: !hidden.isEmpty)
        Self.diagLog.info("reduced mode: hiding \(hidden.count) app(s): \(hidden.sorted().joined(separator: ", "), privacy: .public)")
    }

    // MARK: Clicks

    enum ClickOutcome: Equatable {
        case toggled
        case openMenu
    }

    /// A plain click toggles. A right or Control click opens the menu, and so does a plain click
    /// while no app is chosen, since a toggle would do nothing then.
    func clicked(secondary: Bool) -> ClickOutcome {
        guard !secondary, !hiddenBundleIDs.isEmpty, environment.hidingIsAvailable() else { return .openMenu }
        toggleHiding()
        return .toggled
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard environment.hidingIsAvailable() else {
            menu.addItem(disabled("Hiding is not available on this version of macOS"))
            addFooter(to: menu)
            return
        }
        let hidden = hiddenBundleIDs
        let toggle = NSMenuItem(
            title: isHiding ? String(localized: "Show Hidden Apps") : String(localized: "Hide Chosen Apps"),
            action: #selector(toggleHiding),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = !hidden.isEmpty
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(disabled(String(localized: "Hide these apps' menu bar items:")))
        let apps = environment.apps()
        for app in apps {
            let item = NSMenuItem(title: app.name, action: #selector(toggleApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleID
            item.state = hidden.contains(app.bundleID) ? .on : .off
            menu.addItem(item)
        }
        if apps.isEmpty {
            menu.addItem(disabled(String(localized: "No apps found")))
        }
        addFooter(to: menu)
    }

    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        let granted = appState?.permissions.accessibility.hasPermission == true
        let full = NSMenuItem(
            title: granted
                ? String(localized: "Switch to the Full \(Constants.displayName)")
                : String(localized: "Turn On Accessibility for the Full \(Constants.displayName)…"),
            action: #selector(switchToFullApp),
            keyEquivalent: ""
        )
        full.target = self
        menu.addItem(full)
        let quit = NSMenuItem(
            title: String(localized: "Quit \(Constants.displayName)"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Runs a thaw:// request, so the mode can be driven without the mouse.
    func handle(_ url: URL) {
        guard let command = ReducedModeURLCommand(url) else {
            Self.diagLog.warning("reduced mode: no such request: \(url.absoluteString, privacy: .public)")
            return
        }
        switch command {
        case .toggleHidden:
            toggleHiding()
        case let .hideApp(bundleID):
            hiddenBundleIDs.insert(bundleID)
            isHiding = true
            applyHiding()
        case let .showApp(bundleID):
            hiddenBundleIDs.remove(bundleID)
            applyHiding()
        case .listApps:
            let hidden = hiddenBundleIDs
            let lines = environment.apps().map { "\(hidden.contains($0.bundleID) ? "hidden" : "shown") \($0.bundleID) (\($0.name))" }
            Self.diagLog.info("reduced mode: \(lines.count) app(s) on offer: \(lines.joined(separator: "; "), privacy: .public)")
        }
    }

    @objc private func toggleHiding() {
        isHiding.toggle()
        applyHiding()
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        hiddenBundleIDs.formSymmetricDifference([bundleID])
        isHiding = true
        applyHiding()
    }
}
