//
//  DisplaySettingsManager+SpacingDecisions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Kept out of the class body so they can be tested without AppState or real events.
extension DisplaySettingsManager {
    /// A resolution change, lid open/close or sleep that keeps the active display's UUID is no reason to
    /// re-apply spacing and risk a relaunch wave.
    static func shouldSkipSpacingApply(
        currentActiveDisplayUUID currentUUID: String?,
        lastAppliedActiveDisplayUUID lastUUID: String?
    ) -> Bool {
        currentUUID == lastUUID
    }

    /// The reason a display change applies spacing under, or nil when the display that owns the menu bar
    /// is the one spacing was last applied for.
    static func displayChangeSpacingReason(
        currentActiveDisplayUUID currentUUID: String?,
        lastAppliedActiveDisplayUUID lastUUID: String?
    ) -> String? {
        shouldSkipSpacingApply(currentActiveDisplayUUID: currentUUID, lastAppliedActiveDisplayUUID: lastUUID)
            ? nil
            : "screenParametersChanged"
    }

    /// Seeding a display Thaw has never seen happens on a display change, so it must not relaunch apps.
    static func configurationsChangeReason(seedingConnectedDisplays: Bool) -> String {
        seedingConnectedDisplays ? "displaySeeded" : "configurationsChanged"
    }

    /// Plugging or unplugging a display is not a spacing edit, so it only writes the value.
    static func spacingApplyRelaunchesApps(reason: String) -> Bool {
        reason != "screenParametersChanged" && reason != "displaySeeded"
    }

    /// Write-only mode relaunches nothing, so it never asks.
    static func needsSpacingRelaunchConfirmation(
        applyMode: SpacingApplyMode,
        confirmationsEnabled: Bool
    ) -> Bool {
        applyMode == .relaunchApps && confirmationsEnabled
    }
}
