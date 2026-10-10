//
//  ControlItemMenu.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

// MARK: - ControlItemMenuController

/// Builds the control items' context menu and handles its commands. Rebuilt on
/// every presentation because most of it reflects live state.
@MainActor
final class ControlItemMenuController: NSObject {
    private static nonisolated let diagLog = DiagLog(category: "ControlItemMenu")

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    /// Per the macOS 27 HIG, only common actions and devices get symbols:
    /// Search Items, the section toggles and the recording readouts.
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: Bundle.main.displayName)
        guard let appState else {
            return menu
        }

        // On top: the user may have opened the menu to read it, and it is
        // absent when there is nothing to say.
        let recordingItems = recordingWatchItems(appState: appState)
        if !recordingItems.isEmpty {
            for item in recordingItems {
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        menu.addItem(settingsItem())
        menu.addItem(whatsNewItem())
        menu.addItem(.separator())
        menu.addItem(searchItem(appState: appState))
        menu.addItem(swapBarItem(appState: appState))

        menu.addItem(.separator())
        for item in sectionToggleItems(appState: appState) {
            menu.addItem(item)
        }

        if let profilesItem = profilesItem(appState: appState) {
            menu.addItem(.separator())
            menu.addItem(profilesItem)
        }

        menu.addItem(.separator())
        if Constants.supportsSparkleUpdates {
            menu.addItem(checkForUpdatesItem())
        }
        menu.addItem(supportItem())

        menu.addItem(.separator())
        // The restart item is an alternate of quit: it replaces it while option
        // is held, which is why both carry the same key equivalent.
        menu.addItem(quitItem())
        menu.addItem(restartItem())

        return menu
    }

    // MARK: Item construction

    /// Untargeted so the command reaches the app delegate via the responder chain.
    private func whatsNewItem() -> NSMenuItem {
        NSMenuItem(
            title: String(localized: "What’s New…"),
            action: #selector(AppDelegate.openWhatsNewWindow),
            keyEquivalent: ""
        )
    }

    /// Untargeted for the same reason as whatsNewItem().
    private func settingsItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        item.keyEquivalentModifierMask = .command
        return item
    }

    /// What is listening or watching right now; empty unless the Experiments
    /// toggle is on. Only the microphone names an app: no public API says who
    /// holds a camera.
    private func recordingWatchItems(appState: AppState) -> [NSMenuItem] {
        let activity = appState.recordingWatchManager.activity
        guard !activity.isIdle else {
            return []
        }

        var items = activity.microphoneUsers.map { user in
            informationalItem(
                title: String(localized: "Microphone: \(user.name)"),
                systemName: "mic.fill"
            )
        }
        if activity.isCameraInUse {
            items.append(
                informationalItem(
                    title: String(localized: "Camera in Use"),
                    systemName: "video.fill"
                )
            )
        }
        return items
    }

    /// No action, so NSMenu's automatic enabling leaves it disabled.
    private func informationalItem(title: String, systemName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.setSymbolImage(systemName: systemName, accessibilityDescription: title)
        return item
    }

    private func searchItem(appState: AppState) -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Search Items…"),
            action: #selector(showSearchPanel),
            keyEquivalent: ""
        )
        item.setSymbolImage(systemName: "magnifyingglass", accessibilityDescription: "Search Items")
        apply(
            keyCombination: appState.settings.hotkeys.hotkey(withAction: .searchMenuBarItems)?.keyCombination,
            to: item
        )
        item.target = self
        return item
    }

    /// A checkbox mirroring the Settings switch; no symbol, since the
    /// checkmark occupies that column.
    private func swapBarItem(appState: AppState) -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Show Swap Bar"),
            action: #selector(toggleSwapBar),
            keyEquivalent: ""
        )
        item.state = appState.settings.advanced.enableSwapBar ? .on : .off
        item.target = self
        return item
    }

    private func sectionToggleItems(appState: AppState) -> [NSMenuItem] {
        let toggleableNames: [MenuBarSection.Name] = [.hidden, .alwaysHidden]
        return toggleableNames.compactMap { name in
            guard
                let section = appState.menuBarManager.section(withName: name),
                section.isEnabled
            else {
                return nil
            }

            let title = Self.sectionToggleTitle(for: section, name: name)
            let item = NSMenuItem(
                title: title,
                action: #selector(toggleMenuBarSection),
                keyEquivalent: ""
            )
            // The count is a badge so the title stays a fixed string for translators.
            let count = appState.itemManager.managedItems(for: name).count { !$0.isControlItem }
            item.badge = count > 0 ? NSMenuItemBadge(count: count) : nil
            item.setSymbolImage(
                systemName: section.isHidden ? "eye" : "eye.slash",
                accessibilityDescription: title
            )
            apply(keyCombination: section.hotkey?.keyCombination, to: item)
            item.target = self
            item.representedObject = section
            return item
        }
    }

    /// Spelled out rather than composed so each title is a fixed key for translators.
    private static func sectionToggleTitle(for section: MenuBarSection, name: MenuBarSection.Name) -> String {
        switch (section.isHidden, name) {
        case (true, .hidden):
            String(localized: "Show Hidden Items")
        case (false, .hidden):
            String(localized: "Hide Hidden Items")
        case (true, .alwaysHidden):
            String(localized: "Show Always Hidden Items")
        case (false, .alwaysHidden):
            String(localized: "Hide Always Hidden Items")
        default:
            String(localized: "\(section.isHidden ? "Show" : "Hide") \(name.displayString) Items")
        }
    }

    private func profilesItem(appState: AppState) -> NSMenuItem? {
        let profileManager = appState.profileManager
        guard !profileManager.profiles.isEmpty else {
            return nil
        }

        let submenu = NSMenu()
        for metadata in profileManager.profiles {
            let item = NSMenuItem(
                title: metadata.name,
                action: #selector(applyProfileFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = metadata.id
            if metadata.id == profileManager.activeProfileID {
                item.state = .on
            }
            submenu.addItem(item)
        }

        let item = NSMenuItem(
            title: String(localized: "Profiles"),
            action: nil,
            keyEquivalent: ""
        )
        item.submenu = submenu
        return item
    }

    private func checkForUpdatesItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    private func supportItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Support \(Constants.displayName)…"),
            action: #selector(openDonateURL),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    private func quitItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Quit \(Constants.displayName)"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        item.keyEquivalentModifierMask = .command
        item.target = self
        return item
    }

    private func restartItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Restart \(Constants.displayName)"),
            action: #selector(restartFromMenu),
            keyEquivalent: "q"
        )
        item.keyEquivalentModifierMask = [.command, .option]
        item.isAlternate = true
        item.target = self
        return item
    }

    /// Mirrors a Thaw keyboard shortcut onto item, so the menu advertises the shortcut
    /// that already works globally.
    private func apply(keyCombination: KeyCombination?, to item: NSMenuItem) {
        guard let keyCombination else {
            return
        }
        item.keyEquivalent = keyCombination.key.keyEquivalent
        item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
    }

    // MARK: Commands

    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        guard let section = menuItem.representedObject as? MenuBarSection else {
            return
        }
        section.toggle()
    }

    @objc private func showSearchPanel() {
        appState?.menuBarManager.searchPanel.show()
    }

    @objc private func toggleSwapBar() {
        guard let advanced = appState?.settings.advanced else { return }
        advanced.enableSwapBar.toggle()
    }

    @objc private func applyProfileFromMenu(_ menuItem: NSMenuItem) {
        guard
            let profileID = menuItem.representedObject as? UUID,
            let appState,
            appState.profileManager.layoutTask == nil,
            profileID != appState.profileManager.activeProfileID
        else {
            return
        }
        let profileManager = appState.profileManager
        Task {
            // The menu is already closed, so a silent failure would look like
            // success. Report it the way the Profiles pane does.
            do {
                let profile = try profileManager.loadProfile(id: profileID)
                let previousID = profileManager.activeProfileID
                profileManager.activeProfileID = profileID
                profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
            } catch {
                Self.diagLog.error("Could not apply profile \(profileID) from the status menu: \(error)")
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func checkForUpdates() {
        appState?.updatesManager.checkForUpdates()
    }

    @objc private func openDonateURL() {
        NSWorkspace.shared.open(Constants.donateURL)
    }

    /// Deferred to the default run loop mode: terminating inside menu tracking
    /// can strand the .terminateLater reply, and the process never exits.
    @objc private func quitFromMenu() {
        ApplicationTermination.request()
    }

    /// Deferred like quitFromMenu(): the teardown before exit(0) must drain
    /// after menu tracking has unwound.
    @objc private func restartFromMenu() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.appState?.restartSelf()
            }
        }
    }
}
