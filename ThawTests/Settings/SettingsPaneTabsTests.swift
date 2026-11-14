//
//  SettingsPaneTabsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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

    @Test("Layout's disclosures open the tab that holds them")
    func layoutDisclosures() {
        let navigation = AppNavigationState()
        navigation.requestedSettingsDisclosure = .layoutSpacers
        #expect(SettingsSearchNavigation.consumeDisclosure(navigationState: navigation, tabFor: LayoutDetailTab.tab(for:)) == .spacers)
        #expect(navigation.requestedSettingsDisclosure == nil)
    }

    @Test("Each page's tabs have their own icons")
    func iconsAreDistinct() {
        #expect(Set(ShortcutsTab.allCases.map(\.systemImage)).count == ShortcutsTab.allCases.count)
        #expect(Set(TroubleshootingTab.allCases.map(\.systemImage)).count == TroubleshootingTab.allCases.count)
        #expect(Set(DisplaysTab.allCases.map(\.systemImage)).count == DisplaysTab.allCases.count)
        #expect(Set(ThawBarTab.allCases.map(\.systemImage)).count == ThawBarTab.allCases.count)
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
