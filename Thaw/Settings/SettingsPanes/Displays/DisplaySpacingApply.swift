//
//  DisplaySpacingApply.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The per-display spacing-apply flow: the decision of whether to prompt, the
/// commit paths, and the alert's buttons and message.
///
/// A slider drag writes nothing, since applying relaunches every app with a
/// menu bar item; the draft waits in draftSpacing until requestSpacingApply.
///
/// Every commit path rolls the offset back if the profile write throws, or
/// the next profile reapply would silently revert it.
extension DisplaySettingsPane {
    /// A spacing apply request awaiting user confirmation.
    struct PendingSpacingApply: Equatable {
        let displayID: String
        let displayName: String
        let offset: Double
        let isActiveDisplay: Bool
        let activeProfileID: UUID?
        let activeProfileName: String?
    }

    /// What the person picks in the spacing or the template confirmation.
    enum ConfirmationChoice {
        case updateActiveProfile
        case updateAllProfiles
        /// The way forward while no profile is active.
        case apply
        case cancel
    }

    /// Answers the page's confirmations in place of their alerts. Each is nil
    /// in the app, which shows the alert; tests answer here, so none is needed.
    struct Confirmations {
        var spacing: (@MainActor (PendingSpacingApply) -> ConfirmationChoice)?
        var template: (@MainActor (PendingGlobalApply) -> ConfirmationChoice)?
    }

    // MARK: - Spacing Apply Confirmation

    /// The one decision point for Apply and reset. Applies at once with no
    /// profile on a non-active display; otherwise stages the alert.
    func requestSpacingApply(
        for display: DisplaySettingsManager.DisplayInfo,
        offset: Double
    ) {
        let activeID = appState.profileManager.activeProfileID
        let isActiveDisplay = displaySettings.activeMenuBarDisplayUUID == display.id

        if activeID == nil, !isActiveDisplay {
            commitSpacing(displayID: display.id, offset: offset)
            return
        }

        // Confirmations off, or write-only mode with nothing to relaunch:
        // save to the profile target the user picked.
        if !displaySettings.confirmSpacingRelaunch || displaySettings.spacingApplyMode == .writeOnly {
            commitSpacing(
                displayID: display.id,
                offset: offset,
                savingTo: displaySettings.unconfirmedSpacingProfileScope,
                activeProfileID: activeID
            )
            return
        }

        let activeName = activeID.flatMap { id in
            appState.profileManager.profiles.first(where: { $0.id == id })?.name
        }
        let pending = PendingSpacingApply(
            displayID: display.id,
            displayName: display.name,
            offset: offset,
            isActiveDisplay: isActiveDisplay,
            activeProfileID: activeID,
            activeProfileName: activeName
        )
        if let answer = confirmations.spacing {
            answerSpacingApply(pending, with: answer(pending))
        } else {
            pendingSpacingApply = pending
        }
    }

    /// Writes the new spacing; DisplaySettingsManager starts the relaunch wave
    /// on the next main-queue turn.
    private func commitSpacing(displayID: String, offset: Double) {
        draftSpacing[displayID] = CGFloat(offset)
        displaySettings.updateConfiguration(forDisplayUUID: displayID) { config in
            config.withItemSpacingOffset(offset)
        }
    }

    /// Commits the spacing and, when a profile is active, saves it to the
    /// profiles the scope names. updateProfile captures live state, so the
    /// commit comes first and is rolled back if the save fails.
    private func commitSpacing(
        displayID: String,
        offset: Double,
        savingTo scope: SpacingProfileSaveScope,
        activeProfileID: UUID?
    ) {
        let previousOffset = displaySettings.configuration(forUUID: displayID).itemSpacingOffset
        commitSpacing(displayID: displayID, offset: offset)
        guard let id = activeProfileID else { return }
        do {
            switch scope {
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
        }
    }

    /// What each button of the spacing alert does.
    func answerSpacingApply(_ pending: PendingSpacingApply, with choice: ConfirmationChoice) {
        switch choice {
        case .updateActiveProfile:
            commitSpacing(
                displayID: pending.displayID,
                offset: pending.offset,
                savingTo: .activeProfile,
                activeProfileID: pending.activeProfileID
            )
        case .updateAllProfiles:
            commitSpacing(
                displayID: pending.displayID,
                offset: pending.offset,
                savingTo: .allProfiles,
                activeProfileID: pending.activeProfileID
            )
        case .apply:
            commitSpacing(displayID: pending.displayID, offset: pending.offset)
        case .cancel:
            draftSpacing[pending.displayID] = CGFloat(
                displaySettings.configuration(forUUID: pending.displayID).itemSpacingOffset
            )
        }
    }

    @ViewBuilder
    func spacingConfirmationButtons(for pending: PendingSpacingApply) -> some View {
        if pending.activeProfileID != nil {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                answerSpacingApply(pending, with: .updateActiveProfile)
            }
            Button(String(localized: "Update All Profiles"), role: .destructive) {
                answerSpacingApply(pending, with: .updateAllProfiles)
            }
        } else {
            Button(String(localized: "Apply"), role: .destructive) {
                answerSpacingApply(pending, with: .apply)
            }
        }
        Button(String(localized: "Cancel"), role: .cancel) {
            answerSpacingApply(pending, with: .cancel)
        }
    }

    /// Only the active display's spacing relaunches apps, so other displays get
    /// the profile choice alone.
    func spacingConfirmationMessage(for pending: PendingSpacingApply) -> String {
        let relaunchWarning = pending.isActiveDisplay
            ? String(localized: "This relaunches every app with a menu bar item, so unsaved work in those apps may be lost.")
            : nil
        let profileChoice = pending.activeProfileID.map { _ in
            String(
                format: String(localized: "Save the new spacing to the active profile “%@”, or to every profile."),
                pending.activeProfileName ?? ""
            )
        }
        return [relaunchWarning, profileChoice].compactMap(\.self).joined(separator: " ")
    }
}
