//
//  DisplayGlobalSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The "Global" half of DisplaySettingsPane: a template of the same
/// controls every display has, plus the Apply-to-All broadcast.
///
/// Editing the template writes only displaySettings.globalConfiguration, so
/// the section binds directly without a draft dictionary. The exception is
/// spacing, whose slider label needs a draft: it borrows the per-display
/// draftSpacing dictionary under a sentinel key.
///
/// Apply-to-All overwrites every per-display entry, so it always confirms,
/// even with no profile active. canApplyGlobal disables the button when the
/// broadcast would change nothing.
///
/// The alert lives on DisplaySettingsPane.body, so globalSection,
/// globalConfirmationButtons and globalConfirmationMessage are internal.
extension DisplaySettingsPane {
    /// Sentinel key for the Global section's draft spacing slider, kept
    /// distinct from real display UUIDs so the Global section can share the
    /// per-display draftSpacing dictionary without colliding.
    private static let globalDraftKey = "__global__"

    /// A global-apply request awaiting user confirmation.
    struct PendingGlobalApply: Equatable {
        let displayCount: Int
        let activeProfileID: UUID?
        let activeProfileName: String?
    }

    /// Renders the spacing controls at the top of the Displays pane. Edits
    /// stage on displaySettings.globalConfiguration; Apply broadcasts it.
    @ViewBuilder
    func globalSection() -> some View {
        globalSpacingRow()

        // Copies the whole template over every display's own settings,
        // spacing included, which is why the broadcast always confirms.
        LabeledContent {
            Button("Apply template to all displays") {
                requestGlobalApply()
            }
            .buttonStyle(.settingsGlass)
            .disabled(!canApplyGlobal)
        } label: {
            Text("All displays")
        }
        .annotation(
            "Apply the global template above to every connected and previously-seen display.",
            more: "Newly connected displays are also seeded from this template."
        )
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
        case -16: "None"
        case 0: "Default"
        case 16: "Max"
        default: LocalizedStringKey(draft.formatted())
        }

        LabeledContent {
            ThawSlider(
                labelKey,
                value: sliderBinding,
                in: -16 ... 16,
                step: 2
            )
        } label: {
            Text("Menu bar item spacing")
        }
        .annotation(globalSpacingAnnotation)
        .onChange(of: savedOffset) { _, newValue in
            // Sync draft when the saved value changes externally
            // (profile load, reset).
            draftSpacing[Self.globalDraftKey] = CGFloat(newValue)
        }
    }

    private var globalSpacingAnnotation: LocalizedStringKey {
        if displaySettings.spacingApplyMode == .writeOnly {
            "Applying writes the new spacing without restarting apps; the new spacing appears the next time each menu bar app starts."
        } else {
            "Applying briefly relaunches apps with menu bar items so they pick up the new spacing."
        }
    }

    /// Returns true when the Apply-to-All button should be enabled. The
    /// button activates when at least one known display has a configuration
    /// that differs from the current global template; otherwise the
    /// broadcast would be a no-op.
    private var canApplyGlobal: Bool {
        let target = displaySettings.globalConfiguration
        let displays = displaySettings.displays
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
        let displayCount = displaySettings.displays.count
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
        let previousConfigurations = displaySettings.configurations
        commitGlobalApply()
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
                try appState.profileManager.updateAllProfilesGlobalConfiguration(
                    displaySettings.globalConfiguration,
                    propagateToDisplays: true
                )
            }
        } catch {
            displaySettings.configurations = previousConfigurations
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    func globalConfirmationButtons(for pending: PendingGlobalApply) -> some View {
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

    func globalConfirmationMessage(for pending: PendingGlobalApply) -> String {
        let profileName = pending.activeProfileName ?? ""
        let displayMessage = if displaySettings.spacingApplyMode == .writeOnly {
            String(localized: "This will overwrite the settings of ^[\(pending.displayCount) display](inflect: true) with the global template. If the active display’s spacing changes, the new spacing appears the next time each menu bar app starts, and apps are not restarted.")
        } else {
            String(localized: "This will overwrite the settings of ^[\(pending.displayCount) display](inflect: true) with the global template. If the active display’s spacing changes, Thaw will relaunch each app with a menu bar item. Relaunching apps may cause unsaved input, progress, or transient app state to be lost.")
        }
        if pending.activeProfileID != nil {
            let profileInstruction = String(localized: "Save the global template to the active profile “\(profileName)”, or save it to every profile.")
            return "\(displayMessage) \(profileInstruction)"
        } else {
            return displayMessage
        }
    }
}
