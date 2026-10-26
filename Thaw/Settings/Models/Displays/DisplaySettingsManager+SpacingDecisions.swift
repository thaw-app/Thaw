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

    /// The reason a profile a display change switched to applies its spacing under.
    static let displayProfileSwitchReason = "displayProfileSwitch"

    /// Seeding a new display and a display-driven profile switch both happen on a display change, so they only write.
    static func configurationsChangeReason(writeOnlyReason: String?) -> String {
        writeOnlyReason ?? "configurationsChanged"
    }

    /// Plugging or unplugging a display is not a spacing edit, so it only writes the value.
    static func spacingApplyRelaunchesApps(reason: String) -> Bool {
        !["screenParametersChanged", "displaySeeded", displayProfileSwitchReason].contains(reason)
    }

    /// Takes a profile's configurations; write-only when a display change switched to the profile.
    func assignConfigurations(_ newConfigurations: [String: DisplayThawBarConfiguration], writeOnly: Bool) {
        writeOnlyConfigurationsReason = writeOnly ? Self.displayProfileSwitchReason : nil
        defer { writeOnlyConfigurationsReason = nil }
        configurations = newConfigurations
    }

    /// Write-only mode relaunches nothing, so it never asks.
    static func needsSpacingRelaunchConfirmation(
        applyMode: SpacingApplyMode,
        confirmationsEnabled: Bool
    ) -> Bool {
        applyMode == .relaunchApps && confirmationsEnabled
    }
}
