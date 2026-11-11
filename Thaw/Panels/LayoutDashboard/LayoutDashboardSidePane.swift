//
//  LayoutDashboardSidePane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The Layout window's right pane: the selected item's editor, or Groups, Spacers or Apple's items.
struct LayoutDashboardSidePane: View {
    @Environment(AppState.self) private var appState
    let selection: LayoutSelectionModel
    @Binding var pane: Pane
    /// False while the window is away from the bar it edits: the panes still show, but nothing changes.
    let isEditable: Bool

    enum Pane: CaseIterable, ThawTab {
        case item, groups, spacers, appleItems

        var title: LocalizedStringResource {
            switch self {
            case .item: "Item"
            case .groups: "Groups"
            case .spacers: "Spacers"
            case .appleItems: "Apple’s Items"
            }
        }

        var systemImage: String {
            if case .item = self {
                "slider.horizontal.3"
            } else {
                tab?.systemImage ?? "circle"
            }
        }

        var tab: LayoutDetailTab? {
            switch self {
            case .item: nil
            case .groups: .groups
            case .spacers: .spacers
            case .appleItems: .appleItems
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ThawTabStrip(selection: $pane, tabs: Pane.allCases)
                .padding(ThawSpacing.base)
            Divider()
            if let tab = pane.tab {
                ThawForm(readingWidth: .full) {
                    LayoutDetailTabs(
                        itemManager: appState.itemManager,
                        canArrangeLayout: !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                        isHidingUnavailable: appState.menuBarManager.sectionController.isHidingUnavailable,
                        includesOptions: false,
                        fixedTab: tab,
                        groupNavigation: LayoutGroupNavigation(selection: selection, appState: appState)
                    )
                    // On the rows, not the form, so the pane still scrolls.
                    .disabled(!isEditable)
                }
            } else {
                LayoutItemEditor(selection: selection, isEditable: isEditable)
            }
        }
        // Picking an item means editing it.
        .onChange(of: selection.anchorItemID) { _, id in
            if id != nil {
                pane = .item
            }
        }
    }
}
