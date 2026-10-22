//
//  SettingsSidebarPaneList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - SettingsSidebarPanes

/// The sidebar's pages in groups, as in Floe: everyday pages, the extras under Modules, Manage, then About.
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
            heading: String(localized: "Modules", comment: "A heading in the settings sidebar, over the Profiles, Automation and Experiments pages, the parts of Thaw beyond the everyday pages."),
            panes: [.profiles, .automation, .theLab]
        ),
        Group(
            heading: String(localized: "Manage", comment: "A heading in the settings sidebar, over the Privacy and Troubleshooting pages, which look after Thaw itself."),
            panes: [.privacy, .tools]
        ),
        Group(heading: nil, panes: [.about]),
    ]

    /// Every page, in sidebar order.
    static let all: [SettingsNavigationIdentifier] = groups.flatMap(\.panes)

    /// The sidebar's rows, headings included. A group with no heading after
    /// another group opens with a gap.
    static let rows: [SettingsSidebarRow] = groups.reduce(into: []) { rows, group in
        if let heading = group.heading {
            rows.append(.heading(heading))
        } else if !rows.isEmpty {
            rows.append(.gap)
        }
        rows += group.panes.map(SettingsSidebarRow.page)
    }

    /// The selected row. None while search results show, so a click on any row ends the search,
    /// and none for a page outside the sidebar.
    static func selectedRow(current: SettingsNavigationIdentifier, isSearching: Bool) -> SettingsNavigationIdentifier? {
        guard !isSearching, all.contains(current) else { return nil }
        return current
    }

    /// The page above or below the current one, past the headings, or nil
    /// at either end or for left and right.
    static func page(moving direction: MoveCommandDirection, from current: SettingsNavigationIdentifier) -> SettingsNavigationIdentifier? {
        all.neighbor(of: current, moving: direction)
    }

    /// Opens a page from the sidebar. The search is cleared first: the page
    /// may already be selected, and a leftover search would keep the detail
    /// column on results.
    static func open(_ pane: SettingsNavigationIdentifier, searchModel: SearchModel, navigationState: AppNavigationState) {
        searchModel.searchText = ""
        SettingsSearchNavigation.selectSidebarPane(pane, navigationState: navigationState)
    }

    /// Opens the page above or below the current one, when there is one.
    static func move(_ direction: MoveCommandDirection, searchModel: SearchModel, navigationState: AppNavigationState) {
        guard let pane = page(moving: direction, from: navigationState.settingsNavigationIdentifier) else { return }
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
    @FocusState private var isFocused: Bool

    static let listWidth: CGFloat = 220

    private var isSearching: Bool {
        !searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedRow: SettingsNavigationIdentifier? {
        SettingsSidebarPanes.selectedRow(current: navigationState.settingsNavigationIdentifier, isSearching: isSearching)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                    ForEach(SettingsSidebarPanes.rows) { row in
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
            SettingsSidebarPanes.move(direction, searchModel: searchModel, navigationState: navigationState)
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

/// A page's row: its symbol and its name, on Thaw's shared selection fill
/// when selected. The fill is the same whether the window is key or not,
/// and the label keeps its own color on it. The selected row also wears the
/// focus ring while the sidebar has keyboard focus.
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
