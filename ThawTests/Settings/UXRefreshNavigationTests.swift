//
//  UXRefreshNavigationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw
import ThawModuleKit

/// The sidebar lists direct destinations in groups, ending with About.
/// Scripts is an unbuilt placeholder with no route from the window.
@MainActor
@Suite("UX refresh navigation")
struct UXRefreshNavigationTests {
    // MARK: - Sidebar shape

    @Test("The sidebar puts Thaw's everyday pages first, then the modules that are on, then Manage, About alone last")
    func sidebarGroups() {
        #expect(SettingsSidebarPanes.groups.map(\.heading) == [nil, "On", "Manage", nil])
        #expect(SettingsSidebarPanes.all == [
            .general, .menuBarLayout, .visibility, .menuBarAppearance, .thawBar, .displays, .hotkeys,
            .profiles, .scripts, .triggers, .widgets,
            .modules, .privacy, .tools,
            .about,
        ], "Got: \(SettingsSidebarPanes.all)")
    }

    @Test("On and Manage have their headings, and About opens with a gap")
    func headingsAndGaps() {
        let rows = SettingsSidebarPanes.rows
        let on = String(localized: "On")
        let manage = String(localized: "Manage")
        #expect(rows.filter { $0.page == nil } == [.heading(on), .heading(manage), .gap])
        #expect(rows[7] == .heading(on))
        #expect(rows[12] == .heading(manage))
        #expect(rows.compactMap(\.page) == SettingsSidebarPanes.all)
    }

    @Test("A page that only opens a module leaves the sidebar while its module is off")
    func modulePanesFollowTheirModule() {
        let allOff = SettingsSidebarPanes.panesTurnedOff { _ in false }
        #expect(allOff == [.scripts, .triggers])
        #expect(SettingsSidebarPanes.panesTurnedOff { $0 == .scripts } == [.triggers])
        #expect(SettingsSidebarPanes.panesTurnedOff { _ in true }.isEmpty)
        #expect(
            SettingsSidebarPanes.panesTurnedOff(isEnabled: { _ in true }, profilesOn: false) == [.profiles],
            "Profiles leaves the sidebar while its switch in Modules is off"
        )

        let pages = SettingsSidebarPanes.rows(turnedOff: allOff).compactMap(\.page)
        #expect(!pages.contains(.scripts))
        #expect(!pages.contains(.triggers))
        #expect(pages.contains(.widgets), "Widgets also holds the panel, which Thaw runs itself")
    }

    @Test("A group whose pages are all off loses its heading, and the arrow keys skip what's off")
    func turnedOffGroupsAndArrows() {
        let rows = SettingsSidebarPanes.rows(turnedOff: [.profiles, .scripts, .triggers, .widgets])
        #expect(!rows.contains(.heading(String(localized: "On"))))
        #expect(SettingsSidebarPanes.page(moving: .down, from: .hotkeys, in: rows) == .modules)
        let scriptsOff = SettingsSidebarPanes.rows(turnedOff: [.scripts])
        #expect(SettingsSidebarPanes.page(moving: .down, from: .profiles, in: scriptsOff) == .triggers)
    }

    @Test("Settings that left Experiments and Triggers are found on their new panes")
    func movedSettingsSearchToTheirNewPanes() {
        let panes = Dictionary(uniqueKeysWithValues: SearchIndex.advancedEntries.map { ($0.id, $0.pane) })
        for id in ["lab.enableRecordingWatch", "lab.recordingWatchScreen", "lab.recordingWatchPlacement"] {
            #expect(panes[id] == nil, "\(id) is hidden for now, so search doesn't offer it")
        }
        #expect(panes["lab.enableControlItemPanel"] == .widgets)
        #expect(panes["lab.enableMenuBarItemDescenders"] == .visibility)
        #expect(panes["advanced.autoZenWhileSharingScreen"] == .visibility)
        #expect(panes["automation.menuBarItemAlertReveals"] == .visibility)
        #expect(panes["lab.enableDesktopMenuHiding"] == .general)
        #expect(panes["lab.zenModeWhileRecording"] == .visibility)
        #expect(!SearchIndex.advancedEntries.contains { $0.pane == .theLab }, "Experiments is gone, so nothing searches to it")
    }

    @Test("Links and saved panes that name Experiments open General")
    func experimentsOpensGeneral() {
        #expect(SettingsNavigationIdentifier.theLab.destination == .general)
        #expect(!SettingsSidebarPanes.all.contains(.theLab))
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

    @Test("Panes folded into others stay outside the sidebar")
    func panesOutsideTheSidebar() {
        let all = Set(SettingsSidebarPanes.all)
        #expect(!all.contains(.advanced), "Advanced was folded into General and Layout")
        #expect(!all.contains(.spaces), "Spaces is a section of Displays")
        #expect(SettingsNavigationIdentifier.spaces.destination == .displays)
        #expect(!all.contains(.automation), "Automation split into Triggers and Scripts")
        #expect(SettingsNavigationIdentifier.automation.destination == .triggers)
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
            "displays.hiddenItemsPresentation",
            "displays.thawBarLocation",
            "displays.thawBarLayout",
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

    @Test("Every search entry opens a pane that is in the sidebar")
    func everyEntryPaneIsInTheSidebar() {
        let sidebar = Set(SettingsSidebarPanes.all)
        for entry in SearchIndex.entries {
            #expect(sidebar.contains(entry.pane), "Entry \(entry.id) routes to \(entry.pane), which has no sidebar row")
        }
    }
}
