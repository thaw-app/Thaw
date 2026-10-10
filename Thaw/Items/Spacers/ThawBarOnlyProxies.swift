//
//  ThawBarOnlyProxies.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

/// The launcher that opens a small Thaw Bar with every Thaw Bar Only item, and
/// the list of items the user wants back in the menu bar, which
/// ItemStandInSlots draws as separate stand-in bundles.
@MainActor
final class ThawBarOnlyProxies {
    /// Deliberately not under Thaw.ControlItem.: the launcher is an
    /// ordinary, draggable item, like spacers.
    static nonisolated let autosavePrefix = "Thaw.Proxy."

    private static let defaultsKey = "MenuBarItemManager.thawBarOnlyProxies"

    private let diagLog = DiagLog(category: "ThawBarOnlyProxies")

    private weak var appState: AppState?

    /// Canonical identifiers of the items the user wants in the menu bar.
    private(set) var enabledIdentifiers: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: ThawBarOnlyProxies.defaultsKey) ?? []
    )

    /// The one icon that opens a small Thaw Bar with every Thaw Bar Only item.
    private var launcher: NSStatusItem?
    private static let launcherAutosaveName = autosavePrefix + "Launcher"
    private var observationTask: Task<Void, Never>?

    static nonisolated func isProxyTag(_ tag: MenuBarItemTag) -> Bool {
        tag.isThawOwnedNamespace && tag.title.hasPrefix(autosavePrefix)
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        observationTask = Task { @MainActor [weak self, itemManager = appState.itemManager] in
            let changes = Observations {
                (itemManager.thawBarOnlyIdentifiers, itemManager.itemCache, MenuBarItemIconChoices.shared.revision,
                 appState.settings.general.showThawBarOnlyLauncher, appState.settings.general.enableThawBarOnly)
            }
            for await _ in changes {
                guard let self else { return }
                reconcile()
            }
        }
    }

    /// Whether one of the proxies owns this window, which identifies a proxy
    /// before its tag catches up with its title.
    func ownsWindowID(_ windowID: CGWindowID) -> Bool {
        guard let windowNumber = launcher?.button?.window?.windowNumber, windowNumber > 0 else { return false }
        return CGWindowID(windowNumber) == windowID
    }

    func isEnabled(for item: MenuBarItem) -> Bool {
        enabledIdentifiers.contains(Self.identifier(for: item))
    }

    func setEnabled(_ enabled: Bool, for item: MenuBarItem) {
        let identifier = Self.identifier(for: item)
        if enabled {
            enabledIdentifiers.insert(identifier)
        } else {
            enabledIdentifiers.remove(identifier)
        }
        UserDefaults.standard.set(enabledIdentifiers.sorted(), forKey: Self.defaultsKey)
        reconcile()
    }

    /// See MenuBarItemManager.followRenamedThawBarOnlyItems().
    func follow(_ renames: [(from: String, to: String)]) {
        var changed = false
        for rename in renames where enabledIdentifiers.remove(rename.from) != nil {
            enabledIdentifiers.insert(rename.to)
            changed = true
        }
        guard changed else { return }
        UserDefaults.standard.set(enabledIdentifiers.sorted(), forKey: Self.defaultsKey)
    }

    private static func identifier(for item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }

    /// The launcher while there is any Thaw Bar Only item, and a stand-in slot
    /// per enabled item that is Thaw Bar Only right now.
    private func reconcile() {
        guard let appState else { return }
        let items = appState.itemManager.thawBarOnlyItems
        reconcileLauncher(isWanted: !items.isEmpty && appState.settings.general.showThawBarOnlyLauncher)
        let live = Dictionary(items.map { (Self.identifier(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        // Wanted is the user's choice alone: an item not yet live at launch
        // keeps its slot, and only its helper waits.
        appState.itemStandInSlots.reconcile(
            wanted: appState.itemManager.isThawBarOnlyEnabled
                ? enabledIdentifiers.intersection(appState.itemManager.thawBarOnlyIdentifiers)
                : [],
            liveItems: live
        )
    }

    private func reconcileLauncher(isWanted: Bool) {
        guard isWanted else {
            if let launcher {
                NSStatusBar.system.removeStatusItem(launcher)
                self.launcher = nil
                appState?.menuBarManager.thawBarPanel.closeIfShowingThawBarOnly()
            }
            return
        }
        guard launcher == nil else { return }
        let name = Self.launcherAutosaveName
        // No seeded position: a guess from a missing Thaw icon position lands
        // on 0, which is an occupied seat. macOS places a new item itself.
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(name)")
        UserDefaults.standard.set(true, forKey: "NSStatusItem VisibleCC \(name)")
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = name
        let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = String(localized: "Thaw Bar Only items")
        statusItem.button?.setAccessibilityLabel(String(localized: "Thaw Bar Only items"))
        statusItem.button?.setAccessibilityIdentifier(name)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(launcherClicked(_:))
        launcher = statusItem
        assertLauncherTitle(attempt: 0)
        diagLog.info("Created the Thaw Bar Only launcher")
    }

    private func assertLauncherTitle(attempt: Int) {
        guard let launcher else { return }
        if let window = launcher.button?.window {
            window.title = Self.launcherAutosaveName
        } else if attempt < 20 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.assertLauncherTitle(attempt: attempt + 1)
            }
        }
    }

    /// Whether the pointer is on the launcher, so the panel's outside-click
    /// dismissal leaves the launcher's own toggle to it.
    func launcherContainsPointer() -> Bool {
        guard launcher != nil,
              let bounds = appState?.itemManager.barBounds(ofThawItemNamed: Self.launcherAutosaveName),
              let pointer = MouseHelpers.locationCoreGraphics
        else { return false }
        return bounds.contains(pointer)
    }

    @objc private func launcherClicked(_ sender: NSStatusBarButton) {
        toggleThawBarOnlyBar(
            on: sender.window?.screen,
            openedFrom: appState?.itemManager.barBounds(ofThawItemNamed: Self.launcherAutosaveName)
        )
    }

    /// Opens or closes the small Thaw Bar with every Thaw Bar Only item.
    func toggleThawBarOnlyBar(on screen: NSScreen? = nil, openedFrom iconFrame: CGRect? = nil) {
        guard let appState else { return }
        let panel = appState.menuBarManager.thawBarPanel
        if panel.isVisible, panel.presentation == .thawBarOnly {
            panel.close()
            return
        }
        guard !appState.itemManager.thawBarOnlyItems.isEmpty,
              let screen = screen ?? NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        else { return }
        panel.show(section: .hidden, on: screen, presentation: .thawBarOnly, openedFrom: iconFrame)
    }
}

extension MenuBarItemManager {
    /// Where one of Thaw's own status items is on the bar, found by its
    /// autosave name. On macOS 27 the button's own window has no real frame,
    /// so the item cache's accessibility bounds are the only measure.
    func barBounds(ofThawItemNamed autosaveName: String) -> CGRect? {
        managedItems.first { $0.tag.isThawOwnedNamespace && $0.tag.title == autosaveName }?.bounds
    }
}
