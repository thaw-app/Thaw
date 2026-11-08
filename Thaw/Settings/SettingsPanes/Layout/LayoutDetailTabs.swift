//
//  LayoutDetailTabs.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The lists under the bars, one at a time: Options, Groups, Spacers and Apple's Items.
/// Search results switch to the tab that holds them. The Layout window leaves Options out.
struct LayoutDetailTabs: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    let canArrangeLayout: Bool
    let isHidingUnavailable: Bool
    var includesOptions = true
    /// Shows this tab without the tab bar, for a window that switches tabs itself.
    var fixedTab: LayoutDetailTab?

    @State private var tab: LayoutDetailTab?

    var body: some View {
        let settings = appState.settings.layout
        // Groups and Apple's items need the bars, so without them only Options and Spacers are offered.
        let offered = canArrangeLayout ? LayoutDetailTab.allCases : [.options, .spacers]
        let tabs = includesOptions ? offered : offered.filter { $0 != .options }
        let selected = fixedTab ?? tab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs[0]
        if fixedTab == nil {
            SettingsPaneTabs(
                selection: Binding(get: { selected }, set: { tab = $0 }),
                tabs: tabs,
                tabForDisclosure: { LayoutDetailTab.tab(for: $0) }
            )
        }
        switch selected {
        case .groups:
            MenuBarLayoutGroupsSection()
        case .spacers:
            ThawSection("Spacers") {
                LayoutSpacersRows(spacerManager: appState.spacerManager, undoManager: appState.layoutUndo)
            }
            .settingsSearchAnchor("layout.spacers")
        case .appleItems:
            ControlCenterReplacementsSection(settings: settings)
        case .options:
            LayoutSectionOptions(settings: settings, isHidingUnavailable: isHidingUnavailable)
            HidingMethodSection(settings: settings)
            LayoutOverflowSection(settings: settings)
            if canArrangeLayout {
                LayoutResetControls(
                    itemManager: itemManager,
                    controlItemsDisabled: itemManager.areControlItemsMissing,
                    alwaysHiddenEnabled: settings.enableAlwaysHiddenSection
                )
            }
        }
    }
}
