//
//  DisplaySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Keep shared state and alerts here: SwiftUI cannot present alert actions moved into nested View types.
/// Internal @State lets sibling-file extensions share it; callers use its defaults.
struct DisplaySettingsPane: View {
    @Environment(AppState.self) var appState
    @Bindable var displaySettings: DisplaySettingsManager

    /// Slider edits remain drafts until Apply, without saving configuration or relaunching apps.
    @State var draftSpacing: [String: CGFloat] = [:]
    /// Non-nil while a spacing apply awaits confirmation.
    @State var pendingSpacingApply: PendingSpacingApply?
    /// Non-nil while a global broadcast awaits confirmation.
    @State var pendingGlobalApply: PendingGlobalApply?
    @State var errorMessage: String?
    @State var selectedDisplayID: String?

    var body: some View {
        ThawForm {
            // didSet cannot throw; surface write failures so unsaved values do not silently vanish on relaunch.
            if let failure = displaySettings.lastPersistenceFailure {
                SettingsWarningPill(
                    title: "Display settings weren’t saved",
                    message: "\(failure) The settings below are in effect now, but they will be back to their last saved values after a restart.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }

            // The arrangement selects the display edited below.
            if selectedDisplay != nil {
                ThawSection {
                    displaySelector
                }
            }

            // Keep confirmation with spacing because it governs how those edits are committed.
            ThawSection("Menu bar item spacing") {
                globalSection()
                confirmSpacingRelaunchControls
            }

            if selectedDisplay != nil {
                ThawSection {
                    Text("Per display")
                } content: {
                    perDisplayControls
                }
            }
        }
        .alert(
            String(localized: "Apply spacing change?"),
            item: $pendingSpacingApply,
            actions: { pending in spacingConfirmationButtons(for: pending) },
            message: { pending in Text(spacingConfirmationMessage(for: pending)) }
        )
        .alert(
            String(localized: "Apply template to all displays?"),
            item: $pendingGlobalApply,
            actions: { pending in globalConfirmationButtons(for: pending) },
            message: { pending in Text(globalConfirmationMessage(for: pending)) }
        )
        .errorAlert("Couldn’t save display settings", message: $errorMessage)
    }

    @ViewBuilder
    private var confirmSpacingRelaunchControls: some View {
        ThawPicker(
            "When applying spacing",
            selection: $displaySettings.spacingApplyMode
        ) {
            Text("Apply spacing immediately (restarts menu bar apps)")
                .tag(SpacingApplyMode.relaunchApps)
            Text("Wait until next restart (no apps restarted)")
                .tag(SpacingApplyMode.writeOnly)
        }
        .annotation(
            "macOS only reads menu bar spacing when a status item’s owner starts.",
            more: "Restarting apps applies the change now; waiting leaves every app running and the new spacing appears the next time each app starts (after a restart, or when you reopen it)."
        )

        // Write-only mode relaunches nothing, so there is nothing to confirm.
        if displaySettings.spacingApplyMode == .relaunchApps {
            Toggle("Confirm before relaunching apps", isOn: $displaySettings.confirmSpacingRelaunch)
                .annotation(
                    "Before a display change or spacing edit relaunches your menu bar apps, \(Constants.displayName) asks you to confirm.",
                    more: "Turn this off to apply spacing changes and relaunch apps without confirmation."
                )

            if !displaySettings.confirmSpacingRelaunch {
                ThawPicker(
                    "Without confirmation, save spacing to",
                    selection: $displaySettings.unconfirmedSpacingProfileScope
                ) {
                    Text("Active profile").tag(SpacingProfileSaveScope.activeProfile)
                    Text("All profiles").tag(SpacingProfileSaveScope.allProfiles)
                }
                .annotation("When a profile is active, choose whether spacing changes save to the active profile or to every profile.")
            }
        }
    }
}
