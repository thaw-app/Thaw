//
//  ProfileRelaunchSafety.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Applying a profile may make spacing relaunches safer, never less safe.
/// Only the user, in Settings, can turn confirmation off or switch back to relaunching.
nonisolated enum ProfileRelaunchSafety {
    /// The two settings that decide whether a spacing change relaunches apps.
    struct Settings: Equatable {
        var confirmRelaunch: Bool
        var applyMode: SpacingApplyMode
    }

    /// A profile saved before the mode existed keeps the current mode.
    static func merged(
        current: Settings,
        profileConfirmRelaunch: Bool,
        profileApplyMode: SpacingApplyMode?
    ) -> Settings {
        let profileMode = profileApplyMode ?? current.applyMode
        let applyMode: SpacingApplyMode = current.applyMode == .writeOnly || profileMode == .writeOnly
            ? .writeOnly
            : .relaunchApps
        return Settings(
            confirmRelaunch: current.confirmRelaunch || profileConfirmRelaunch,
            applyMode: applyMode
        )
    }

    /// A profile apply restarts apps only when its caller asked to and the user needn't confirm, or already did.
    static func relaunchesApps(requested: Bool, settings: Settings, approved: Bool) -> Bool {
        requested && settings.applyMode == .relaunchApps && (!settings.confirmRelaunch || approved)
    }

    /// The settings that will be in effect once the profile is applied.
    @MainActor
    static func merged(_ profile: Profile, onto displaySettings: DisplaySettingsManager) -> Settings {
        merged(
            current: Settings(
                confirmRelaunch: displaySettings.confirmSpacingRelaunch,
                applyMode: displaySettings.spacingApplyMode
            ),
            profileConfirmRelaunch: profile.confirmSpacingRelaunch,
            profileApplyMode: profile.spacingApplyMode
        )
    }

    /// Whether applying the profile has to ask before its spacing change restarts apps.
    @MainActor
    static func needsConfirmation(for profile: Profile, displaySettings: DisplaySettingsManager) -> Bool {
        let settings = merged(profile, onto: displaySettings)
        return settings.applyMode == .relaunchApps && settings.confirmRelaunch
    }

    @MainActor
    @discardableResult
    static func apply(_ profile: Profile, to displaySettings: DisplaySettingsManager) -> Settings {
        let settings = merged(profile, onto: displaySettings)
        displaySettings.spacingApplyMode = settings.applyMode
        displaySettings.confirmSpacingRelaunch = settings.confirmRelaunch
        return settings
    }
}
