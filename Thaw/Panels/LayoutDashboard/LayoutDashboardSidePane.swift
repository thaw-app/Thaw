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

    @State private var pane = Pane.item

    enum Pane: CaseIterable {
        case item, groups, spacers, appleItems

        var title: LocalizedStringKey {
            switch self {
            case .item: "Item"
            case .groups: "Groups"
            case .spacers: "Spacers"
            case .appleItems: "Apple"
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
            Picker("Show", selection: $pane) {
                ForEach(Pane.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(ThawSpacing.base)
            Divider()
            if let tab = pane.tab {
                ThawForm(readingWidth: .full) {
                    LayoutDetailTabs(
                        itemManager: appState.itemManager,
                        canArrangeLayout: !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                        isHidingUnavailable: false,
                        includesOptions: false,
                        fixedTab: tab
                    )
                }
            } else {
                LayoutItemEditor(selection: selection)
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
