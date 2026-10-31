//
//  SettingsSidebarPaneList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

// MARK: - SettingsSidebarPanes

/// The sidebar's pages in groups, as in Floe: everyday pages, the modules that are on, Manage, then About.
enum SettingsSidebarPanes {
    /// One group of pages, under its heading when it has one.
    struct Group: Identifiable {
        let heading: String?
        let panes: [SettingsNavigationIdentifier]

        var id: SettingsNavigationIdentifier {
            panes[0]
        }
    }

    static let groups: [Group] = [
        Group(heading: nil, panes: [.general, .menuBarLayout, .visibility, .menuBarAppearance, .thawBar, .displays, .hotkeys]),
        Group(
            heading: String(localized: "On", comment: "A heading in the settings sidebar, over the pages of the parts switched on in Modules."),
            panes: [.profiles, .scripts, .triggers, .widgets]
        ),
        Group(
            heading: String(localized: "Manage", comment: "A heading in the settings sidebar, over the Modules, Privacy and Troubleshooting pages, which look after Thaw itself."),
            panes: [.modules, .privacy, .tools]
        ),
        Group(heading: nil, panes: [.about]),
    ]

    /// Every page, in sidebar order.
    static let all: [SettingsNavigationIdentifier] = groups.flatMap(\.panes)

    /// Pages that belong to a module, by the module. Each one leaves the
    /// sidebar while its module is off; Modules turns it back on.
    static let modulePanes: [SettingsNavigationIdentifier: ModuleIdentifier] = [
        .scripts: .scripts,
        .triggers: .triggers,
        .widgets: .widgets,
    ]

    /// The pages whose part is switched off in Modules, Profiles included.
    static func panesTurnedOff(isEnabled: (ModuleIdentifier) -> Bool, profilesOn: Bool = true) -> Set<SettingsNavigationIdentifier> {
        var off = Set(modulePanes.filter { !isEnabled($0.value) }.map(\.key))
        if !profilesOn {
            off.insert(.profiles)
        }
        return off
    }

    /// The sidebar's rows with every page on.
    static let rows = rows(turnedOff: [])

    /// The sidebar's rows, headings included, without the pages that are
    /// turned off. A group left with no pages loses its heading too, and a
    /// group with no heading after another group opens with a gap.
    static func rows(turnedOff: Set<SettingsNavigationIdentifier>) -> [SettingsSidebarRow] {
        var rows = [SettingsSidebarRow]()
        for group in groups {
            let pages = group.panes.filter { !turnedOff.contains($0) }.map(SettingsSidebarRow.page)
            guard !pages.isEmpty else { continue }
            if let heading = group.heading {
                rows.append(.heading(heading))
            } else if !rows.isEmpty {
                rows.append(.gap)
            }
            rows += pages
        }
        return rows
    }

    /// Whether the open page shows as selected. Not while search results show, so a click on any
    /// row ends the search, and not for a page outside the sidebar.
    static func showsSelection(current: SettingsNavigationIdentifier, isSearching: Bool) -> Bool {
        !isSearching && all.contains(current)
    }

    /// Opens a page from the sidebar. The search is cleared first: the page
    /// may already be selected, and a leftover search would keep the detail
    /// column on results.
    static func open(_ pane: SettingsNavigationIdentifier, searchModel: SearchModel, navigationState: AppNavigationState) {
        searchModel.searchText = ""
        SettingsSearchNavigation.selectSidebarPane(pane, navigationState: navigationState)
    }
}

/// One row of the sidebar: a page to select, the heading over a group, or
/// the space before a group without one.
typealias SettingsSidebarRow = ThawSidebarRow<SettingsNavigationIdentifier>

// MARK: - SettingsSidebarPaneList

/// The shared sidebar with Thaw's pages, on the default gold selection.
struct SettingsSidebarPaneList: View {
    @Environment(SearchModel.self) private var searchModel
    let navigationState: AppNavigationState
    /// Pages whose module is off, left out of the list.
    var turnedOff: Set<SettingsNavigationIdentifier> = []

    static let listWidth: CGFloat = 220

    private var isSearching: Bool {
        !searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rows: [SettingsSidebarRow] {
        SettingsSidebarPanes.rows(turnedOff: turnedOff)
    }

    var body: some View {
        let current = navigationState.settingsNavigationIdentifier
        ThawSidebar(
            rows: rows,
            current: current,
            showsSelection: SettingsSidebarPanes.showsSelection(current: current, isSearching: isSearching),
            select: { SettingsSidebarPanes.open($0, searchModel: searchModel, navigationState: navigationState) },
            title: { Text($0.localized) },
            icon: { $0.iconResource.view }
        )
    }
}
