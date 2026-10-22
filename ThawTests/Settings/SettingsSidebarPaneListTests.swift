//
//  SettingsSidebarPaneListTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The settings sidebar: its rows, how it opens pages, and how it draws them.
@Suite("Settings sidebar list", .serialized, .scratchDefaults)
@MainActor
struct SettingsSidebarPaneListTests {
    private let size = CGSize(width: SettingsSidebarPaneList.listWidth, height: 900)

    private func render(
        _ navigation: AppNavigationState,
        searchModel: SearchModel
    ) -> OffscreenRender<some View> {
        OffscreenRender(
            SettingsSidebarPaneList(navigationState: navigation)
                .environment(searchModel)
                .frame(width: size.width, height: size.height),
            size: size
        )
    }

    @Test("Each row has its own identity, and a group is known by its first page")
    func rowIdentities() {
        let ids = SettingsSidebarPanes.rows.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("heading:Modules"))
        #expect(ids.contains("gap"))
        #expect(ids.contains(SettingsNavigationIdentifier.privacy.rawValue))
        #expect(SettingsSidebarPanes.groups.map(\.id) == [.general, .profiles, .privacy, .about])
        #expect(SettingsSidebarRow.heading("Manage").page == nil)
        #expect(SettingsSidebarRow.gap.page == nil)
        #expect(SettingsSidebarRow.page(.tools).page == .tools)
    }

    @Test("Opening a page clears the search, even when the page is already open")
    func openClearsSearch() {
        let navigation = AppNavigationState()
        let searchModel = SearchModel()
        navigation.requestedSettingsSection = "Repair"
        searchModel.searchText = "hide"
        SettingsSidebarPanes.open(.privacy, searchModel: searchModel, navigationState: navigation)
        #expect(navigation.settingsNavigationIdentifier == .privacy)
        #expect(searchModel.searchText.isEmpty)
        #expect(navigation.requestedSettingsSection == nil, "a leftover search request is dropped")
        searchModel.searchText = "hide"
        SettingsSidebarPanes.open(.privacy, searchModel: searchModel, navigationState: navigation)
        #expect(searchModel.searchText.isEmpty)
    }

    @Test("The arrow keys move through the pages past the headings and stop at either end")
    func arrowKeys() {
        let navigation = AppNavigationState()
        let searchModel = SearchModel()
        navigation.settingsNavigationIdentifier = .hotkeys
        SettingsSidebarPanes.move(.down, searchModel: searchModel, navigationState: navigation)
        #expect(navigation.settingsNavigationIdentifier == .profiles)
        SettingsSidebarPanes.move(.up, searchModel: searchModel, navigationState: navigation)
        #expect(navigation.settingsNavigationIdentifier == .hotkeys)
        navigation.settingsNavigationIdentifier = .about
        searchModel.searchText = "hide"
        SettingsSidebarPanes.move(.down, searchModel: searchModel, navigationState: navigation)
        #expect(navigation.settingsNavigationIdentifier == .about)
        #expect(searchModel.searchText == "hide", "a move that goes nowhere keeps the search")
        SettingsSidebarPanes.move(.left, searchModel: searchModel, navigationState: navigation)
        #expect(navigation.settingsNavigationIdentifier == .about)
    }

    @Test("The selection fill follows the open page, and no row is filled while searching")
    func drawsTheSelection() async throws {
        let navigation = AppNavigationState()
        let searchModel = SearchModel()
        navigation.settingsNavigationIdentifier = .general
        let render = render(navigation, searchModel: searchModel)
        let onGeneral = try render.pixels()
        #expect(onGeneral.contains { $0 != 0 }, "the list draws something")

        navigation.settingsNavigationIdentifier = .privacy
        await render.settle { (try? render.pixels()) != onGeneral }
        let onPrivacy = try render.pixels()
        #expect(onPrivacy != onGeneral)

        searchModel.searchText = "spacing"
        await render.settle { (try? render.pixels()) != onPrivacy }
        let searching = try render.pixels()
        #expect(searching != onPrivacy)
        #expect(searching != onGeneral)

        searchModel.searchText = "   "
        await render.settle { (try? render.pixels()) == onPrivacy }
        #expect(try render.pixels() == onPrivacy, "a blank search is not a search")
    }
}
