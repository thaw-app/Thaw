//
//  ControlItemMenuTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

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
}
