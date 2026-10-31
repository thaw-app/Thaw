//
//  ControlItemMenuTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw
import ThawUI

/// The control items' context menu, built from an AppState that was never set up.
@MainActor
@Suite("Control item menu", .serialized, .scratchDefaults)
struct ControlItemMenuTests {
    private func item(_ menu: NSMenu, titled title: String) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title == title })
    }

    @Test("The menu opens with Settings and ends with Quit and its Restart alternate")
    func structure() throws {
        let appState = AppState()
        let menu = ControlItemMenuController(appState: appState).makeMenu()
        let first = try #require(menu.items.first { !$0.isSeparatorItem })
        #expect(first.action == #selector(AppDelegate.openSettingsWindow))
        let quit = try #require(menu.items.dropLast().last)
        let restart = try #require(menu.items.last)
        #expect(quit.keyEquivalent == "q")
        #expect(quit.keyEquivalentModifierMask == .command)
        #expect(restart.isAlternate)
        #expect(restart.keyEquivalentModifierMask == [.command, .option])
        #expect(try !#require(menu.items.first?.isSeparatorItem))
    }

    @Test("Settings and What's New go through the responder chain")
    func untargetedItems() throws {
        let appState = AppState()
        let menu = ControlItemMenuController(appState: appState).makeMenu()
        let settings = try #require(menu.items.first { $0.action == #selector(AppDelegate.openSettingsWindow) })
        #expect(settings.target == nil)
        #expect(settings.keyEquivalent == ",")
        let whatsNew = try #require(menu.items.first { $0.action == #selector(AppDelegate.openWhatsNewWindow) })
        #expect(whatsNew.target == nil)
    }

    @Test("The swap bar item mirrors the setting and toggles it")
    func swapBarToggle() throws {
        let appState = AppState()
        appState.settings.advanced.enableSwapBar = false
        let controller = ControlItemMenuController(appState: appState)
        let menu = controller.makeMenu()
        let swap = try item(menu, titled: String(localized: "Show Swap Bar"))
        #expect(swap.state == .off)
        let index = menu.index(of: swap)
        menu.performActionForItem(at: index)
        #expect(appState.settings.advanced.enableSwapBar)
        let rebuilt = controller.makeMenu()
        #expect(try item(rebuilt, titled: String(localized: "Show Swap Bar")).state == .on)
    }

    @Test("The search item advertises its keyboard shortcut")
    func searchShortcut() throws {
        let appState = AppState()
        let hotkey = try #require(appState.settings.hotkeys.hotkey(withAction: .searchMenuBarItems))
        let previous = hotkey.keyCombination
        hotkey.keyCombination = KeyCombination(key: .space, modifiers: [.control, .option])
        defer { hotkey.keyCombination = previous }
        let controller = ControlItemMenuController(appState: appState)
        let menu = controller.makeMenu()
        let search = try item(menu, titled: String(localized: "Search Items…"))
        #expect(search.keyEquivalentModifierMask == [.control, .option])
        #expect(search.target === controller)
    }

    @Test("The Hidden toggle names the section's state", arguments: [false, true])
    func sectionToggle(alwaysHiddenEnabled: Bool) throws {
        let appState = AppState()
        appState.settings.advanced.enableAlwaysHiddenSection = alwaysHiddenEnabled
        let menu = ControlItemMenuController(appState: appState).makeMenu()
        let titles = Set(menu.items.map(\.title))
        let hidden = try #require(appState.menuBarManager.section(withName: .hidden))
        let expected = hidden.isHidden ? String(localized: "Show Hidden Items") : String(localized: "Hide Hidden Items")
        if hidden.isEnabled {
            #expect(titles.contains(expected))
            let toggle = try item(menu, titled: expected)
            #expect(toggle.representedObject as? MenuBarSection === hidden)
            #expect(toggle.badge == nil)
        }
        let alwaysHidden = try #require(appState.menuBarManager.section(withName: .alwaysHidden))
        let hasAlwaysHiddenToggle = titles.contains(String(localized: "Show Always Hidden Items"))
            || titles.contains(String(localized: "Hide Always Hidden Items"))
        #expect(hasAlwaysHiddenToggle == alwaysHidden.isEnabled)
    }

    @Test("Once the app state is gone the menu is empty but titled")
    func menuWithoutAppState() throws {
        var appState: AppState? = AppState()
        let controller = try ControlItemMenuController(appState: #require(appState))
        weak var released = appState
        appState = nil
        try #require(released == nil)
        let menu = controller.makeMenu()
        #expect(menu.items.isEmpty)
        #expect(menu.title == Bundle.main.displayName)
    }

    @Test("The Hidden toggle counts the section's items as a badge, leaving out control items")
    func sectionToggleBadge() throws {
        let appState = AppState()
        appState.itemManager.itemCache[.hidden] = [
            LayoutEditorWorld.item("Alpha"),
            LayoutEditorWorld.item(.hiddenControlItem),
            LayoutEditorWorld.item("Beta"),
        ]
        let menu = ControlItemMenuController(appState: appState).makeMenu()
        let hidden = try #require(appState.menuBarManager.section(withName: .hidden))
        let toggle = try #require(menu.items.first { $0.representedObject as? MenuBarSection === hidden })
        #expect(toggle.badge?.itemCount == 2)
    }

    @Test("What is recording is listed on top, one row per microphone app and one for the camera")
    func recordingReadout() throws {
        let appState = AppState()
        appState.recordingWatchManager.activity = RecordingActivity(
            microphoneUsers: [MicrophoneUser(processIdentifier: 1, bundleIdentifier: nil, name: "Zoom")],
            isCameraInUse: true
        )
        let menu = ControlItemMenuController(appState: appState).makeMenu()
        let readout = Array(menu.items.prefix(3))
        #expect(readout.prefix(2).map(\.title) == [
            String(localized: "Microphone: \("Zoom")"),
            String(localized: "Camera in Use"),
        ])
        #expect(readout.prefix(2).allSatisfy { $0.action == nil }, "readouts are disabled")
        #expect(try #require(readout.last).isSeparatorItem)
        #expect(menu.items.dropFirst(3).first?.action == #selector(AppDelegate.openSettingsWindow))
    }

    @Test("A microphone without the camera lists only the microphone")
    func microphoneOnly() {
        let appState = AppState()
        appState.recordingWatchManager.activity = RecordingActivity(
            microphoneUsers: [MicrophoneUser(processIdentifier: 1, bundleIdentifier: nil, name: "Zoom")]
        )
        let menu = ControlItemMenuController(appState: appState).makeMenu()
        #expect(!menu.items.contains { $0.title == String(localized: "Camera in Use") })
        #expect(menu.items.first?.title == String(localized: "Microphone: \("Zoom")"))
    }

    @Test("Each section toggle title says what choosing it will do", arguments: [
        (true, MenuBarSection.Name.hidden, "Show Hidden Items"),
        (false, .hidden, "Hide Hidden Items"),
        (true, .alwaysHidden, "Show Always Hidden Items"),
        (false, .alwaysHidden, "Hide Always Hidden Items"),
    ])
    func sectionToggleTitles(isHidden: Bool, name: MenuBarSection.Name, expected: String) {
        #expect(ControlItemMenuController.sectionToggleTitle(isHidden: isHidden, name: name) == String(localized: String.LocalizationValue(expected)))
    }

    @Test("A section without its own title is named in the composed one")
    func composedSectionToggleTitle() {
        let name = MenuBarSection.Name.visible.localizedName
        #expect(ControlItemMenuController.sectionToggleTitle(isHidden: true, name: .visible) == String(localized: "\("Show") \(name) Items"))
        #expect(ControlItemMenuController.sectionToggleTitle(isHidden: false, name: .visible) == String(localized: "\("Hide") \(name) Items"))
    }

    @Test("The profiles submenu lists each profile, checks the active one and sends the choice to the controller")
    func profilesSubmenu() throws {
        try ProfileTestDirectory.withManager(seeding: ["Home", "Work"]) { manager, _ in
            let appState = AppState()
            let work = try #require(manager.profiles.first { $0.name == "Work" })
            manager.activeProfileID = work.id
            let controller = ControlItemMenuController(appState: appState)
            let menu = controller.makeMenu(profileManager: manager)

            let profiles = try item(menu, titled: String(localized: "Profiles"))
            let entries = try #require(profiles.submenu?.items)
            #expect(entries.map(\.title) == manager.profiles.map(\.name))
            #expect(entries.filter { $0.state == .on }.map(\.title) == ["Work"])
            #expect(entries.map { $0.representedObject as? UUID } == manager.profiles.map(\.id))
            #expect(entries.allSatisfy { $0.target === controller && $0.action != nil })
            let index = menu.index(of: profiles)
            #expect(menu.items[index - 1].isSeparatorItem)
        }
    }

    @Test("Without profiles the menu has no Profiles entry")
    func noProfilesEntry() throws {
        try ProfileTestDirectory.withManager(seeding: []) { manager, _ in
            let appState = AppState()
            let menu = ControlItemMenuController(appState: appState).makeMenu(profileManager: manager)
            #expect(menu.items.contains { $0.action == #selector(AppDelegate.openSettingsWindow) }, "the menu was built")
            #expect(!menu.items.contains { $0.title == String(localized: "Profiles") })
            withExtendedLifetime(appState) {}
        }
    }
}
