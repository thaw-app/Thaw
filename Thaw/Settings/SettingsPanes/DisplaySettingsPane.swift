//
//  DisplaySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct DisplaySettingsPane: View {
    /// Sentinel key for the Global section's draft spacing slider, kept
    /// distinct from real display UUIDs so the Global section can share the
    /// per-display draftSpacing dictionary without colliding.
    private static let globalDraftKey = "__global__"

    @EnvironmentObject var appState: AppState
    @ObservedObject var displaySettings: DisplaySettingsManager

    @State private var maxSliderLabelWidth: CGFloat = 0
    /// Per-display draft of the spacing slider, keyed by display UUID.
    /// Until the user clicks Apply, dragging the slider only updates this
    /// dictionary, it does not touch the saved configuration or trigger
    /// any relaunches.
    @State private var draftSpacing: [String: CGFloat] = [:]
    /// Pending spacing apply held while the confirmation alert is shown.
    /// Set by requestSpacingApply when a prompt is required; the alert binds
    /// to its non-nil state. Nil when no alert is showing.
    @State private var pendingSpacingApply: PendingSpacingApply?
    /// Pending global broadcast held while the global confirmation alert
    /// is shown. Set by requestGlobalApply; the alert binds to its
    /// non-nil state. Nil when no alert is showing.
    @State private var pendingGlobalApply: PendingGlobalApply?
    @State private var errorMessage: String?
    @State private var showingError = false

    /// A spacing apply request awaiting user confirmation.
    private struct PendingSpacingApply: Equatable {
        let displayID: String
        let displayName: String
        let offset: Double
        let isActiveDisplay: Bool
        let activeProfileID: UUID?
        let activeProfileName: String?
    }

    /// A global-apply request awaiting user confirmation.
    private struct PendingGlobalApply: Equatable {
        let displayCount: Int
        let activeProfileID: UUID?
        let activeProfileName: String?
    }

    var body: some View {
        IceForm {
            IceSection {
                globalSection()
            }
            ForEach(displaySettings.allDisplays()) { display in
                IceSection {
                    displayRow(for: display)
                }
            }
        }
        .alert(
            String(localized: "Apply spacing change?"),
            isPresented: Binding(
                get: { pendingSpacingApply != nil },
                set: { if !$0 { pendingSpacingApply = nil } }
            ),
            presenting: pendingSpacingApply,
            actions: { pending in spacingConfirmationButtons(for: pending) },
            message: { pending in Text(spacingConfirmationMessage(for: pending)) }
        )
        .alert(
            String(localized: "Apply global settings to all displays?"),
            isPresented: Binding(
                get: { pendingGlobalApply != nil },
                set: { if !$0 { pendingGlobalApply = nil } }
            ),
            presenting: pendingGlobalApply,
            actions: { pending in globalConfirmationButtons(for: pending) },
            message: { pending in Text(globalConfirmationMessage(for: pending)) }
        )
        .alert("Error", isPresented: $showingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    @ViewBuilder
    private func displayRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        let useIceBar = Binding<Bool>(
            get: { displaySettings.configuration(forUUID: display.id).useIceBar },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withUseIceBar(newValue)
                }
            }
        )

        let location = Binding<IceBarLocation>(
            get: { displaySettings.configuration(forUUID: display.id).iceBarLocation },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withIceBarLocation(newValue)
                }
            }
        )

        let alwaysShowHiddenItems = Binding<Bool>(
            get: { displaySettings.configuration(forUUID: display.id).alwaysShowHiddenItems },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withAlwaysShowHiddenItems(newValue)
                }
            }
        )

        let layout = Binding<IceBarLayout>(
            get: { displaySettings.configuration(forUUID: display.id).iceBarLayout },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withIceBarLayout(newValue)
                }
            }
        )

        let gridColumns = Binding<Int>(
            get: { displaySettings.configuration(forUUID: display.id).gridColumns },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withGridColumns(newValue)
                }
            }
        )

        HStack {
            Spacer()
            Text(display.name)
                .font(.headline)
            if display.hasNotch {
                Text("Notch")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            if !display.isConnected {
                Text("Disconnected")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }

        Toggle("Always show hidden items", isOn: alwaysShowHiddenItems)
            .disabled(useIceBar.wrappedValue)
            .annotation {
                if useIceBar.wrappedValue {
                    Text("Not available because the \(Constants.displayName) Bar is enabled for this display.")
                } else {
                    Text("Always show hidden menu bar items in the menu bar on this display.")
                }
            }

        Toggle("Use \(Constants.displayName) Bar", isOn: useIceBar)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar on this display.")

        if useIceBar.wrappedValue {
            IcePicker("Location", selection: location) {
                ForEach(IceBarLocation.allCases) { loc in
                    Text(loc.localized).tag(loc)
                }
            }
            .annotation {
                switch location.wrappedValue {
                case .dynamic:
                    Text("The \(Constants.displayName) Bar's location changes based on context.")
                case .mousePointer:
                    Text("The \(Constants.displayName) Bar is centered below the mouse pointer.")
                case .iceIcon:
                    Text("The \(Constants.displayName) Bar is centered below the \(Constants.displayName) icon.")
                case .leftAligned:
                    Text("The \(Constants.displayName) Bar is aligned to the left edge of the display.")
                case .rightAligned:
                    Text("The \(Constants.displayName) Bar is aligned to the right edge of the display.")
                }
            }

            IcePicker("Layout", selection: layout) {
                ForEach(IceBarLayout.allCases) { lay in
                    Text(lay.localized).tag(lay)
                }
            }
            .annotation {
                switch layout.wrappedValue {
                case .horizontal:
                    Text("Items are arranged in a single horizontal row.")
                case .vertical:
                    Text("Items are stacked vertically in a single column.")
                case .grid:
                    Text("Items are arranged in a grid with multiple columns.")
                }
            }

            if layout.wrappedValue == .grid {
                let gridColumnsDouble = Binding<Double>(
                    get: { Double(gridColumns.wrappedValue) },
                    set: { gridColumns.wrappedValue = Int($0) }
                )
                LabeledContent {
                    IceSlider(
                        value: gridColumnsDouble,
                        in: 2 ... 10,
                        step: 1
                    ) {
                        Text(verbatim: "\(gridColumns.wrappedValue)")
                    }
                } label: {
                    Text("Columns")
                        .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                        .onFrameChange { frame in
                            maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                        }
                }
                .annotation("Maximum number of items per row in the grid layout.")
            }
        }

        spacingRow(for: display)
    }

    @ViewBuilder
    private func spacingRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        let savedOffset = displaySettings.configuration(forUUID: display.id).itemSpacingOffset
        let draft = draftSpacing[display.id] ?? CGFloat(savedOffset)
        let canApply = draft != CGFloat(savedOffset)

        let sliderBinding = Binding<CGFloat>(
            get: { draftSpacing[display.id] ?? CGFloat(savedOffset) },
            set: { draftSpacing[display.id] = $0 }
        )

        let labelKey: LocalizedStringKey = switch draft {
        case -16: "none"
        case 0: "default"
        case 16: "max"
        default: LocalizedStringKey(draft.formatted())
        }

        LabeledContent {
            IceSlider(
                labelKey,
                value: sliderBinding,
                in: -16 ... 16,
                step: 2
            )
        } label: {
            LabeledContent {
                Button("Apply") {
                    requestSpacingApply(for: display, offset: Double(draft))
                }
                .help(Text("Apply the spacing for this display"))
                .disabled(!canApply)

                Button {
                    requestSpacingApply(for: display, offset: 0)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(Text("Reset to the default spacing"))
                .disabled(savedOffset == 0 && draft == 0)
            } label: {
                Text("Menu bar item spacing")
            }
        }
        .annotation(
            "Apply briefly relaunches apps with menu bar items so they pick up the new spacing. Setting takes effect when this display is the active menu bar display."
        )
        .onChange(of: savedOffset) { _, newValue in
            // Sync draft when the saved value changes externally
            // (profile load, URI scheme, etc.).
            draftSpacing[display.id] = CGFloat(newValue)
        }
    }

    // MARK: - Spacing Apply Confirmation

    /// Routes both the Apply button and the inline reset button through a
    /// single decision point. When no profile is active and the change is
    /// for a non-active display, applies immediately (matches prior
    /// behaviour). Otherwise stages a PendingSpacingApply so the .alert
    /// can ask the user to choose between updating the active profile,
    /// updating every profile, or cancelling.
    private func requestSpacingApply(
        for display: DisplaySettingsManager.DisplayInfo,
        offset: Double
    ) {
        let activeID = appState.profileManager.activeProfileID
        let isActiveDisplay = displaySettings.activeMenuBarDisplayUUID == display.id

        if activeID == nil, !isActiveDisplay {
            commitSpacing(displayID: display.id, offset: offset)
            return
        }

        let activeName = activeID.flatMap { id in
            appState.profileManager.profiles.first(where: { $0.id == id })?.name
        }
        pendingSpacingApply = PendingSpacingApply(
            displayID: display.id,
            displayName: display.name,
            offset: offset,
            isActiveDisplay: isActiveDisplay,
            activeProfileID: activeID,
            activeProfileName: activeName
        )
    }

    /// Writes the new spacing to displaySettings.configurations. The
    /// Combine sink in DisplaySettingsManager picks this up and drives the
    /// relaunch wave on the next main-queue dispatch, so the caller is
    /// expected to have already written the profile file when persisting
    /// to a profile is desired.
    private func commitSpacing(displayID: String, offset: Double) {
        draftSpacing[displayID] = CGFloat(offset)
        displaySettings.updateConfiguration(forDisplayUUID: displayID) { config in
            config.withItemSpacingOffset(offset)
        }
    }

    @ViewBuilder
    private func spacingConfirmationButtons(for pending: PendingSpacingApply) -> some View {
        if pending.activeProfileID != nil {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                if let id = pending.activeProfileID {
                    // updateProfile(scope:.configurationOnly) captures live
                    // state, so the in-memory configuration must hold the new
                    // value before the save. Snapshot the previous offset so
                    // a save failure can roll the live state back instead of
                    // leaving the new spacing applied without a matching
                    // profile entry, which the next reapply would revert.
                    let previousOffset = displaySettings
                        .configuration(forUUID: pending.displayID)
                        .itemSpacingOffset
                    commitSpacing(displayID: pending.displayID, offset: pending.offset)
                    do {
                        try appState.profileManager.updateProfile(
                            id: id,
                            scope: .configurationOnly,
                            appState: appState
                        )
                    } catch {
                        commitSpacing(displayID: pending.displayID, offset: previousOffset)
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                } else {
                    commitSpacing(displayID: pending.displayID, offset: pending.offset)
                }
            }
            Button(String(localized: "Update All Profiles"), role: .destructive) {
                let previousOffset = displaySettings
                    .configuration(forUUID: pending.displayID)
                    .itemSpacingOffset
                commitSpacing(displayID: pending.displayID, offset: pending.offset)
                do {
                    try appState.profileManager.updateAllProfilesItemSpacingOffset(
                        displayUUID: pending.displayID,
                        offset: pending.offset
                    )
                } catch {
                    commitSpacing(displayID: pending.displayID, offset: previousOffset)
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                draftSpacing[pending.displayID] = CGFloat(
                    displaySettings.configuration(forUUID: pending.displayID).itemSpacingOffset
                )
            }
        } else {
            Button(String(localized: "Apply"), role: .destructive) {
                commitSpacing(displayID: pending.displayID, offset: pending.offset)
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                draftSpacing[pending.displayID] = CGFloat(
                    displaySettings.configuration(forUUID: pending.displayID).itemSpacingOffset
                )
            }
        }
    }

    private func spacingConfirmationMessage(for pending: PendingSpacingApply) -> String {
        let profileName = pending.activeProfileName ?? ""
        switch (pending.isActiveDisplay, pending.activeProfileID != nil) {
        case (true, true):
            return String(
                format: String(localized: "Applying this spacing change will briefly relaunch all apps with menu bar items. Save the new spacing to the active profile \"%@\", or save it to every profile."),
                profileName
            )
        case (false, true):
            return String(
                format: String(localized: "Save the new spacing to the active profile \"%@\", or save it to every profile."),
                profileName
            )
        case (true, false):
            return String(localized: "Applying this spacing change will briefly relaunch all apps with menu bar items.")
        case (false, false):
            return ""
        }
    }

    // MARK: - Global Section

    /// Renders the Global controls at the top of the Displays pane. Edits
    /// here are staged on displaySettings.globalConfiguration only; the
    /// Apply button broadcasts the template to every known display via
    /// requestGlobalApply.
    @ViewBuilder
    private func globalSection() -> some View {
        let useIceBar = Binding<Bool>(
            get: { displaySettings.globalConfiguration.useIceBar },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withUseIceBar($0) }
        )
        let location = Binding<IceBarLocation>(
            get: { displaySettings.globalConfiguration.iceBarLocation },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withIceBarLocation($0) }
        )
        let alwaysShowHiddenItems = Binding<Bool>(
            get: { displaySettings.globalConfiguration.alwaysShowHiddenItems },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withAlwaysShowHiddenItems($0) }
        )
        let layout = Binding<IceBarLayout>(
            get: { displaySettings.globalConfiguration.iceBarLayout },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withIceBarLayout($0) }
        )
        let gridColumns = Binding<Int>(
            get: { displaySettings.globalConfiguration.gridColumns },
            set: { displaySettings.globalConfiguration = displaySettings.globalConfiguration.withGridColumns($0) }
        )

        HStack {
            Spacer()
            Text("Global")
                .font(.headline)
            Spacer()
        }

        Toggle("Always show hidden items", isOn: alwaysShowHiddenItems)
            .disabled(useIceBar.wrappedValue)
            .annotation {
                if useIceBar.wrappedValue {
                    Text("Not available because the \(Constants.displayName) Bar is enabled in the global template.")
                } else {
                    Text("Always show hidden menu bar items in the menu bar.")
                }
            }

        Toggle("Use \(Constants.displayName) Bar", isOn: useIceBar)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")

        if useIceBar.wrappedValue {
            IcePicker("Location", selection: location) {
                ForEach(IceBarLocation.allCases) { loc in
                    Text(loc.localized).tag(loc)
                }
            }
            .annotation {
                switch location.wrappedValue {
                case .dynamic:
                    Text("The \(Constants.displayName) Bar's location changes based on context.")
                case .mousePointer:
                    Text("The \(Constants.displayName) Bar is centered below the mouse pointer.")
                case .iceIcon:
                    Text("The \(Constants.displayName) Bar is centered below the \(Constants.displayName) icon.")
                case .leftAligned:
                    Text("The \(Constants.displayName) Bar is aligned to the left edge of the display.")
                case .rightAligned:
                    Text("The \(Constants.displayName) Bar is aligned to the right edge of the display.")
                }
            }

            IcePicker("Layout", selection: layout) {
                ForEach(IceBarLayout.allCases) { lay in
                    Text(lay.localized).tag(lay)
                }
            }
            .annotation {
                switch layout.wrappedValue {
                case .horizontal:
                    Text("Items are arranged in a single horizontal row.")
                case .vertical:
                    Text("Items are stacked vertically in a single column.")
                case .grid:
                    Text("Items are arranged in a grid with multiple columns.")
                }
            }

            if layout.wrappedValue == .grid {
                let gridColumnsDouble = Binding<Double>(
                    get: { Double(gridColumns.wrappedValue) },
                    set: { gridColumns.wrappedValue = Int($0) }
                )
                LabeledContent {
                    IceSlider(
                        value: gridColumnsDouble,
                        in: 2 ... 10,
                        step: 1
                    ) {
                        Text(verbatim: "\(gridColumns.wrappedValue)")
                    }
                } label: {
                    Text("Columns")
                        .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                        .onFrameChange { frame in
                            maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                        }
                }
                .annotation("Maximum number of items per row in the grid layout.")
            }
        }

        globalSpacingRow()

        LabeledContent {
            Button("Apply to All Displays") {
                requestGlobalApply()
            }
            .disabled(!canApplyGlobal)
        } label: {
            Text("Broadcast")
        }
        .annotation("Apply the global template above to every connected and previously-seen display. Newly connected displays are also seeded from this template.")
    }

    /// Spacing slider for the Global template. Uses a sentinel draft key so
    /// it can share the per-display draftSpacing dictionary.
    @ViewBuilder
    private func globalSpacingRow() -> some View {
        let savedOffset = displaySettings.globalConfiguration.itemSpacingOffset
        let draft = draftSpacing[Self.globalDraftKey] ?? CGFloat(savedOffset)

        let sliderBinding = Binding<CGFloat>(
            get: { draftSpacing[Self.globalDraftKey] ?? CGFloat(savedOffset) },
            set: { newValue in
                draftSpacing[Self.globalDraftKey] = newValue
                // Stage the draft into the global template immediately so
                // the Apply-to-All button broadcasts the spacing along with
                // the other controls. The relaunch wave only fires when
                // Apply-to-All writes to the per-display configurations,
                // so this assignment is cheap.
                displaySettings.globalConfiguration = displaySettings.globalConfiguration
                    .withItemSpacingOffset(Double(newValue))
            }
        )

        let labelKey: LocalizedStringKey = switch draft {
        case -16: "none"
        case 0: "default"
        case 16: "max"
        default: LocalizedStringKey(draft.formatted())
        }

        LabeledContent {
            IceSlider(
                labelKey,
                value: sliderBinding,
                in: -16 ... 16,
                step: 2
            )
        } label: {
            Text("Menu bar item spacing")
        }
        .annotation(
            "Applying briefly relaunches apps with menu bar items so they pick up the new spacing."
        )
        .onChange(of: savedOffset) { _, newValue in
            // Sync draft when the saved value changes externally
            // (profile load, reset).
            draftSpacing[Self.globalDraftKey] = CGFloat(newValue)
        }
    }

    /// Returns true when the Apply-to-All button should be enabled. The
    /// button activates when at least one known display has a configuration
    /// that differs from the current global template; otherwise the
    /// broadcast would be a no-op.
    private var canApplyGlobal: Bool {
        let target = displaySettings.globalConfiguration
        let displays = displaySettings.allDisplays()
        guard !displays.isEmpty else { return false }
        return displays.contains { display in
            displaySettings.configuration(forUUID: display.id) != target
        }
    }

    // MARK: - Global Apply Confirmation

    /// Routes the Apply-to-All button through the confirmation alert when a
    /// profile is active. When no profile is active, the broadcast still
    /// asks for confirmation because it overwrites every per-display entry,
    /// which is destructive.
    private func requestGlobalApply() {
        let displayCount = displaySettings.allDisplays().count
        let activeID = appState.profileManager.activeProfileID
        let activeName = activeID.flatMap { id in
            appState.profileManager.profiles.first(where: { $0.id == id })?.name
        }
        pendingGlobalApply = PendingGlobalApply(
            displayCount: displayCount,
            activeProfileID: activeID,
            activeProfileName: activeName
        )
    }

    /// Pushes the global template to every known display via the manager's
    /// broadcast helper. The Combine sink in DisplaySettingsManager picks
    /// the resulting configurations change up and drives the relaunch wave
    /// for the active display on the next main-queue dispatch.
    private func commitGlobalApply() {
        displaySettings.applyGlobalToAllKnownDisplays()
    }

    @ViewBuilder
    private func globalConfirmationButtons(for pending: PendingGlobalApply) -> some View {
        if pending.activeProfileID != nil {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                if let id = pending.activeProfileID {
                    // Snapshot the previous configurations so a save failure
                    // can roll the live state back rather than leaving the
                    // broadcast applied without a matching profile entry,
                    // which the next reapply would revert.
                    let previousConfigurations = displaySettings.configurations
                    commitGlobalApply()
                    do {
                        try appState.profileManager.updateProfile(
                            id: id,
                            scope: .configurationOnly,
                            appState: appState
                        )
                    } catch {
                        displaySettings.configurations = previousConfigurations
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                } else {
                    commitGlobalApply()
                }
            }
            Button(String(localized: "Update All Profiles"), role: .destructive) {
                let previousConfigurations = displaySettings.configurations
                commitGlobalApply()
                do {
                    try appState.profileManager.updateAllProfilesGlobalConfiguration(
                        displaySettings.globalConfiguration,
                        propagateToDisplays: true
                    )
                } catch {
                    displaySettings.configurations = previousConfigurations
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } else {
            Button(String(localized: "Apply"), role: .destructive) {
                commitGlobalApply()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    private func globalConfirmationMessage(for pending: PendingGlobalApply) -> String {
        let profileName = pending.activeProfileName ?? ""
        if pending.activeProfileID != nil {
            return String(
                format: String(localized: "This will overwrite the settings of %d display(s) with the global template and may briefly relaunch apps with menu bar items. Save the global template to the active profile \"%@\", or save it to every profile."),
                pending.displayCount,
                profileName
            )
        } else {
            return String(
                format: String(localized: "This will overwrite the settings of %d display(s) with the global template and may briefly relaunch apps with menu bar items."),
                pending.displayCount
            )
        }
    }
}
