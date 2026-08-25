//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @Environment(AppState.self) var appState: AppState
    let itemManager: MenuBarItemManager
    @Bindable var advancedSettings: AdvancedSettings

    @State private var maxSliderLabelWidth: CGFloat = 0
    @State private var isAdvancedExpanded = false

    var body: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermissions
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm {
                LayoutBarsSection(itemManager: itemManager)
                spacersCard
                MenuBarLayoutGroupsSection()
                layoutSectionsCard
                iconPreviewsCard
                advancedLayoutControlsCard
                LayoutResetControls(
                    itemManager: itemManager,
                    controlItemsDisabled: itemManager.areControlItemsMissing,
                    alwaysHiddenEnabled: appState.settings.advanced.enableAlwaysHiddenSection
                )
            }
            .onAppear {
                // Enable background cache prewarming while the layout settings
                // pane is open.
                appState.imageCache.markSettingsPaneOpened()
            }
            .onDisappear {
                // Disable background cache prewarming once the layout settings
                // pane is no longer visible, bounding how long perpetual
                // background captures (including the leaking SkyLight offscreen
                // path) can run (#759).
                appState.imageCache.markSettingsPaneClosed()
            }
        }
    }

    private var layoutSectionsCard: some View {
        IceSection("Sections") {
            Toggle(
                "Enable the always-hidden section",
                isOn: $advancedSettings.enableAlwaysHiddenSection
            )
            sectionDividerStyle
        }
    }

    private var iconPreviewsCard: some View {
        IceSection("Icon previews") {
            iconRefreshInterval
        }
    }

    private var spacersCard: some View {
        IceSection("Spacers") {
            ForEach(appState.spacerManager.spacers) { spacer in
                LabeledContent {
                    HStack(spacing: 12) {
                        ColorPicker(
                            "Spacer color",
                            selection: Binding(
                                get: { spacer.color.map { Color(cgColor: $0.cgColor) } ?? .clear },
                                set: { newColor in
                                    appState.spacerManager.setColor(NSColor(newColor).cgColor, for: spacer.id)
                                }
                            ),
                            supportsOpacity: true
                        )
                        .labelsHidden()
                        .help("Fill the spacer with a color. Fully transparent renders as an empty gap.")
                        IceSlider(
                            value: Binding(
                                get: { Double(spacer.width) },
                                set: { appState.spacerManager.setWidth(CGFloat($0), for: spacer.id) }
                            ),
                            in: Double(MenuBarSpacer.minWidth) ... Double(MenuBarSpacer.maxWidth),
                            step: 4
                        ) {
                            Text(verbatim: "\(Int(spacer.width)) pt")
                                .monospacedDigit()
                        }
                        Button {
                            appState.spacerManager.removeSpacer(id: spacer.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Remove this spacer")
                    }
                } label: {
                    Text("Spacer")
                }
            }

            Button("Add Spacer") {
                appState.spacerManager.addSpacer()
            }
            .annotation("Inserts an empty gap item into the menu bar. Position it like any other item — hold \u{2318} Command and drag it in the menu bar.")
        }
    }

    private var advancedLayoutControlsCard: some View {
        IceSection {
            DisclosureGroup("Advanced layout controls", isExpanded: $isAdvancedExpanded) {
                automaticArrangementEnabled
                enableMenuBarItemOverflow
                if advancedSettings.enableMenuBarItemOverflow {
                    useThawBarOnNotchOverflow
                }
            }
        }
        .onChange(of: appState.navigationState.requestedSettingsDisclosure, initial: true) { _, _ in
            if SettingsSearchNavigation.consumeDisclosure(
                .advancedLayoutControls,
                navigationState: appState.navigationState
            ) {
                isAdvancedExpanded = true
            }
        }
    }

    /// Both strings are reused verbatim from the existing catalog so this
    /// control ships fully translated: "Arrange menu bar items." and the
    /// ⌘ Command + drag line already carry all 19 localizations. The
    /// trailing period in the toggle label is the catalog's, not a slip —
    /// matching the existing key exactly is what avoids a new translation
    /// round.
    private var automaticArrangementEnabled: some View {
        Toggle(
            "Arrange menu bar items.",
            isOn: $advancedSettings.automaticArrangementEnabled
        )
        .annotation {
            Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                .padding(.trailing, 75)
        }
    }

    private var enableMenuBarItemOverflow: some View {
        Toggle(
            "Enable menu bar item overflow",
            isOn: $advancedSettings.enableMenuBarItemOverflow
        )
        .annotation {
            Text(
                """
                Move menu bar items from the visible section into the hidden \
                section when they don't fit beside the notch on a notched \
                display. Disable to keep the saved profile layout exactly as \
                authored even when items would otherwise be pushed under the \
                notch.
                """
            )
            .padding(.trailing, 75)
        }
    }

    private var useThawBarOnNotchOverflow: some View {
        Toggle(
            "Use the Thaw Bar while items are overflowed",
            isOn: $advancedSettings.useThawBarOnNotchOverflow
        )
        .annotation {
            Text(
                """
                Reveal hidden items through the Thaw Bar while overflow has items \
                ejected. The visible row has no room left beside the notch at that \
                point, so expanding the hidden section inline cannot show them. \
                Disable to always follow the per-display Thaw Bar setting.
                """
            )
            .padding(.trailing, 75)
        }
    }

    private var sectionDividerStyle: some View {
        IcePicker("Section divider style", selection: $advancedSettings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    private var iconRefreshInterval: some View {
        let maxFPS = MenuBarItemImageCache.maxIconRefreshRate
        let fpsBinding = Binding<Double>(
            get: {
                let interval = advancedSettings.iconRefreshInterval
                return interval > 0 ? 1.0 / interval : 0
            },
            set: { advancedSettings.iconRefreshInterval = $0 > 0 ? 1.0 / $0 : 0 }
        )
        return LabeledContent {
            IceSlider(
                value: fpsBinding,
                in: 0 ... maxFPS,
                step: 1
            ) {
                Text(fpsBinding.wrappedValue > 0
                    ? "\(Int(fpsBinding.wrappedValue)) fps"
                    : "Off")
            }
        } label: {
            Text("Icon refresh rate")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("How often animated icons refresh in the visible section, Hidden Thaw Bar, Search, and Layout. Always Hidden is capped at 1 fps. Higher values use more CPU.")
    }

    private var cannotArrange: some View {
        Text("\(Constants.displayName) cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var missingScreenRecordingPermissions: some View {
        VStack {
            Text("Menu bar layout requires screen recording permissions.")
                .font(.title2)

            Button {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            } label: {
                Text("Go to Advanced Settings")
            }
            .buttonStyle(.link)
        }
    }
}
