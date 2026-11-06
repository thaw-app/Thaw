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

    /// Writes the new spacing; DisplaySettingsManager starts the relaunch wave
    /// on the next main-queue turn.
    private func commitSpacing(displayID: String, offset: Double) {
        draftSpacing[displayID] = CGFloat(offset)
        displaySettings.updateConfiguration(forDisplayUUID: displayID) { config in
            config.withItemSpacingOffset(offset)
        }
    }

    /// Commits the spacing and, when a profile is active, persists it to the
    /// profile target chosen by unconfirmedSpacingProfileScope. Mirrors the
    /// alert's actions, rollback included.
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
        }
    }

    @ViewBuilder
    func spacingConfirmationButtons(for pending: PendingSpacingApply) -> some View {
        if pending.activeProfileID != nil {
            Button(String(localized: "Update Active Profile"), role: .destructive) {
                if let id = pending.activeProfileID {
                    // updateProfile captures live state, so commit first and
                    // roll back if the save fails.
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
