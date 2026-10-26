//
//  DisplaySettingsManager+SpacingDecisions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure decisions the manager's spacing paths take, kept out of the class body so they can be tested on their own.
extension DisplaySettingsManager {
    /// Whether a screen-parameters change should be ignored because the active
    /// menu bar display is unchanged. A resolution change, lid open/close or
    /// sleep transition that leaves the UUID the same is not a reason to
    /// re-apply spacing and risk a relaunch wave.
    ///
    /// Pure on its inputs so it can be tested without AppState or real events.
    static func shouldSkipSpacingApply(
        currentActiveDisplayUUID currentUUID: String?,
        lastAppliedActiveDisplayUUID lastUUID: String?
    ) -> Bool {
        currentUUID == lastUUID
    }

    /// The reason a configurations change applies spacing under. Seeding a display
    /// Thaw has never seen happens on a display change, so it must not relaunch apps.
    static func configurationsChangeReason(seedingConnectedDisplays: Bool) -> String {
        seedingConnectedDisplays ? "displaySeeded" : "configurationsChanged"
    }

    /// Plugging or unplugging a display is not a spacing edit, so it only writes the value.
    static func spacingApplyRelaunchesApps(reason: String) -> Bool {
        reason != "screenParametersChanged" && reason != "displaySeeded"
    }

    /// Whether to ask before a relaunch wave. Write-only mode relaunches
    /// nothing, so it never asks, whatever the confirmation toggle says.
    static func needsSpacingRelaunchConfirmation(
        applyMode: SpacingApplyMode,
        confirmationsEnabled: Bool
    ) -> Bool {
        applyMode == .relaunchApps && confirmationsEnabled
    }
}
