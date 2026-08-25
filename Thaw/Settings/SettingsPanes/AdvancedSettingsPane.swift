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
    @State private var currentLogFileName: String?
    @State private var isConfirmingReset = false

    var body: some View {
        IceForm {
            IceSection("Menu Bar Search") {
                searchSectionOrdering
                moveCursorToRevealedItem
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
                enableSecondaryContextMenu
                if settings.enableSecondaryContextMenu {
                    enableSecondaryContextMenuQuit
                }
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
        .onAppear {
            maxSliderLabelWidth = 0
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

            if settings.enableDiagnosticLogging {
                LabeledContent("Maximum log file size (MB)") {
                    numberField(
                        "Maximum log file size in megabytes",
                        value: $settings.diagnosticLogMaxSizeMB,
                        bounds: Self.logSizeBounds
                    )
                }
                .annotation("Start a new log file once the current one reaches this size.")

                LabeledContent("Keep logs for (days)") {
                    numberField(
                        "Days to keep log files",
                        value: $settings.diagnosticLogRetentionDays,
                        bounds: Self.logRetentionBounds
                    )
                }
                .annotation {
                    Text(
                        """
                        Delete older log files after this many days, or sooner if more than 50 pile up. \
                        The file being written is always kept.
                        """
                    )
                }

                IcePicker("Rotate by time", selection: $settings.diagnosticLogRotationInterval) {
                    ForEach(LogRotationInterval.allCases) { interval in
                        Text(interval.localized).tag(interval)
                    }
                }
                .annotation {
                    Text(
                        """
                        Also start a new log file once the current one has been open for an hour or a day. \
                        The size limit still applies.
                        """
                    )
                }
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

    /// A number the user can either type or step through.
    ///
    /// A value shown next to a stepper as plain text reads as something the app
    /// filled in and the user cannot change, and clicking to the far end of a
    /// range is slow. The field carries the value, the stepper nudges it, and
    /// both answer to the same hidden label so VoiceOver names them.
    private func numberField(
        _ label: LocalizedStringKey,
        value: Binding<Int>,
        bounds: NumberBounds
    ) -> some View {
        HStack(spacing: 6) {
            TextField(label, value: value, formatter: bounds.formatter)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()

            Stepper(label, value: value, in: bounds.range)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    /// A stepper's range together with the formatter that holds typed input
    /// inside it, so the two cannot drift apart.
    private struct NumberBounds {
        let range: ClosedRange<Int>
        let formatter: NumberFormatter

        init(_ range: ClosedRange<Int>) {
            self.range = range

            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            formatter.allowsFloats = false
            formatter.minimum = NSNumber(value: range.lowerBound)
            formatter.maximum = NSNumber(value: range.upperBound)
            self.formatter = formatter
        }
    }

    private static let logSizeBounds = NumberBounds(1 ... 100)
    private static let logRetentionBounds = NumberBounds(1 ... 30)

    private var displayedSearchSectionNames: [MenuBarSection.Name] {
        settings.searchSectionOrder.filter { name in
            name != .alwaysHidden || settings.enableAlwaysHiddenSection
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
