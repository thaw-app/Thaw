//
//  SettingsPaneTabsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Settings pages with tabs")
struct SettingsPaneTabsTests {
    private func sections(on pane: SettingsNavigationIdentifier) -> [(id: String, section: String)] {
        SearchIndex.entries.filter { $0.pane == pane }.compactMap { entry in entry.sectionText.map { (entry.id, $0) } }
    }

    @Test("Every Shortcuts, Troubleshooting and Displays search result opens a tab")
    func everyResultHasATab() {
        for (id, section) in sections(on: .hotkeys) {
            #expect(ShortcutsTab(section: section) != nil, "\(id) is in \(section), which no Shortcuts tab holds")
        }
        for (id, section) in sections(on: .tools) {
            #expect(TroubleshootingTab(section: section) != nil, "\(id) is in \(section), which no Troubleshooting tab holds")
        }
        for (id, section) in sections(on: .displays) {
            #expect(DisplaysTab(section: section) != nil, "\(id) is in \(section), which no Displays tab holds")
        }
    }

    @Test("The Thaw Bar's options for all displays open their tab, from search and from a link")
    func thawBarOptions() {
        #expect(ThawBarTab(section: "Options for all displays") == .allDisplays)
        #expect(ThawBarTab(section: "Preview") == nil)
        for id in ["general.lockThawBarPosition", "general.openHiddenItemsInMenuBar"] {
            let section = SearchIndex.entries.first { $0.id == id }?.sectionText
            #expect(section.flatMap(ThawBarTab.init(section:)) == .allDisplays, "\(id) opens All Displays")
        }
        // The shortcut choice sits beside Location on the Display tab, which a result opens by default.
        let shortcut = SearchIndex.entries.first { $0.id == "general.thawBarLocationOnHotkey" }
        #expect(shortcut?.pane == .thawBar)
        #expect(shortcut?.sectionText == nil)
    }

    @Test("The template for new displays is searched on the Displays Template tab")
    func templateTab() {
        #expect(DisplaysTab(section: "Template for new displays") == .template)
        let entry = SearchIndex.entries.first { $0.id == "displays.template" }
        #expect(entry?.pane == .displays)
        #expect(entry?.sectionText.flatMap(DisplaysTab.init(section:)) == .template)
    }

    @Test("Profile shortcuts are searched on Profiles, and the welcome screens are found on About")
    func profilesTabAndWelcomeScreens() {
        #expect(SearchIndex.entries.first { $0.id == "profiles.shortcuts" }?.pane == .profiles)
        #expect(SearchIndex.aboutEntries.first { $0.id == "about.replayOnboarding" }?.pane == .about)
        #expect(!SearchIndex.toolsEntries.contains { $0.id == "about.replayOnboarding" })
    }

    @Test("A section is handed to the page once, then forgotten")
    func sectionIsConsumedOnce() {
        let navigation = AppNavigationState()
        navigation.requestedSettingsSection = "Repair"
        #expect(SettingsSearchNavigation.consumeSection(navigationState: navigation, tabFor: TroubleshootingTab.init(section:)) == .repair)
        #expect(navigation.requestedSettingsSection == nil)
        navigation.requestedSettingsSection = "Elsewhere"
        #expect(SettingsSearchNavigation.consumeSection(navigationState: navigation, tabFor: TroubleshootingTab.init(section:)) == nil)
        #expect(navigation.requestedSettingsSection == "Elsewhere", "Another page's section is left for that page")
    }

    @Test("A disclosure is handed to the page whose tab holds it, once, then forgotten")
    func disclosureIsConsumedOnce() {
        let navigation = AppNavigationState()
        navigation.requestedSettingsDisclosure = .appearanceInsideShape
        #expect(SettingsSearchNavigation.consumeDisclosure(navigationState: navigation, tabFor: LayoutDetailTab.tab(for:)) == nil)
        #expect(navigation.requestedSettingsDisclosure == .appearanceInsideShape, "Another page's disclosure is left for that page")
        navigation.requestedSettingsDisclosure = .layoutSpacers
        #expect(SettingsSearchNavigation.consumeDisclosure(navigationState: navigation, tabFor: LayoutDetailTab.tab(for:)) == .spacers)
        #expect(navigation.requestedSettingsDisclosure == nil)
        #expect(SettingsSearchNavigation.consumeDisclosure(navigationState: navigation, tabFor: LayoutDetailTab.tab(for:)) == nil)
    }

    @Test("A search result for a Layout setting opens the tab that holds it")
    func layoutSearchOpensTheRightTab() {
        // The capture button sits above the tabs, so it shows on any of them.
        let outsideTabs = ["pane.menuBarLayout", "layout.captureHiddenItems"]
        let layoutEntries = SearchIndex.entries.filter { $0.pane == .menuBarLayout && !outsideTabs.contains($0.id) }
        #expect(!layoutEntries.isEmpty)
        for entry in layoutEntries {
            #expect(LayoutDetailTab.tab(for: entry.disclosure) != nil, "\(entry.id) has no tab, so search would land on the wrong one")
        }
        #expect(LayoutDetailTab.tab(for: .layoutSpacers) == .spacers)
        #expect(LayoutDetailTab.tab(for: .layoutOptions) == .options)
        #expect(LayoutDetailTab.tab(for: .layoutAppleItems) == .appleItems)
        #expect(LayoutDetailTab.tab(for: nil) == nil)
    }

    @Test("Layout's tabs run Options, Groups, Spacers, then Apple's items")
    func layoutTabOrder() {
        #expect(LayoutDetailTab.allCases == [.options, .groups, .spacers, .appleItems])
    }

    @Test("Each page's tabs have their own icons")
    func iconsAreDistinct() {
        #expect(Set(ShortcutsTab.allCases.map(\.systemImage)).count == ShortcutsTab.allCases.count)
        #expect(Set(TroubleshootingTab.allCases.map(\.systemImage)).count == TroubleshootingTab.allCases.count)
        #expect(Set(DisplaysTab.allCases.map(\.systemImage)).count == DisplaysTab.allCases.count)
        #expect(Set(ThawBarTab.allCases.map(\.systemImage)).count == ThawBarTab.allCases.count)
        #expect(Set(LayoutDetailTab.allCases.map(\.systemImage)).count == LayoutDetailTab.allCases.count)
    }

    @Test("Shortcuts has a Profiles tab only while Profiles is on and a profile is saved")
    func shortcutsProfilesTab() {
        let withoutProfiles = ShortcutsTab.allCases.filter { $0 != .profiles }
        #expect(ShortcutsTab.offered(hasProfiles: true, profilesOn: true) == ShortcutsTab.allCases)
        #expect(ShortcutsTab.offered(hasProfiles: false, profilesOn: true) == withoutProfiles)
        #expect(ShortcutsTab.offered(hasProfiles: true, profilesOn: false) == withoutProfiles, "with Profiles off its shortcuts aren't listened for")
        #expect(ShortcutsTab.offered(hasProfiles: false, profilesOn: false) == withoutProfiles)
    }
}

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
