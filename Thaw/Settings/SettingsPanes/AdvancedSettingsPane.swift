//
//  AdvancedSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct AdvancedSettingsPane: View {
    @Environment(AppState.self) var appState: AppState
    @Bindable var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    var body: some View {
        IceForm {
            CaptureInspectorSection()
            IceSection("Menu Bar Search") {
                moveCursorToRevealedItem
                surfaceItemsSeekingAttention
            }
            IceSection("Tooltips") {
                if appState.hasPermission(.screenRecording) {
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
                autoZenWhileSharingScreen
                enableSecondaryContextMenu
            }
            IceSection("Permissions") {
                allPermissions
            }
        }
        .onAppear {
            maxSliderLabelWidth = 0
        }
    }

    private var surfaceItemsSeekingAttention: some View {
        Toggle(
            "Surface hidden items that ask for attention",
            isOn: $settings.surfaceItemsSeekingAttention
        )
        .annotation(
            """
            When a hidden item starts blinking its icon, briefly show its \
            section so you see it. Thaw tells a blink apart from a clock or \
            a battery percentage by whether the icon keeps returning to a \
            state it already showed. It shows the section rather than moving \
            the item, and the usual rehide puts it back.
            """
        )
    }

    private var moveCursorToRevealedItem: some View {
        Toggle(
            "Move the pointer to revealed items",
            isOn: $settings.moveCursorToRevealedItem
        )
        .annotation(
            """
            When you open a menu bar item from the search panel, move the mouse \
            pointer next to it, so its menu appears under the pointer.
            """
        )
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
                version of \(Constants.displayName)'s menu, with Quit at the bottom. Disable this setting \
                if you encounter conflicts with other apps.
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

    private var autoZenWhileSharingScreen: some View {
        Toggle(
            "Enter zen mode while presenting",
            isOn: $settings.autoZenWhileSharingScreen
        )
        .annotation {
            Text(
                """
                Hide every concealable section for as long as a display is mirrored \
                or your screen is being shared, then put it back. macOS offers no way \
                to see that another app is recording the screen, so recordings are not \
                covered.
                """
            )
        }
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
                    .buttonStyle(.thawSecondary)
                }
            } label: {
                Text(permission.title)
            }
            .frame(height: 22)
        }
    }
}
