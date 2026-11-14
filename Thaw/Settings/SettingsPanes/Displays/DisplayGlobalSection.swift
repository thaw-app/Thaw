//
//  DisplayGlobalSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The Template tab of DisplaySettingsPane: the template new displays start
/// from (Thaw Bar settings and spacing), plus the Apply-to-All broadcast.
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

    /// The template's Thaw Bar settings. The shortcut placement is app-wide, so it stays on the Thaw Bar page.
    var templateThawBarControls: some View {
        ThawBarConfigurationControls(
            alwaysShowHiddenItems: displaySettings.binding(for: .template, \.alwaysShowHiddenItems) { $0.withAlwaysShowHiddenItems($1) },
            useThawBar: displaySettings.binding(for: .template, \.useThawBar) { $0.withUseThawBar($1) },
            location: displaySettings.binding(for: .template, \.thawBarLocation) { $0.withThawBarLocation($1) },
            layout: displaySettings.binding(for: .template, \.thawBarLayout) { $0.withThawBarLayout($1) },
            gridColumns: displaySettings.binding(for: .template, \.gridColumns) { $0.withGridColumns($1) },
            itemScale: displaySettings.binding(for: .template, \.thawBarItemScale) { $0.withThawBarItemScale($1) },
            useThawBarForAlwaysHidden: displaySettings.globalConfiguration.useThawBarForAlwaysHidden
                && appState.settings.layout.isAlwaysHiddenSectionEnabled,
            context: .globalTemplate
        )
    }

    /// The template's spacing and the Apply-to-All button. Edits stage on
    /// displaySettings.globalConfiguration; Apply broadcasts it.
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
        .annotation(applyAllAnnotation)
    }

    /// The full relaunch warning is on the Spacing tab; this only says when it applies.
    private var applyAllAnnotation: LocalizedStringResource {
        if displaySettings.spacingApplyMode == .writeOnly {
            "Replaces the settings of every display Thaw knows with this template. If the spacing in use changes, apps show it the next time they start."
        } else {
            "Replaces the settings of every display Thaw knows with this template. If the spacing in use changes, apps with menu bar items restart, as described under Spacing."
        }
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
            SpacingSlider(value: sliderBinding) { Text(labelKey) }
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

    private var globalSpacingAnnotation: LocalizedStringResource {
        "The spacing new displays start with. To use it on the displays you have, apply the template."
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

    /// Routes the Apply-to-All button through the confirmation alert. It always asks, even with spacing
    /// confirmations off, because it overwrites every display's own settings.
    private func requestGlobalApply() {
        let displayCount = displaySettings.displays.count
        let activeID = appState.profileManager.activeProfileID
        let activeName = activeID.flatMap { id in
            appState.profileManager.profiles.first(where: { $0.id == id })?.name
        }
        let pending = PendingGlobalApply(
            displayCount: displayCount,
            activeProfileID: activeID,
            activeProfileName: activeName
        )
        if let answer = confirmations.template {
            answerGlobalApply(pending, with: answer(pending))
        } else {
            pendingGlobalApply = pending
        }
    }

    /// Pushes the global template to every known display via the manager's
    /// broadcast helper. The Combine sink in DisplaySettingsManager picks
    /// the resulting configurations change up and drives the relaunch wave
    /// for the active display on the next main-queue dispatch.
    ///
    /// A save that fails rolls the live state back rather than leaving the
    /// broadcast applied without a matching profile entry, which the next
    /// reapply would revert.
    private func commitGlobalApply(saving save: () throws -> Void = { /* No profile to save to. */ }) {
        let previousConfigurations = displaySettings.configurations
        displaySettings.applyGlobalToAllKnownDisplays()
        do {
            try save()
        } catch {
            displaySettings.configurations = previousConfigurations
            errorMessage = error.localizedDescription
        }
    }

    /// What each button of the template alert does.
    func answerGlobalApply(_ pending: PendingGlobalApply, with choice: ConfirmationChoice) {
        switch choice {
        case .updateActiveProfile:
            commitGlobalApply {
                guard let id = pending.activeProfileID else { return }
                try appState.profileManager.updateProfile(
                    id: id,
                    scope: .configurationOnly,
                    appState: appState
                )
            }
        case .updateAllProfiles:
            commitGlobalApply {
                try appState.profileManager.updateAllProfilesGlobalConfiguration(
                    displaySettings.globalConfiguration,
                    propagateToDisplays: true
                )
            }
        case .apply:
            commitGlobalApply()
        case .cancel:
            // The dialog dismisses itself; cancelling needs no other work.
            break
        }
    }

    @ViewBuilder
    func globalConfirmationButtons(for pending: PendingGlobalApply) -> some View {
        if pending.activeProfileID != nil {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                answerGlobalApply(pending, with: .updateActiveProfile)
            }
            Button(String(localized: "Update All Profiles"), role: .destructive) {
                answerGlobalApply(pending, with: .updateAllProfiles)
            }
        } else {
            Button(String(localized: "Apply"), role: .destructive) {
                answerGlobalApply(pending, with: .apply)
            }
        }
        Button(String(localized: "Cancel"), role: .cancel) {
            answerGlobalApply(pending, with: .cancel)
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
