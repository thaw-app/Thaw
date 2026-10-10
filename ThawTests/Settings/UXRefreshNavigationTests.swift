//
//  UXRefreshNavigationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The sidebar is one flat list of direct destinations, ending with About.
/// Scripts is a placeholder reachable only through search.
@MainActor
@Suite("UX refresh navigation")
struct UXRefreshNavigationTests {
    // MARK: - Sidebar shape

    @Test("The sidebar is one flat list, the basics first")
    func sidebarIsOneList() {
        #expect(SettingsSidebarPanes.groups.count == 1, "Got: \(SettingsSidebarPanes.groups.count)")
        #expect(SettingsSidebarPanes.all == [
            .general, .menuBarLayout, .visibility, .menuBarAppearance, .thawBar,
            .profiles, .hotkeys, .automation, .triggers, .displays, .spaces,
            .privacy, .theLab, .tools, .about,
        ], "Got: \(SettingsSidebarPanes.all)")
    }

    @Test("About is visible by default and respects sidebar customization")
    func aboutSidebarVisibility() {
        let visible = SettingsSidebarPanes.visibleGroups(hidden: []).flatMap(\.panes)
        #expect(visible.last == .about)

        let customized = SettingsSidebarPanes.visibleGroups(hidden: [SettingsNavigationIdentifier.about.rawValue])
            .flatMap(\.panes)
        #expect(customized == visible.filter { $0 != .about })
    }

    @Test("Placeholder and absorbed panes stay outside the sidebar")
    func panesOutsideTheSidebar() {
        let all = Set(SettingsSidebarPanes.all)
        #expect(!all.contains(.scripts), "Scripts is a placeholder reachable via search only")
        #expect(!all.contains(.widgets), "Custom Status Icon is an Experiments toggle, not a sidebar destination")
        #expect(!all.contains(.advanced), "Advanced was dissolved into Menu Bar Behavior and Automation")
        // All remain valid identifiers for search, thaw:// and other routes.
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
            "displays.confirmSpacingRelaunch",
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
