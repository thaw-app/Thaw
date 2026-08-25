//
//  GeneralSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppState.self) var appState: AppState
    @Bindable var settings: GeneralSettings
    @Bindable var advancedSettings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var rehideIntervalKey: LocalizedStringKey {
        let number = settings.rehideInterval.formatted(.number.precision(.fractionLength(0 ... 1)))
        return LocalizedStringKey(String(localized: "\(number) seconds"))
    }

    var body: some View {
        IceForm {
            IceSection {
                appOptions
            }
            IceSection("\(Constants.displayName) icon") {
                iceIconOptions
            }
            IceSection("Empty menu bar area") {
                emptyAreaOptions
            }
            IceSection("While rearranging") {
                showAllSectionsOnUserDrag
            }
            IceSection("After revealing") {
                rehideOptions
            }
        }
        .onAppear {
            maxSliderLabelWidth = 0
        }
    }

    // MARK: App Options

    @ViewBuilder
    private var appOptions: some View {
        LaunchAtLogin.Toggle {
            Text("Launch at Login")
        }
        Toggle("Simple Mode", isOn: $settings.simpleMode)
            .annotation("Shows only the essential settings. All features keep working and keep their configuration.")
        Toggle("Show setting descriptions", isOn: $settings.showSettingDescriptions)
            .annotation("Explains what a setting does directly beneath it, like this text.")
    }

    // MARK: Ice Icon Options

    @ViewBuilder
    private var iceIconOptions: some View {
        showIceIcon
        if settings.showIceIcon {
            iceIconPicker
        }
        alwaysHiddenIconGestures
    }

    private var showIceIcon: some View {
        Toggle("Show \(Constants.displayName) icon", isOn: $settings.showIceIcon)
            .annotation("Show the \(Constants.displayName) icon in the menu bar. Click to show hidden items, double-click for always-hidden, and right-click for settings.")
    }

    private var iceIconPicker: some View {
        IceIconPicker(settings: settings)
    }

    @ViewBuilder
    private var alwaysHiddenIconGestures: some View {
        if advancedSettings.enableAlwaysHiddenSection {
            Toggle(
                "Use Option-click to open always-hidden section",
                isOn: $advancedSettings.useOptionClickToShowAlwaysHiddenSection
            )
            if settings.showIceIcon {
                Toggle(
                    "Double-click \(Constants.displayName) icon to open always-hidden section",
                    isOn: $advancedSettings.useDoubleClickToShowAlwaysHiddenSection
                )
            }
        } else {
            Text("Enable the always-hidden section in Layout to configure icon gestures for that section.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Empty Menu Bar Area

    @ViewBuilder
    private var emptyAreaOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show on click", isOn: $settings.showOnClick)
                .annotation("Click an empty area of the menu bar to show hidden menu bar items.")

            if settings.showOnClick, advancedSettings.enableAlwaysHiddenSection {
                Toggle("Double-click for always-hidden", isOn: $settings.showOnDoubleClick)
                    .annotation("Double-click an empty area of the menu bar to show always-hidden menu bar items.")
            }
        }
        Toggle("Show on hover", isOn: $settings.showOnHover)
            .annotation("Hover over an empty area of the menu bar to show hidden menu bar items.")
        if settings.showOnHover {
            showOnHoverDelay
        }
        Toggle("Show on scroll", isOn: $settings.showOnScroll)
            .annotation("Scroll or swipe in the menu bar to show hidden menu bar items.")
    }

    private var showOnHoverDelay: some View {
        LabeledContent {
            IceSlider(
                value: $advancedSettings.showOnHoverDelay,
                in: 0 ... 1,
                step: 0.1
            ) {
                SecondsLabel(value: advancedSettings.showOnHoverDelay)
            }
        } label: {
            Text("Show on hover delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before showing on hover.")
    }

    // MARK: While Rearranging

    private var showAllSectionsOnUserDrag: some View {
        Toggle(
            "Show all sections when ⌘ Command + dragging menu bar items",
            isOn: $advancedSettings.showAllSectionsOnUserDrag
        )
    }

    // MARK: After Revealing

    @ViewBuilder
    private var rehideOptions: some View {
        Toggle("Automatically rehide", isOn: $settings.autoRehide)
        if settings.autoRehide {
            rehideStrategyPicker
        }
    }

    private var rehideStrategyPicker: some View {
        VStack {
            IcePicker("Strategy", selection: $settings.rehideStrategy) {
                ForEach(RehideStrategy.allCases) { strategy in
                    Text(strategy.localized).tag(strategy)
                }
            }
            .annotation {
                switch settings.rehideStrategy {
                case .smart:
                    Text("Menu bar items are rehidden using a smart algorithm.")
                case .timed:
                    Text("Menu bar items are rehidden after a fixed amount of time.")
                case .focusedApp:
                    Text("Menu bar items are rehidden when the focused app changes.")
                }
            }

            if case .timed = settings.rehideStrategy {
                IceSlider(
                    rehideIntervalKey,
                    value: $settings.rehideInterval,
                    in: 0 ... 30,
                    step: 1
                )
            }
        }
    }
}
