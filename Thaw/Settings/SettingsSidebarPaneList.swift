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

    /// The selected row. None while search results show, so a click on any row ends the search,
    /// and none for a page outside the sidebar.
    static func selectedRow(current: SettingsNavigationIdentifier, isSearching: Bool) -> SettingsNavigationIdentifier? {
        guard !isSearching, all.contains(current) else { return nil }
        return current
    }

    /// The page above or below the current one among the rows shown, past
    /// the headings, or nil at either end or for left and right.
    static func page(
        moving direction: MoveCommandDirection,
        from current: SettingsNavigationIdentifier,
        in rows: [SettingsSidebarRow] = rows
    ) -> SettingsNavigationIdentifier? {
        rows.compactMap(\.page).neighbor(of: current, moving: direction)
    }

    /// Opens a page from the sidebar. The search is cleared first: the page
    /// may already be selected, and a leftover search would keep the detail
    /// column on results.
    static func open(_ pane: SettingsNavigationIdentifier, searchModel: SearchModel, navigationState: AppNavigationState) {
        searchModel.searchText = ""
        SettingsSearchNavigation.selectSidebarPane(pane, navigationState: navigationState)
    }

    /// Opens the page above or below the current one, when there is one.
    static func move(
        _ direction: MoveCommandDirection,
        in rows: [SettingsSidebarRow] = rows,
        searchModel: SearchModel,
        navigationState: AppNavigationState
    ) {
        guard let pane = page(moving: direction, from: navigationState.settingsNavigationIdentifier, in: rows) else { return }
        open(pane, searchModel: searchModel, navigationState: navigationState)
    }
}

/// One row of the sidebar: a page to select, the heading over a group, or
/// the space before a group without one.
enum SettingsSidebarRow: Identifiable, Equatable {
    case heading(String)
    case gap
    case page(SettingsNavigationIdentifier)

    var id: String {
        switch self {
        case let .heading(title): "heading:" + title
        case .gap: "gap"
        case let .page(pane): pane.rawValue
        }
    }

    /// The page a click selects; nil for a heading or a gap, which nothing selects.
    var page: SettingsNavigationIdentifier? {
        if case let .page(pane) = self {
            return pane
        }
        return nil
    }
}

// MARK: - SettingsSidebarPaneList

/// Rows of its own, not a List: a List draws its own selection, and its Sections crash AppKit
/// on macOS 27.0 and 27.2 (a freed row view in sizeLastColumnToFit).
struct SettingsSidebarPaneList: View {
    @Environment(SearchModel.self) private var searchModel
    let navigationState: AppNavigationState
    /// Pages whose module is off, left out of the list.
    var turnedOff: Set<SettingsNavigationIdentifier> = []
    @FocusState private var isFocused: Bool

    static let listWidth: CGFloat = 220

    private var isSearching: Bool {
        !searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rows: [SettingsSidebarRow] {
        SettingsSidebarPanes.rows(turnedOff: turnedOff)
    }

    private var selectedRow: SettingsNavigationIdentifier? {
        SettingsSidebarPanes.selectedRow(current: navigationState.settingsNavigationIdentifier, isSearching: isSearching)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                    ForEach(rows) { row in
                        switch row {
                        case let .heading(title):
                            SettingsSidebarHeading(title: title)
                        case .gap:
                            // The same room a heading leaves above its group.
                            Spacer(minLength: ThawSpacing.gutter)
                                .frame(height: ThawSpacing.gutter)
                        case let .page(pane):
                            SettingsSidebarPageRow(pane: pane, isSelected: pane == selectedRow, showsFocus: isFocused) {
                                SettingsSidebarPanes.open(pane, searchModel: searchModel, navigationState: navigationState)
                            }
                            .id(pane.rawValue)
                        }
                    }
                }
                .padding(.horizontal, ThawSpacing.row)
                .padding(.vertical, ThawSpacing.base)
            }
            // A page chosen by the arrow keys, a search result or a link stays in sight.
            .onChange(of: navigationState.settingsNavigationIdentifier) { _, pane in
                proxy.scrollTo(pane.rawValue)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .thawKeyboardList(isFocused: $isFocused) { direction in
            SettingsSidebarPanes.move(direction, in: rows, searchModel: searchModel, navigationState: navigationState)
        }
    }
}

/// The small uppercase name over a group of pages.
private struct SettingsSidebarHeading: View {
    let title: String

    var body: some View {
        ThawListHeading(Text(verbatim: title))
            // Room above each group, so the groups read apart.
            .padding(.top, ThawSpacing.gutter)
            .padding(.bottom, ThawSpacing.tight)
            .padding(.leading, ThawSpacing.row)
    }
}

/// A page's row on the shared selection fill, with the focus ring while the sidebar has focus.
private struct SettingsSidebarPageRow: View {
    let pane: SettingsNavigationIdentifier
    let isSelected: Bool
    let showsFocus: Bool
    let select: () -> Void

    /// The box the symbols share, so the names line up.
    private static let iconBox: CGFloat = 18
    private static let height: CGFloat = 32
    private static let shape = RoundedRectangle(cornerRadius: ThawRadius.row, style: .continuous)

    var body: some View {
        Button(action: select) {
            Label {
                Text(pane.localized)
                    .font(ThawType.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            } icon: {
                pane.iconResource.view
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.iconBox, height: Self.iconBox)
            }
            .padding(.horizontal, ThawSpacing.row)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .thawSelectedFill(isSelected, in: Self.shape)
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .thawSelectionCue(isSelected: isSelected, in: Self.shape)
        .thawFocusRing(isSelected && showsFocus, in: Self.shape)
    }
}
