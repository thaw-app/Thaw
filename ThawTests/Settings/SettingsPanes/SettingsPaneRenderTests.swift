//
//  SettingsPaneRenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// Settings pages drawn off screen against an AppState that is never started.
/// Layout and Simple Mode are left out because they preload captures from the live bar.
@MainActor
@Suite("Settings page rendering", .serialized, .scratchDefaults)
struct SettingsPaneRenderTests {
    private static let size = CGSize(width: 760, height: 2400)

    private func render(_ view: some View, appState: AppState) -> OffscreenRender<some View> {
        OffscreenRender(
            view
                .environment(appState)
                .environment(\.settingsPaneTitle, nil)
                .frame(width: Self.size.width, height: Self.size.height),
            size: Self.size
        )
    }

    /// Draws the page, waits for it to put something on screen, and returns its pixels.
    private func drawnPixels(_ render: OffscreenRender<some View>) async throws -> Data {
        await render.settle { (try? render.pixels())?.contains { $0 != 0 } == true }
        let pixels = try render.pixels()
        #expect(pixels.contains { $0 != 0 }, "the page draws something")
        return pixels
    }

    /// Asks the page for the tab holding each section in turn and checks that
    /// every tab draws differently from the first.
    private func expectTabsDraw(
        _ sections: [String],
        appState: AppState,
        render: OffscreenRender<some View>
    ) async throws {
        let first = try await drawnPixels(render)
        for section in sections {
            appState.navigationState.requestedSettingsSection = section
            await render.settle { appState.navigationState.requestedSettingsSection == nil }
            #expect(appState.navigationState.requestedSettingsSection == nil, "the page takes \(section)")
            await render.settle { (try? render.pixels()) != first }
            #expect(try render.pixels() != first, "\(section) draws its own tab")
        }
    }

    @Test("General draws, and hiding descriptions redraws it")
    func generalPane() async throws {
        let appState = AppState()
        let settings = appState.settings
        let render = render(GeneralSettingsPane(settings: settings.general, advancedSettings: settings.advanced), appState: appState)
        let before = try await drawnPixels(render)
        settings.general.showOnHover.toggle()
        settings.general.autoRehide.toggle()
        await render.settle { (try? render.pixels()) != before }
        #expect(try render.pixels() != before)
    }

    @Test("Visibility draws, and a different rehide strategy redraws it")
    func visibilityPane() async throws {
        let appState = AppState()
        let settings = appState.settings
        settings.general.autoRehide = true
        settings.general.rehideStrategy = .smart
        let render = render(MenuBarAccessPane(settings: settings.general, advancedSettings: settings.advanced), appState: appState)
        let before = try await drawnPixels(render)
        settings.general.showOnClick.toggle()
        settings.general.showOnHover.toggle()
        settings.general.rehideStrategy = .timed
        await render.settle { (try? render.pixels()) != before }
        #expect(try render.pixels() != before)
    }

    @Test("Tools draws each of its tabs")
    func toolsPane() async throws {
        let appState = AppState()
        let render = render(ToolsSettingsPane(settings: appState.settings.advanced), appState: appState)
        try await expectTabsDraw(["Repair", "Reset"], appState: appState, render: render)
    }

    @Test("Shortcuts draws each of its tabs")
    func hotkeysPane() async throws {
        let appState = AppState()
        let render = render(HotkeysSettingsPane(settings: appState.settings.hotkeys), appState: appState)
        try await expectTabsDraw(["Menu bar items", "Layout", "Thaw Bar"], appState: appState, render: render)
    }

    @Test("Displays draws each of its tabs")
    func displaysPane() async throws {
        let appState = AppState()
        let render = render(DisplaySettingsPane(displaySettings: appState.settings.displaySettings), appState: appState)
        try await expectTabsDraw(["This Space", "Wide displays"], appState: appState, render: render)
    }

    @Test("Thaw Bar draws its options for all displays")
    func thawBarPane() async throws {
        let appState = AppState()
        let render = render(ThawBarSettingsPane(displaySettings: appState.settings.displaySettings), appState: appState)
        try await expectTabsDraw(["Options for all displays"], appState: appState, render: render)
    }

