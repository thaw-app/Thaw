//
//  UXRefreshNavigationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The sidebar lists direct destinations in groups, ending with About.
/// Scripts is an unbuilt placeholder with no route from the window.
@MainActor
@Suite("UX refresh navigation")
struct UXRefreshNavigationTests {
    // MARK: - Sidebar shape

    @Test("The sidebar puts Thaw's everyday pages first, then the extras under Modules, then Manage, About alone last")
    func sidebarGroups() {
        #expect(SettingsSidebarPanes.groups.map(\.heading) == [nil, "Modules", "Manage", nil])
        #expect(SettingsSidebarPanes.all == [
            .general, .menuBarLayout, .visibility, .menuBarAppearance, .thawBar, .displays, .hotkeys,
            .profiles, .automation, .theLab,
            .privacy, .tools,
            .about,
        ], "Got: \(SettingsSidebarPanes.all)")
    }

    @Test("Modules and Manage have their headings, and About opens with a gap")
    func headingsAndGaps() {
        let rows = SettingsSidebarPanes.rows
        #expect(rows.filter { $0.page == nil } == [.heading("Modules"), .heading("Manage"), .gap])
        #expect(rows[7] == .heading("Modules"))
        #expect(rows[11] == .heading("Manage"))
        #expect(rows.compactMap(\.page) == SettingsSidebarPanes.all)
    }

    @Test("The arrow keys step over headings and stop at the ends")
    func arrowKeysSkipHeadings() {
        #expect(SettingsSidebarPanes.page(moving: .down, from: .hotkeys) == .profiles)
        #expect(SettingsSidebarPanes.page(moving: .up, from: .profiles) == .hotkeys)
        #expect(SettingsSidebarPanes.page(moving: .up, from: .general) == nil)
        #expect(SettingsSidebarPanes.page(moving: .down, from: .about) == nil)
        #expect(SettingsSidebarPanes.page(moving: .down, from: .spaces) == nil)
        #expect(SettingsSidebarPanes.page(moving: .left, from: .hotkeys) == nil)
    }

    @Test("No sidebar row is selected while search results show, so any row ends the search")
    func searchDeselectsTheSidebar() {
        #expect(SettingsSidebarPanes.selectedRow(current: .visibility, isSearching: false) == .visibility)
        #expect(SettingsSidebarPanes.selectedRow(current: .visibility, isSearching: true) == nil)
        #expect(SettingsSidebarPanes.selectedRow(current: .spaces, isSearching: false) == nil)
    }

    @Test("About is last")
    func aboutIsLast() {
        #expect(SettingsSidebarPanes.rows.last == .page(.about))
    }

    @Test("Placeholder and absorbed panes stay outside the sidebar")
    func panesOutsideTheSidebar() {
        let all = Set(SettingsSidebarPanes.all)
        #expect(!all.contains(.scripts), "Scripts is an unbuilt placeholder, not a sidebar destination")
        #expect(!all.contains(.widgets), "Custom Status Icon is an Experiments toggle, not a sidebar destination")
        #expect(!all.contains(.advanced), "Advanced was dissolved into Menu Bar Behavior and Automation")
        #expect(!all.contains(.spaces), "Spaces is a section of Displays & Spaces")
        #expect(SettingsNavigationIdentifier.spaces.destination == .displays)
        #expect(!all.contains(.triggers), "Triggers is a section of Automation")
        #expect(SettingsNavigationIdentifier.triggers.destination == .automation)
        #expect(SettingsNavigationIdentifier.general.destination == .general)
        // All remain valid identifiers for saved selections, thaw:// and other routes.
        #expect(SettingsNavigationIdentifier(rawValue: "About") == .about)
        #expect(SettingsNavigationIdentifier(rawValue: "Scripts") == .scripts)
    }

    @Test("Every sidebar pane is a direct destination, no hub indirection")
    func listedPanesAreDirect() {
        // Each listed identifier must render its own pane, without hub remapping.
        let listed = Set(SettingsSidebarPanes.all)
        let allPanes = Set(SettingsNavigationIdentifier.allCases)
        #expect(listed.isSubset(of: allPanes))
    }

    // MARK: - Persistence compatibility

    @Test("Old pane raw values still decode")
    func oldRawValuesDecode() {
        // Raw values are the persistence contract for saved lastSettingsPane selections.
        let legacy: [String: SettingsNavigationIdentifier] = [
            "General": .general,
            "Menu Bar Layout": .menuBarLayout,
            "Visibility": .visibility,
            "Thaw Bar": .thawBar,
            "Displays": .displays,
            "Spaces": .spaces,
            "Menu Bar Appearance": .menuBarAppearance,
            "Hotkeys": .hotkeys,
            "Profiles": .profiles,
            "Advanced": .advanced,
            "Automation": .automation,
            "Triggers": .triggers,
            "Scripts": .scripts,
            "Widgets": .widgets,
            "The Lab": .theLab,
            "Tools": .tools,
            "Privacy": .privacy,
            "About": .about,
        ]
        for (raw, expected) in legacy {
            #expect(SettingsNavigationIdentifier(rawValue: raw) == expected, "Legacy raw value \(raw) no longer decodes")
        }
    }

    // MARK: - Search relocation

    @Test("Thaw Bar search entries route to the Thaw Bar page")
    func thawBarEntriesRouteToThawBar() {
        let thawBarIDs: Set = [
            "pane.thawBar",
            "displays.useThawBar",
            "displays.thawBarLocation",
            "displays.thawBarLayout",
            "displays.alwaysShowHiddenItems",
            "general.lockThawBarPosition",
            "general.thawBarLocationOnHotkey",
        ]
        for entry in SearchIndex.entries where thawBarIDs.contains(entry.id) {
            #expect(entry.pane == .thawBar, "Entry \(entry.id) should route to .thawBar, got \(entry.pane)")
        }
        let indexed = Set(SearchIndex.entries.map(\.id))
        for id in thawBarIDs {
            #expect(indexed.contains(id), "Expected Thaw Bar entry \(id) is missing from the index")
        }
    }

    @Test("Reveal, rehide, search, and tooltip entries route to Visibility")
    func revealEntriesRouteToVisibility() {
        let visibilityIDs: Set = [
            "general.showOnClick",
            "general.showOnHover",
            "general.showOnScroll",
            "general.autoRehide",
            "general.menuBarSearchPresentation",
            "general.showMenuBarTooltips",
            "general.tempShowInterval",
        ]
        for entry in SearchIndex.entries where visibilityIDs.contains(entry.id) {
            #expect(entry.pane == .visibility, "Entry \(entry.id) should route to .visibility, got \(entry.pane)")
        }
    }

    @Test("Menu bar spacing entries stay on the Displays page")
    func spacingEntriesStayOnDisplays() {
        let stayIDs: Set = [
            "displays.itemSpacing",
            "displays.spacingApplyMode",
        ]
        for entry in SearchIndex.entries where stayIDs.contains(entry.id) {
            #expect(entry.pane == .displays, "Entry \(entry.id) should stay on .displays, got \(entry.pane)")
        }
    }

    @Test("Every search entry's pane is a known identifier")
    func everyEntryPaneIsKnown() {
        let known = Set(SettingsNavigationIdentifier.allCases)
        for entry in SearchIndex.entries {
            #expect(known.contains(entry.pane), "Entry \(entry.id) routes to unknown pane \(entry.pane)")
        }
    }
}
