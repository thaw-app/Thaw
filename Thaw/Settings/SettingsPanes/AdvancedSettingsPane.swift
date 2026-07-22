//
//  AdvancedSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawCapture

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    var body: some View {
        IceForm {
            IceSection("Menu Bar Search") {
                searchSectionOrdering
            }
            IceSection("Tooltips") {
                if ScreenCapture.hasCachedScreenRecordingPermission {
                    showMenuBarTooltips
                    tooltipDelay
                } else {
                    Text("Screen recording permissions are required to display tooltips.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            IceSection("Menu bar behavior") {
                hideApplicationMenus
                enableSecondaryContextMenu
                if settings.enableSecondaryContextMenu {
                    enableSecondaryContextMenuQuit
                }
            }
            IceSection("Permissions") {
                allPermissions
            }
        }
        .onAppear {
            maxSliderLabelWidth = 0
        }
    }

    private var displayedSearchSectionNames: [MenuBarSection.Name] {
        settings.searchSectionOrder.filter { name in
            name != .alwaysHidden || settings.isAlwaysHiddenSectionEnabled
        }
    }

    private var searchSectionOrdering: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(displayedSearchSectionNames.enumerated()), id: \.element) { index, name in
                searchSectionRow(for: name)
                if index < displayedSearchSectionNames.count - 1 {
                    Divider()
                }
            }
        }
        .animation(.default, value: settings.searchSectionOrder)
        .animation(.default, value: settings.enableAlwaysHiddenSection)
        .annotation(
            "Choose which menu bar sections appear in the search panel, and in what order. Use the up and down buttons to reorder, and turn off a section to exclude its items from search results.",
            spacing: 10
        )
    }

    @ViewBuilder
    private func searchSectionRow(for name: MenuBarSection.Name) -> some View {
        let displayed = displayedSearchSectionNames
        let position = displayed.firstIndex(of: name) ?? 0
        let isFirst = position == 0
        let isLast = position == displayed.count - 1
        HStack(spacing: 8) {
            Text(name.localized)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                moveSearchSection(name, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .accessibilityLabel(String(localized: "Move up"))
            Button {
                moveSearchSection(name, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .accessibilityLabel(String(localized: "Move down"))
            Toggle(name.localized, isOn: searchInclusionBinding(for: name))
                .labelsHidden()
        }
    }

    private func searchInclusionBinding(for name: MenuBarSection.Name) -> Binding<Bool> {
        switch name {
        case .visible:
            return $settings.searchIncludeVisible
        case .hidden:
            return $settings.searchIncludeHidden
        case .alwaysHidden:
            return $settings.searchIncludeAlwaysHidden
        }
    }

    private func moveSearchSection(_ name: MenuBarSection.Name, by offset: Int) {
        // Swap by the user-visible neighbour so the move is predictable when
        // the always-hidden row is conditionally hidden from this list.
        let displayed = displayedSearchSectionNames
        guard let displayIndex = displayed.firstIndex(of: name) else {
            return
        }
        let displayTarget = displayIndex + offset
        guard displayed.indices.contains(displayTarget) else {
            return
        }
        let other = displayed[displayTarget]
        guard
            let index = settings.searchSectionOrder.firstIndex(of: name),
            let otherIndex = settings.searchSectionOrder.firstIndex(of: other)
        else {
            return
        }
        var order = settings.searchSectionOrder
        order.swapAt(index, otherIndex)
        settings.searchSectionOrder = order
    }

    private var hideApplicationMenus: some View {
        Toggle(
            "Hide app menus when showing menu bar items",
            isOn: $settings.hideApplicationMenus
        )
        .annotation {
            Text(
                """
                Make more room in the menu bar by hiding the current app menus if \
                needed. macOS requires \(Constants.displayName) to make itself visible in the Dock while \
                this setting is in effect.
                """
            )
            .padding(.trailing, 75)
        }
    }

    private var enableSecondaryContextMenu: some View {
        Toggle(
            "Enable secondary context menu",
            isOn: $settings.enableSecondaryContextMenu
        )
        .annotation {
            Text(
                """
                Right-click in an empty area of the menu bar to display a minimal \
                version of \(Constants.displayName)'s menu. Disable this setting if you encounter conflicts \
                with other apps.
                """
            )
            .padding(.trailing, 75)
        }
    }

    private var enableSecondaryContextMenuQuit: some View {
        Toggle(
            "Enable secondary context menu quit",
            isOn: $settings.enableSecondaryContextMenuQuit
        )
        .annotation {
            Text(
                """
                Add a Quit \(Constants.displayName) item to the bottom of the secondary context menu.
                """
            )
            .padding(.trailing, 75)
        }
    }

    private var tooltipDelay: some View {
        LabeledContent {
            IceSlider(
                value: $settings.tooltipDelay,
                in: 0 ... 1,
                step: 0.1
            ) {
                SecondsLabel(value: settings.tooltipDelay)
            }
        } label: {
            Text("Tooltip delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before showing a tooltip over a menu bar item.")
    }

    private var showMenuBarTooltips: some View {
        Toggle("Show tooltips in the menu bar", isOn: $settings.showMenuBarTooltips)
            .annotation("Show a tooltip when hovering over menu bar items in the actual menu bar.")
    }

    private var allPermissions: some View {
        ForEach(appState.permissions.allPermissions) { permission in
            LabeledContent {
                if permission.hasPermission {
                    Label {
                        Text("Permission Granted")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Grant Permission") {
                        permission.performRequest()
                    }
                }
            } label: {
                Text(permission.title)
            }
            .frame(height: 22)
        }
    }
}