    @Test("Automation draws its triggers, hooks and allowed apps")
    func automationPane() async throws {
        let appState = AppState()
        let settings = appState.settings
        let render = render(
            AutomationSettingsPane(settings: settings.automation, hookSettings: settings.automationHook, advancedSettings: settings.advanced),
            appState: appState
        )
        _ = try await drawnPixels(render)
    }

    @Test("Privacy, The Lab, About, Appearance, Widgets and Scripts draw")
    func remainingPanes() async throws {
        let appState = AppState()
        let settings = appState.settings
        _ = try await drawnPixels(render(PrivacySettingsPane(updatesManager: appState.updatesManager, advancedSettings: settings.advanced), appState: appState))
        _ = try await drawnPixels(render(TheLabSettingsPane(settings: settings.advanced), appState: appState))
        _ = try await drawnPixels(render(AboutSettingsPane(updatesManager: appState.updatesManager), appState: appState))
        _ = try await drawnPixels(render(MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager), appState: appState))
        _ = try await drawnPixels(render(WidgetsSettingsPane(), appState: appState))
        _ = try await drawnPixels(render(ScriptsSettingsPane(), appState: appState))
    }

    @Test("Profiles lists saved profiles and previews the selected one")
    func profilesPane() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["Work", "Home"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        manager.setAssociatedDisplay(uuid: "DISPLAY", displayName: "Studio", forProfileID: manager.profiles[0].id)
        let appState = AppState()
        let listed = try await drawnPixels(render(ProfileSettingsPane(profileManager: manager), appState: appState))

        let emptyTmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: emptyTmp) }
        let empty = render(ProfileSettingsPane(profileManager: ProfileManager(profilesDirectory: emptyTmp)), appState: appState)
        #expect(try await drawnPixels(empty) != listed, "an empty list draws its empty state")
    }

    @Test("The settings window draws its pages and switches to search results")
    func settingsView() async throws {
        let appState = AppState()
        appState.settings.general.simpleMode = false
        let navigation = appState.navigationState
        let view = SettingsView(appState: appState, navigationState: navigation, generalSettings: appState.settings.general)
        let render = OffscreenRender(view.environment(appState).frame(width: 1000, height: 800), size: CGSize(width: 1000, height: 800))
        let general = try await drawnPixels(render)

        navigation.settingsNavigationIdentifier = .about
        await render.settle { (try? render.pixels()) != general }
        #expect(try render.pixels() != general, "another page draws differently")
    }
}

/// Back and forward through the pages visited in the settings window.
@MainActor
@Suite("Settings page history", .serialized, .scratchDefaults)
struct SettingsPaneHistoryTests {
    @Test("Going back and forward walks the visited pages and moving on clears forward")
    func history() {
        let navigation = AppState().navigationState
        let history = SettingsPaneHistory()
        navigation.settingsNavigationIdentifier = .general

        history.record(leaving: .general)
        navigation.settingsNavigationIdentifier = .about
        history.record(leaving: .about)
        navigation.settingsNavigationIdentifier = .privacy
        #expect(history.back == [.general, .about])

        history.goBack(from: .privacy, navigationState: navigation)
        #expect(navigation.settingsNavigationIdentifier == .about)
        #expect(history.forward == [.privacy])
        #expect(history.back == [.general])

        history.goForward(from: .about, navigationState: navigation)
        #expect(navigation.settingsNavigationIdentifier == .privacy)
        #expect(history.forward.isEmpty)

        history.goBack(from: .privacy, navigationState: navigation)
        history.record(leaving: .about)
        #expect(history.forward.isEmpty, "a new visit drops the forward list")
    }

    @Test("History keeps the last fifty pages and ignores moves with nowhere to go")
    func historyBounds() {
        let navigation = AppState().navigationState
        let history = SettingsPaneHistory()
        history.goBack(from: .general, navigationState: navigation)
        history.goForward(from: .general, navigationState: navigation)
        #expect(history.back.isEmpty)
        #expect(history.forward.isEmpty)
        for _ in 0 ..< 60 {
            history.record(leaving: .about)
        }
        #expect(history.back.count == 50)
    }
}
