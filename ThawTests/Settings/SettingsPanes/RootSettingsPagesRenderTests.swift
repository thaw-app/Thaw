//
//  RootSettingsPagesRenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import ThawModuleKit
import ThawUI

/// Pages and sections directly under SettingsPanes, drawn off screen against an AppState
/// that is never started. Modules come from a fake system, so no module app is launched,
/// and nothing here asks for a permission, reads the screen or changes the menu bar.
@MainActor
@Suite("Settings root pages rendering", .serialized, .scratchDefaults)
struct RootSettingsPagesRenderTests {
    private static let size = CGSize(width: 760, height: 1800)

    private typealias Page = OffscreenRender<AnyView>

    private func page(_ view: some View, appState: AppState) -> Page {
        OffscreenRender(
            AnyView(
                view
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
    }

    /// Waits until the page shows text, and returns what it shows.
    private func shownTexts(_ page: Page, containing text: String) async -> [String] {
        await page.settle { page.texts().contains { $0.contains(text) } }
        return page.texts()
    }

    // MARK: Triggers

    @Test("Triggers shows its module row, and the icon-change list once the module is on")
    func triggersPane() async {
        let off = AppState()
        let offPage = page(TriggersSettingsPane(), appState: off)
        let offTexts = await shownTexts(offPage, containing: "When an app runs")
        #expect(offTexts.contains { $0.contains("Not installed") }, "no module is installed in the test host")
        #expect(!offTexts.contains { $0.contains("Hide an item first") })

        Defaults.set([ModuleIdentifier.triggers.rawValue], forKey: .enabledModules)
        let on = AppState()
        let onPage = page(TriggersSettingsPane(), appState: on)
        let onTexts = await shownTexts(onPage, containing: "Hide an item first")
        #expect(onTexts.contains { $0.contains("Hide an item first") })
    }

    // MARK: Modules

    /// A module host over a fake system, the one the ModuleHost tests use.
    private func moduleHost(_ system: ModuleHostTests.FakeSystem) -> ModuleHost {
        let host = ModuleHost(environment: system.environment())
        host.refresh()
        return host
    }

    @Test("Modules shows a card per module with why it can't run, and its switches start and stop it")
    func modulesPane() async throws {
        let appState = AppState()
        let system = ModuleHostTests.FakeSystem()
        system.savedEnabled = ["triggers"]
        let triggers = system.addModule("triggers")
        _ = system.addModule("widgets", team: "OTHER")
        _ = system.addModule("automation", minimumAPIVersion: 99)
        let host = moduleHost(system)
        let profiles = ProfilesFeature()
        let page = page(ModulesSettingsPane(moduleHost: host, profiles: profiles), appState: appState)

        let texts = await shownTexts(page, containing: "Not signed by")
        #expect(texts.contains { $0.contains("Switches saved layouts") }, "the Profiles card comes first")
        #expect(texts.contains { $0.contains("Needs a newer version") })
        #expect(texts.contains { $0.contains("Shows chosen menu bar items") })

        try page.press("Open…")
        await page.settle { system.windowsShown == [triggers] }
        #expect(system.windowsShown == [triggers], "Open launches the module with its window")

        let switches = page.elements().filter { OffscreenAccessibility.role(of: $0) == .checkBox }
        #expect(switches.count == 4, "one switch per card")
        let wasOn = profiles.isOn
        OffscreenAccessibility.press(try #require(switches.first))
        await page.settle { profiles.isOn != wasOn }
        #expect(profiles.isOn != wasOn, "the Profiles card's switch turns Profiles on or off")
        profiles.isOn = wasOn
    }

    @Test("Each module state has its own summary")
    func moduleSummaries() {
        #expect(ModulesSettingsPane.summary(for: "widgets", state: .gaveUp).contains("kept quitting"))
        #expect(ModulesSettingsPane.summary(for: "widgets", state: .launchFailed).contains("Couldn't start"))
        #expect(ModulesSettingsPane.summary(for: "automation", state: .idle).contains("scripts"))
        #expect(ModulesSettingsPane.summary(for: "widgets", state: .running(1)).contains("battery"))
        #expect(ModulesSettingsPane.summary(for: "unknown", state: .stopped).isEmpty)
    }

    @Test("A module switch saves the choice and launches the module")
    func moduleControls() async throws {
        let appState = AppState()
        let system = ModuleHostTests.FakeSystem()
        system.savedEnabled = []
        let widgets = system.addModule("widgets")
        let host = moduleHost(system)
        let page = page(ModuleControls(moduleHost: host, identifier: "widgets", name: "Widgets"), appState: appState)
        await page.settle { page.elements().contains { OffscreenAccessibility.role(of: $0) == .checkBox } }
        #expect(page.elements(role: .button, label: "Open…").isEmpty, "a module that is off has no Open button")

        let toggle = try #require(page.elements().first { OffscreenAccessibility.role(of: $0) == .checkBox })
        OffscreenAccessibility.press(toggle)
        await page.settle { system.launched == [widgets] }
        #expect(host.isEnabled("widgets"))
        #expect(system.savedEnabled == ["widgets"])
        #expect(system.launched == [widgets])
    }

    // MARK: Simple Mode

    @Test("Simple Mode draws its settings, the Accessibility warning, and the section shortcut")
    func simpleModePane() async {
        let appState = AppState()
        let general = appState.settings.general
        general.simpleModeShowsPreview = false
        appState.settings.layout.enableAlwaysHiddenSection = true
        appState.settings.visibility.showAlwaysHiddenOnIconDoubleClick = true
        let page = page(
            SimpleModeSettingsPane(itemManager: appState.itemManager, updatesManager: appState.updatesManager, settings: general),
            appState: appState
        )
        let texts = await shownTexts(page, containing: "Item arrangement")
        #expect(texts.contains { $0.contains("Sections preview") })
        #expect(texts.contains { $0.contains("double-click") }, "Always Hidden names the double-click while it works")
        if !appState.permissions.accessibility.hasPermission {
            #expect(texts.contains { $0.contains("Accessibility is off") })
        }

        appState.settings.visibility.showAlwaysHiddenOnIconDoubleClick = false
        await page.settle { !page.texts().contains { $0.contains("double-click") } }
        #expect(page.texts().contains { $0.contains("stay hidden when you show hidden items") })
    }

    // MARK: Other apps

    @Test("Allowed apps lists each app with a Remove button that takes it off")
    func otherAppsRows() async throws {
        Defaults.set(["com.example.allowed"], forKey: .settingsURIWhitelist)
        Defaults.set(true, forKey: .settingsURIEnabled)
        let appState = AppState()
        let privacy = appState.settings.privacy
        privacy.isSettingsURIEnabled = true
        let page = page(ThawForm { OtherAppsSection(settings: privacy) }, appState: appState)
        await page.settle { !page.elements(role: .button, label: "Choose App…").isEmpty }
        #expect(!page.elements(role: .button, label: "Choose App…").isEmpty)

        let app = try #require(privacy.whitelistedApps.first)
        try page.press("Remove \(app.displayName)")
        await page.settle { privacy.whitelistedApps.isEmpty }
        #expect(privacy.whitelistedApps.isEmpty)

        privacy.isSettingsURIEnabled = false
        await page.settle { page.elements(role: .button, label: "Choose App…").isEmpty }
        #expect(page.elements(role: .button, label: "Choose App…").isEmpty, "the list hides while links are off")
    }

    // MARK: Move inspector

    @Test("The move inspector lists recorded moves and says when the saved layout was refused")
    func moveInspector() async {
        let appState = AppState()
        let monitor = appState.itemManager.moveMonitor
        let page = page(ThawForm { MoveInspectorSection() }, appState: appState)
        _ = await shownTexts(page, containing: "saved menu bar layout")
        #expect(!page.texts().contains { $0.contains("This session") }, "no counters before a move")

        monitor.recordStoreMove(item: "Example Item", destination: "Hidden, after Clock", satisfied: true)
        monitor.recordStoreMove(item: "Other Item", destination: "Visible", satisfied: false)
        monitor.recordStoreUnavailable()
        let texts = await shownTexts(page, containing: "Example Item")
        #expect(texts.contains { $0.contains("Other Item") })
        #expect(texts.contains { $0.contains("This session") })
        #expect(texts.contains { $0.contains("refused access") })
    }

    // MARK: Folded menu bar

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// Seeds the item list, so the bars draw what is there and never preload from the live bar.
    private func seedItems(_ appState: AppState) {
        appState.itemManager.itemCache[.visible] = [Self.item("Visible", x: 300)]
        appState.itemManager.itemCache[.hidden] = [Self.item("Hidden", x: 200)]
        appState.itemManager.itemCache[.alwaysHidden] = [Self.item("Always", x: 100)]
    }

    @Test("The folded bar names each section, with a sort menu, and marks the one a drag hovers")
    func foldedMenuBar() async throws {
        let appState = AppState()
        seedItems(appState)
        let page = page(FoldedMenuBar(itemManager: appState.itemManager), appState: appState)
        await page.settle { page.texts().contains { $0 == "Hidden" } }
        #expect(page.texts().contains { $0 == "Visible" } && page.texts().contains { $0 == "Hidden" })
        let sortMenus = page.elements().filter { [.menuButton, .popUpButton].contains(OffscreenAccessibility.role(of: $0)) }
        #expect(sortMenus.count >= 2, "each section has a sort menu")

        let before = try page.pixels()
        NotificationCenter.default.post(name: .layoutBarDragTargetChanged, object: nil, userInfo: ["section": MenuBarSection.Name.hidden.rawValue, "active": true])
        await page.settle { (try? page.pixels()) != before }
        #expect(try page.pixels() != before, "the hovered section's name gets its wash")
        NotificationCenter.default.post(name: .layoutBarDragTargetChanged, object: nil, userInfo: ["section": "unknown"])
        NotificationCenter.default.post(name: .layoutBarDragTargetChanged, object: nil, userInfo: ["section": MenuBarSection.Name.hidden.rawValue, "active": false])
        await page.settle { (try? page.pixels()) == before }
        #expect(try page.pixels() == before, "the wash goes when the drag leaves")
    }

    @Test("Simple Mode's preview draws the sections it shows")
    func simpleModePreview() async {
        let appState = AppState()
        seedItems(appState)
        let general = appState.settings.general
        general.simpleModeShowsPreview = true
        let page = page(
            SimpleModeSettingsPane(itemManager: appState.itemManager, updatesManager: appState.updatesManager, settings: general),
            appState: appState
        )
        let texts = await shownTexts(page, containing: "Item arrangement")
        let showsBars = texts.contains { $0 == "Visible" }
        let showsAutoHideWarning = texts.contains { $0.contains("set to hide itself") }
        #expect(showsBars || showsAutoHideWarning, "the preview, or why there is none")
    }
}
