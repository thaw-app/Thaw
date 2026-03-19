//
//  AdvancedSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct SecondsLabel: View {
    let value: Double

    private var formatted: String {
        let localized = String(localized: "\(value) seconds")
        return localized
            .replacingOccurrences(of: #"(\d+)\.0+(\s)"#, with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d+)\,0+(\s)"#, with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d+[\.,]\d*?)0+(\s)"#, with: "$1$2", options: .regularExpression)
    }

    var body: Text {
        Text(formatted)
    }
}

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0
    @State private var currentLogFileName: String?
    @State private var isConfirmingReset = false

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    var body: some View {
        IceForm {
            IceSection("Menu Bar Sections") {
                enableAlwaysHiddenSection
                useOptionClickToShowAlwaysHiddenSection
                showAllSectionsOnUserDrag
                sectionDividerStyle
            }
            IceSection("Tooltips") {
                if ScreenCapture.cachedCheckPermissions() {
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
            IceSection("Other") {
                useLCSSortingOnNotchedDisplays
                hideApplicationMenus
                enableSecondaryContextMenu
                showIceBarAtMouseLocationOnHotkey
                showOnHoverDelay
                iconRefreshInterval
            }
            IceSection("Permissions") {
                allPermissions
            }
            IceSection("Diagnostics") {
                diagnosticLogging
            }
            IceSection("Reset") {
                resetSettings
            }
        }
    }

    private var resetSettings: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Reset all settings"))
                Text(String(localized: "Reset all settings to their default values. This action cannot be undone."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(String(localized: "Reset \(Constants.displayName)", comment: "A button that resets all settings to defaults")) {
                isConfirmingReset = true
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .alert(String(localized: "Reset all settings?"), isPresented: $isConfirmingReset) {
            Button(String(localized: "Reset"), role: .destructive) {
                appState.settings.resetAllSettingsToDefaults()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                isConfirmingReset = false
            }
        } message: {
            Text(String(localized: "This will reset all settings to their default values. This action cannot be undone."))
        }
    }

    private var enableAlwaysHiddenSection: some View {
        Toggle(
            "Enable the always-hidden section",
            isOn: $settings.enableAlwaysHiddenSection
        )
    }

    private var useOptionClickToShowAlwaysHiddenSection: some View {
        Toggle(
            "Use Option-click to open always hidden section",
            isOn: $settings.useOptionClickToShowAlwaysHiddenSection
        )
    }

    private var showAllSectionsOnUserDrag: some View {
        Toggle(
            "Show all sections when ⌘ Command + dragging menu bar items",
            isOn: $settings.showAllSectionsOnUserDrag
        )
    }

    private var sectionDividerStyle: some View {
        IcePicker("Section divider style", selection: $settings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    private var useLCSSortingOnNotchedDisplays: some View {
        Toggle(
            "Use LCS sorting on notched displays",
            isOn: $settings.useLCSSortingOnNotchedDisplays
        )
        .annotation {
            Text(
                """
                Use the faster LCS (Longest Common Subsequence) algorithm for \
                profile sorting on notched displays instead of the full sort. \
                LCS minimises the number of moves but may be less reliable on \
                notched displays with smaller resolutions.
                """
            )
            .padding(.trailing, 75)
        }
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

    private var showIceBarAtMouseLocationOnHotkey: some View {
        let binding = Binding<Bool>(
            get: { appState.settings.general.iceBarLocationOnHotkey },
            set: { appState.settings.general.iceBarLocationOnHotkey = $0 }
        )
        return Toggle(
            "Show at mouse pointer on hotkey",
            isOn: binding
        )
        .annotation("Always show the \(Constants.displayName) Bar at the mouse pointer's location when it is shown using a hotkey.")
    }

    private var showOnHoverDelay: some View {
        LabeledContent {
            IceSlider(
                value: $settings.showOnHoverDelay,
                in: 0 ... 1,
                step: 0.1
            ) {
                SecondsLabel(value: settings.showOnHoverDelay)
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

    private var iconRefreshInterval: some View {
        let fpsBinding = Binding<Double>(
            get: { (1.0 / settings.iconRefreshInterval).rounded() },
            set: { settings.iconRefreshInterval = 1.0 / $0 }
        )
        return LabeledContent {
            IceSlider(
                value: fpsBinding,
                in: 1 ... 30,
                step: 1
            ) {
                Text("\(Int(fpsBinding.wrappedValue)) fps")
            }
        } label: {
            Text("Icon refresh rate")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("How often animated menu bar icons are refreshed in panels. Higher values are smoother but use more CPU.")
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

    private var diagnosticLogging: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Enable diagnostic logging",
                isOn: $settings.enableDiagnosticLogging
            )
            .annotation {
                Text(
                    """
                    Writes detailed debug logs to a file for troubleshooting. \
                    Log files are saved to ~/Library/Logs/Thaw/. \
                    Disable when not needed to avoid unnecessary disk writes.
                    """
                )
                .padding(.trailing, 75)
            }

            HStack(spacing: 12) {
                if settings.enableDiagnosticLogging || DiagnosticLogger.shared.hasLogFiles {
                    Button("Show Log Files in Finder") {
                        let url = DiagnosticLogger.shared.logDirectory
                        NSWorkspace.shared.open(url)
                    }
                }

                if let currentLogFileName {
                    Text(currentLogFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: settings.enableDiagnosticLogging) {
                // Small yield to let the Combine sink create/close the log file first.
                try? await Task.sleep(for: .milliseconds(50))
                currentLogFileName = (
                    DiagnosticLogger.shared.currentLogFile
                        ?? DiagnosticLogger.shared.latestLogFile
                )?.lastPathComponent
            }
        }
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
