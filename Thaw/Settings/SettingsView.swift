//
//  SettingsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - Preference Key for Measuring Sidebar Item Widths

private struct SidebarItemWidthPreferenceKey: PreferenceKey {
    static let defaultValue: [SettingsNavigationIdentifier: CGFloat] = [:]

    static func reduce(
        value: inout [SettingsNavigationIdentifier: CGFloat],
        nextValue: () -> [SettingsNavigationIdentifier: CGFloat]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    let appState: AppState
    @ObservedObject var navigationState: AppNavigationState
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.sidebarRowSize) private var sidebarRowSize

    private let sidebarPadding: CGFloat = 3
    private let sidebarItemCornerRadius: CGFloat = 12

    /// State to store measured text widths from sidebar items
    @State private var measuredTextWidths: [SettingsNavigationIdentifier: CGFloat] = [:]

    /// Minimum sidebar width based on row size
    private var minSidebarWidth: CGFloat {
        switch sidebarRowSize {
        case .small: 200
        case .medium: 220
        case .large: 240
        @unknown default: 220
        }
    }

    /// Space for icon including padding and Label internal spacing
    /// Icon sizes naturally to sidebarItemHeight, so we use that as basis
    private var iconSpace: CGFloat {
        sidebarItemHeight + 8
    }

    /// List margins (leading/trailing padding in sidebar)
    private var listMargins: CGFloat {
        32
    }

    /// Dynamic sidebar width calculated from measured content
    private var dynamicSidebarWidth: CGFloat {
        let maxTextWidth = measuredTextWidths.values.max() ?? 0
        // 8 = horizontal padding on label (4pt × 2 sides)
        let calculatedWidth = maxTextWidth + iconSpace + listMargins + 8
        return max(calculatedWidth, minSidebarWidth)
    }

    private var sidebarItemHeight: CGFloat {
        switch sidebarRowSize {
        case .small: 26
        case .medium: 32
        case .large: 34
        @unknown default: 32
        }
    }

    private var sidebarFontSize: CGFloat {
        switch sidebarRowSize {
        case .small: 13
        case .medium: 15
        case .large: 16
        @unknown default: 15
        }
    }

    private var sidebarTextStyle: some ShapeStyle {
        appearsActive ? .primary : .secondary
    }

    private var navigationTitle: LocalizedStringKey {
        navigationState.settingsNavigationIdentifier.localized
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle(navigationTitle)
    }

    private var sidebar: some View {
        List {
            Section {
                ForEach(SettingsNavigationIdentifier.allCases) { identifier in
                    sidebarButton(for: identifier)
                }
            } header: {
                Text("\(Constants.displayName)")
                    .font(.system(size: sidebarFontSize * 2.67, weight: .medium))
                    .foregroundStyle(sidebarTextStyle)
                    .padding(.leading, sidebarPadding)
                    .padding(.bottom, sidebarFontSize)
            }
            .collapsible(false)
        }
        .scrollDisabled(true)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            sidebarToolbarSpacer
        }
        .navigationSplitViewColumnWidth(
            min: minSidebarWidth,
            ideal: dynamicSidebarWidth,
            max: dynamicSidebarWidth * 1.5
        )
        .onPreferenceChange(SidebarItemWidthPreferenceKey.self) { widths in
            measuredTextWidths = widths
        }
    }

    private func sidebarButton(for identifier: SettingsNavigationIdentifier) -> some View {
        let isSelected = navigationState.settingsNavigationIdentifier == identifier

        return Button {
            if !isSelected {
                navigationState.settingsNavigationIdentifier = identifier
            }
        } label: {
            sidebarItemLabel(for: identifier, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private func sidebarItemLabel(
        for identifier: SettingsNavigationIdentifier,
        isSelected: Bool
    ) -> some View {
        Label {
            Text(identifier.localized)
                .font(.system(size: sidebarFontSize))
                .foregroundStyle(sidebarTextStyle)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: SidebarItemWidthPreferenceKey.self,
                                value: [identifier: geometry.size.width]
                            )
                    }
                )
        } icon: {
            identifier.iconResource.view
                .foregroundStyle(sidebarTextStyle)
                .padding(sidebarPadding)
        }
        .foregroundStyle(sidebarItemForegroundStyle(isSelected: isSelected))
        .frame(maxWidth: .infinity, minHeight: sidebarItemHeight, alignment: .leading)
        .padding(.horizontal, 10)
        .background(sidebarItemBackground(isSelected: isSelected))
        .clipShape(RoundedRectangle(cornerRadius: sidebarItemCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: sidebarItemCornerRadius, style: .continuous))
    }

    private func sidebarItemForegroundStyle(isSelected: Bool) -> some ShapeStyle {
        if isSelected && appearsActive {
            return AnyShapeStyle(.white)
        }
        return AnyShapeStyle(sidebarTextStyle)
    }

    @ViewBuilder
    private func sidebarItemBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: sidebarItemCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: appearsActive
                            ? [Color.accentColor.opacity(0.96), Color.accentColor]
                            : [Color.secondary.opacity(0.35), Color.secondary.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            Color.clear
        }
    }

    @ToolbarContentBuilder
    private var sidebarToolbarSpacer: some ToolbarContent {
        ToolbarSpacer(.flexible)
    }

    private var detailView: some View {
        settingsPane
            .id(navigationState.settingsNavigationIdentifier)
            .scrollEdgeEffectStyle(.hard, for: .top)
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane(settings: appState.settings.general)
        case .displays:
            DisplaySettingsPane(displaySettings: appState.settings.displaySettings)
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .profiles:
            ProfileSettingsPane(profileManager: appState.profileManager)
        case .advanced:
            AdvancedSettingsPane(settings: appState.settings.advanced)
        case .automation:
            AutomationSettingsPane()
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }
}
