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

    @Environment(AppState.self) var appState: AppState
    @Bindable var displaySettings: DisplaySettingsManager

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
    @State private var selectedDisplayID: String?

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
            IceSection("Global") {
                globalSection()
            }
            IceSection {
                confirmSpacingRelaunchControls
            } footer: {
                SettingsWarningPill(
                    title: "Apps may relaunch",
                    message: "Changing menu bar spacing for a display can relaunch apps with menu bar items. Unsaved input, progress, or transient app state may be lost."
                )
            }
            if !displaySettings.allDisplays().isEmpty {
                IceSection {
                    Text("Per display")
                } content: {
                    perDisplayControls
                }
            }
        }
        .alert(
            String(localized: "Apply spacing change?"),
            isPresented: Binding(
                get: { pendingSpacingApply != nil },
                set: {
                    if !$0 {
                        pendingSpacingApply = nil
                    }
                }
            ),
            presenting: pendingSpacingApply,
            actions: { pending in spacingConfirmationButtons(for: pending) },
            message: { pending in Text(spacingConfirmationMessage(for: pending)) }
        )
        .alert(
            String(localized: "Apply global settings to all displays?"),
            isPresented: Binding(
                get: { pendingGlobalApply != nil },
                set: {
                    if !$0 {
                        pendingGlobalApply = nil
                    }
                }
            ),
            presenting: pendingGlobalApply,
            actions: { pending in globalConfirmationButtons(for: pending) },
            message: { pending in Text(globalConfirmationMessage(for: pending)) }
        )
        .alert("Error", isPresented: $showingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var confirmSpacingRelaunchControls: some View {
        Toggle("Confirm before relaunching apps", isOn: $displaySettings.confirmSpacingRelaunch)
            .annotation("Before a display change or spacing edit relaunches your menu bar apps, Thaw asks you to confirm. Turn this off to apply spacing changes and relaunch apps without confirmation.")

        if !displaySettings.confirmSpacingRelaunch {
            IcePicker(
                "Without confirmation, save spacing to",
                selection: $displaySettings.unconfirmedSpacingProfileScope
            ) {
                Text("Active profile").tag(SpacingProfileSaveScope.activeProfile)
                Text("All profiles").tag(SpacingProfileSaveScope.allProfiles)
            }
            .annotation("When a profile is active, choose whether spacing changes save to just the active profile or to every profile.")
        }
    }

    /// One controls block driven by a display picker, instead of repeating
    /// the identical block once per display (thaw-next's redesign).
    @ViewBuilder
    private var perDisplayControls: some View {
        let displays = displaySettings.allDisplays()
        let selected = displays.first { $0.id == selectedDisplayID } ?? displays[0]

        IcePicker(
            "Display",
            selection: Binding(
                get: { selected.id },
                set: { selectedDisplayID = $0 }
            )
        ) {
            ForEach(displays) { display in
                Text(display.name).tag(display.id)
            }
        }

        if selected.hasNotch || !selected.isConnected || hasCustomConfiguration(selected) {
            displayHeader(for: selected)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        displayRow(for: selected)
    }

    /// Whether the display has its own stored configuration, which takes
    /// precedence over the global template (#1045): without this marker the
    /// global toggles look broken, because editing the template does nothing
    /// for displays that have custom settings.
    private func hasCustomConfiguration(_ display: DisplaySettingsManager.DisplayInfo) -> Bool {
        displaySettings.configurationOverride(forUUID: display.id) != nil
    }

    private func displayHeader(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        HStack(spacing: 6) {
            Text(display.name)
            if hasCustomConfiguration(display) {
                Text("Custom")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.tint)
                    .help(Text(
                        "This display has its own settings, which take precedence over the global template above."
                    ))
            }
            if display.hasNotch {
                Text("Notch")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            if !display.isConnected {
                Text("Disconnected")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
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

        let useThawBarForAlwaysHidden = Binding<Bool>(
            get: { displaySettings.configuration(forUUID: display.id).useThawBarForAlwaysHidden },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withUseThawBarForAlwaysHidden(newValue)
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

        IceBarConfigurationControls(
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            useIceBar: useIceBar,
            useThawBarForAlwaysHidden: useThawBarForAlwaysHidden,
            location: location,
            layout: layout,
            gridColumns: gridColumns,
            context: .display
        )

        spacingRow(for: display)
    }

    @ViewBuilder
    private func spacingRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        let savedOffset = displaySettings.configuration(forUUID: display.id).itemSpacingOffset
        let draft = draftSpacing[display.id] ?? CGFloat(savedOffset)
        let canApply = draft != CGFloat(savedOffset)
        // macOS keeps one spacing for the whole system, and it follows the
        // display that hosts the menu bar: writing another display's value
        // would either do nothing or silently restyle every display (#961).
        let editsActiveDisplay = displaySettings.activeMenuBarDisplayUUID == display.id

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
            .disabled(!editsActiveDisplay)
        } label: {
            LabeledContent {
                Button("Apply") {
                    requestSpacingApply(for: display, offset: Double(draft))
                }
                .help(Text("Apply the spacing for this display"))
                .disabled(!canApply || !editsActiveDisplay)

                Button {
                    requestSpacingApply(for: display, offset: 0)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(Text("Reset to the default spacing"))
                .disabled(savedOffset == 0 && draft == 0)
                .disabled(!editsActiveDisplay)
            } label: {
                Text("Menu bar item spacing")
            }
        }
        .annotation {
            if editsActiveDisplay {
                Text(
                    "Apply briefly relaunches apps with menu bar items so they pick up the new spacing. macOS keeps one spacing for the whole system; it follows the display that hosts the menu bar."
                )
            } else {
                Text(
                    "macOS keeps one item spacing for the whole system, taken from the display that currently hosts the menu bar. This display's saved value applies while it hosts the menu bar; make it the active menu bar display to change it here."
                )
            }
        }
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

        // Confirmations disabled: apply directly, saving to the profile
        // target the user picked instead of staging the alert.
        if !displaySettings.confirmSpacingRelaunch {
            commitSpacingWithoutConfirmation(
                displayID: display.id,
                offset: offset,
                activeProfileID: activeID
            )
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

    /// Commits the spacing and, when a profile is active, persists it to the
    /// profile target chosen by unconfirmedSpacingProfileScope. Used when
    /// confirmations are disabled; mirrors the spacingConfirmationButtons
    /// actions including the rollback on a failed profile save.
    private func commitSpacingWithoutConfirmation(
        displayID: String,
        offset: Double,
        activeProfileID: UUID?
    ) {
        let previousOffset = displaySettings.configuration(forUUID: displayID).itemSpacingOffset
        commitSpacing(displayID: displayID, offset: offset)
        guard let id = activeProfileID else { return }
        do {
            switch displaySettings.unconfirmedSpacingProfileScope {
            case .activeProfile:
                try appState.profileManager.updateProfile(
                    id: id,
                    scope: .configurationOnly,
                    appState: appState
                )
            case .allProfiles:
                try appState.profileManager.updateAllProfilesItemSpacingOffset(
                    displayUUID: displayID,
                    offset: offset
                )
            }
        } catch {
            commitSpacing(displayID: displayID, offset: previousOffset)
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Revalidates a staged spacing request before acting on it. The alert is
    /// asynchronous: the menu bar can move to another display while it is
    /// open, and committing then would persist the old display's value while
    /// the manager applies spacing from the new host. The request is cancelled
    /// instead, and the slider snaps back to the saved value.
    private func revalidatePendingSpacing(_ pending: PendingSpacingApply) -> Bool {
        guard displaySettings.activeMenuBarDisplayUUID == pending.displayID else {
            draftSpacing[pending.displayID] = CGFloat(
                displaySettings.configuration(forUUID: pending.displayID).itemSpacingOffset
            )
            errorMessage = String(
                localized: "The menu bar moved to another display while the confirmation was open. The spacing change was cancelled."
            )
            showingError = true
            return false
        }
        return true
    }

    @ViewBuilder
    private func spacingConfirmationButtons(for pending: PendingSpacingApply) -> some View {
        if pending.activeProfileID != nil {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                guard revalidatePendingSpacing(pending) else { return }
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
                guard revalidatePendingSpacing(pending) else { return }
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
                guard revalidatePendingSpacing(pending) else { return }
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
                format: String(localized: "Applying this spacing change will relaunch each app with a menu bar item. Relaunching apps may cause unsaved input, progress, or transient app state to be lost. Save the new spacing to the active profile \"%@\", or save it to every profile."),
                profileName
            )
        case (false, true):
            return String(
                format: String(localized: "Save the new spacing to the active profile \"%@\", or save it to every profile."),
                profileName
            )
        case (true, false):
            return String(localized: "Applying this spacing change will relaunch each app with a menu bar item. Relaunching apps may cause unsaved input, progress, or transient app state to be lost.")
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
        let useThawBarForAlwaysHidden = Binding<Bool>(
            get: { displaySettings.globalConfiguration.useThawBarForAlwaysHidden },
            set: {
                displaySettings.globalConfiguration = displaySettings.globalConfiguration
                    .withUseThawBarForAlwaysHidden($0)
            }
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

        IceBarConfigurationControls(
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            useIceBar: useIceBar,
            useThawBarForAlwaysHidden: useThawBarForAlwaysHidden,
            location: location,
            layout: layout,
            gridColumns: gridColumns,
            context: .globalTemplate
        ) {
            Toggle(
                "Show at mouse pointer on hotkey",
                isOn: Binding(
                    get: { appState.settings.general.iceBarLocationOnHotkey },
                    set: { appState.settings.general.iceBarLocationOnHotkey = $0 }
                )
            )
            .annotation("Always show the \(Constants.displayName) Bar at the mouse pointer's location when it is shown using a hotkey.")
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

        // Confirmations disabled: broadcast directly, saving to the chosen
        // profile target instead of staging the alert.
        if !displaySettings.confirmSpacingRelaunch {
            commitGlobalApplyWithoutConfirmation(activeProfileID: activeID)
            return
        }

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

    /// Broadcasts the global template and, when a profile is active,
    /// persists it to the profile target chosen by
    /// unconfirmedSpacingProfileScope. Used when confirmations are disabled;
    /// mirrors the globalConfirmationButtons actions including rollback.
    private func commitGlobalApplyWithoutConfirmation(activeProfileID: UUID?) {
        guard let id = activeProfileID else {
            commitGlobalApply()
            return
        }
        switch displaySettings.unconfirmedSpacingProfileScope {
        case .activeProfile:
            updateActiveProfile(id: id)
        case .allProfiles:
            updateAllProfiles()
        }
    }

    /// Broadcasts the global template, then persists it to `id`'s profile.
    /// Snapshots the previous configurations first so a save failure can
    /// roll the live state back rather than leaving the broadcast applied
    /// without a matching profile entry, which the next reapply would revert.
    private func updateActiveProfile(id: UUID) {
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
    }

    /// Broadcasts the global template, then persists it to every profile.
    /// Mirrors ``updateActiveProfile(id:)``'s rollback-on-failure behavior.
    private func updateAllProfiles() {
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

    @ViewBuilder
    private func globalConfirmationButtons(for pending: PendingGlobalApply) -> some View {
        if let activeProfileID = pending.activeProfileID {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                updateActiveProfile(id: activeProfileID)
            }
            Button(String(localized: "Update All Profiles"), role: .destructive) {
                updateAllProfiles()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                // Intentionally empty: dismisses the alert, no other action needed.
            }
        } else {
            Button(String(localized: "Apply"), role: .destructive) {
                commitGlobalApply()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                // Intentionally empty: dismisses the alert, no other action needed.
            }
        }
    }

    private func globalConfirmationMessage(for pending: PendingGlobalApply) -> String {
        let profileName = pending.activeProfileName ?? ""
        let displayMessage = String(localized: "This will overwrite the settings of \(pending.displayCount) displays with the global template. If the active display's spacing changes, Thaw will relaunch each app with a menu bar item. Relaunching apps may cause unsaved input, progress, or transient app state to be lost.")
        if pending.activeProfileID != nil {
            let profileInstruction = String(localized: "Save the global template to the active profile \"\(profileName)\", or save it to every profile.")
            return "\(displayMessage) \(profileInstruction)"
        } else {
            return displayMessage
        }
    }
}

private struct IceBarConfigurationControls<ExtraControls: View>: View {
    enum Context {
        case display
        case globalTemplate
    }

    @Binding var alwaysShowHiddenItems: Bool
    @Binding var useIceBar: Bool
    @Binding var useThawBarForAlwaysHidden: Bool
    @Binding var location: IceBarLocation
    @Binding var layout: IceBarLayout
    @Binding var gridColumns: Int

    private let context: Context
    private let extraControls: () -> ExtraControls
    @State private var maxSliderLabelWidth: CGFloat = 0

    /// Whether anything opens in the Thaw Bar, and so whether its appearance
    /// controls apply.
    private var showsThawBar: Bool {
        useIceBar || useThawBarForAlwaysHidden
    }

    init(
        alwaysShowHiddenItems: Binding<Bool>,
        useIceBar: Binding<Bool>,
        useThawBarForAlwaysHidden: Binding<Bool>,
        location: Binding<IceBarLocation>,
        layout: Binding<IceBarLayout>,
        gridColumns: Binding<Int>,
        context: Context,
        @ViewBuilder extraControls: @escaping () -> ExtraControls
    ) {
        _alwaysShowHiddenItems = alwaysShowHiddenItems
        _useIceBar = useIceBar
        _useThawBarForAlwaysHidden = useThawBarForAlwaysHidden
        _location = location
        _layout = layout
        _gridColumns = gridColumns
        self.context = context
        self.extraControls = extraControls
    }

    var body: some View {
        Toggle("Always show hidden items", isOn: $alwaysShowHiddenItems)
            .disabled(useIceBar)
            .annotation {
                if useIceBar {
                    switch context {
                    case .display:
                        Text("Not available because the \(Constants.displayName) Bar is enabled for this display.")
                    case .globalTemplate:
                        Text("Not available because the \(Constants.displayName) Bar is enabled in the global template.")
                    }
                } else {
                    switch context {
                    case .display:
                        Text("Always show hidden menu bar items in the menu bar on this display.")
                    case .globalTemplate:
                        Text("Always show hidden menu bar items in the menu bar.")
                    }
                }
            }

        Toggle("Use \(Constants.displayName) Bar", isOn: $useIceBar)
            .annotation {
                switch context {
                case .display:
                    Text("Show hidden menu bar items in a separate bar below the menu bar.")
                case .globalTemplate:
                    Text("Show hidden menu bar items in a separate bar below the menu bar. This edits the global template, which displays with no custom settings follow; apply it with \"Apply to All Displays\" below, since displays with custom settings keep theirs until then.")
                }
            }

        Toggle("Always-hidden items only", isOn: $useThawBarForAlwaysHidden)
            .disabled(useIceBar)
            .annotation {
                if useIceBar {
                    Text("Not available because every section already opens in the \(Constants.displayName) Bar.")
                } else {
                    Text("""
                    Show always-hidden menu bar items in the \(Constants.displayName) Bar, \
                    while hidden items keep expanding in the menu bar.
                    """)
                }
            }

        extraControls()

        if showsThawBar {
            IcePicker("Location", selection: $location) {
                ForEach(IceBarLocation.allCases) { location in
                    Text(location.localized).tag(location)
                }
            }
            .annotation { locationAnnotation }

            IcePicker("Arrangement", selection: $layout) {
                ForEach(IceBarLayout.allCases) { layout in
                    Text(layout.localized).tag(layout)
                }
            }
            .annotation { layoutAnnotation }

            if layout == .grid {
                let gridColumnsDouble = Binding<Double>(
                    get: { Double(gridColumns) },
                    set: { gridColumns = Int($0) }
                )
                LabeledContent {
                    IceSlider(value: gridColumnsDouble, in: 2 ... 10, step: 1) {
                        Text(verbatim: "\(gridColumns)")
                    }
                } label: {
                    Text("Columns")
                        .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                        .onAppear {
                            // Clear any stale accumulated width before the
                            // label is (re)measured below.
                            maxSliderLabelWidth = 0
                        }
                        .onFrameChange { frame in
                            maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                        }
                }
                .annotation("Maximum number of items per row in the grid arrangement.")
            }
        }
    }

    @ViewBuilder
    private var locationAnnotation: some View {
        switch location {
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

    @ViewBuilder
    private var layoutAnnotation: some View {
        switch layout {
        case .horizontal:
            Text("Items are arranged in a single horizontal row.")
        case .vertical:
            Text("Items are stacked vertically in a single column.")
        case .grid:
            Text("Items are arranged in a grid with multiple columns.")
        }
    }
}

private extension IceBarConfigurationControls where ExtraControls == EmptyView {
    init(
        alwaysShowHiddenItems: Binding<Bool>,
        useIceBar: Binding<Bool>,
        useThawBarForAlwaysHidden: Binding<Bool>,
        location: Binding<IceBarLocation>,
        layout: Binding<IceBarLayout>,
        gridColumns: Binding<Int>,
        context: Context
    ) {
        self.init(
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            useIceBar: useIceBar,
            useThawBarForAlwaysHidden: useThawBarForAlwaysHidden,
            location: location,
            layout: layout,
            gridColumns: gridColumns,
            context: context
        ) {
            EmptyView()
        }
    }
}
