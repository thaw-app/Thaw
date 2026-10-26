//
//  SettingsPaneTabsViewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// A page's tab strip, drawn off screen, taking the tab a search result asks for.
@Suite("Settings page tab strip", .serialized, .scratchDefaults)
@MainActor
struct SettingsPaneTabsViewTests {
    /// Holds the strip's selection, so the test sees what the strip writes.
    @MainActor
    private final class Selection<Tab> {
        var tab: Tab

        init(_ tab: Tab) {
            self.tab = tab
        }

        var binding: Binding<Tab> {
            Binding(get: { self.tab }, set: { self.tab = $0 })
        }
    }

    private func render(_ strip: some View, appState: AppState) -> OffscreenRender<some View> {
        OffscreenRender(strip.environment(appState).frame(width: 480, height: 80), size: CGSize(width: 480, height: 80))
    }

    @Test("A section asked for before the page opens selects its tab, once")
    func sectionOnOpen() async {
        let appState = AppState()
        appState.navigationState.requestedSettingsSection = "Repair"
        let selection = Selection(TroubleshootingTab.diagnostics)
        let render = render(
            SettingsPaneTabs(selection: selection.binding, tabs: TroubleshootingTab.allCases, tabForSection: TroubleshootingTab.init(section:)),
            appState: appState
        )
        await render.settle { selection.tab == .repair }
        #expect(selection.tab == .repair)
        #expect(appState.navigationState.requestedSettingsSection == nil)
    }

    @Test("A disclosure asked for while the page is open selects its tab")
    func disclosureWhileOpen() async throws {
        let appState = AppState()
        let selection = Selection(LayoutDetailTab.options)
        let render = render(
            SettingsPaneTabs(selection: selection.binding, tabs: LayoutDetailTab.allCases, tabForDisclosure: { LayoutDetailTab.tab(for: $0) }),
            appState: appState
        )
        let before = try render.pixels()
        #expect(before.contains { $0 != 0 }, "the strip draws its tabs")
        appState.navigationState.requestedSettingsDisclosure = .layoutSpacers
        await render.settle { selection.tab == .spacers }
        #expect(selection.tab == .spacers)
        #expect(appState.navigationState.requestedSettingsDisclosure == nil)
        await render.settle { (try? render.pixels()) != before }
        #expect(try render.pixels() != before, "the strip redraws on the new tab")
    }

    @Test("A request no tab of this page holds is left for another page")
    func otherPagesRequests() async {
        let appState = AppState()
        appState.navigationState.requestedSettingsSection = "Repair"
        appState.navigationState.requestedSettingsDisclosure = .layoutSpacers
        let selection = Selection(ThawBarTab.look)
        let render = render(SettingsPaneTabs(selection: selection.binding, tabs: ThawBarTab.allCases), appState: appState)
        await render.settle(within: .milliseconds(300)) { false }
        #expect(selection.tab == .look)
        #expect(appState.navigationState.requestedSettingsSection == "Repair")
        #expect(appState.navigationState.requestedSettingsDisclosure == .layoutSpacers)
    }
}
