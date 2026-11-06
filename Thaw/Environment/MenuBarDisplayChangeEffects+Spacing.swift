//
//  MenuBarDisplayChangeEffects+Spacing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The display settings' part in a display change: recording the connected displays, then writing
/// the spacing of the display that owns the menu bar.
@MainActor
protocol DisplayChangeSpacing: AnyObject {
    /// Records the connected displays and seeds a new display's configuration from the global
    /// template, without relaunching apps.
    func seedConnectedDisplays()
    /// Writes the active display's spacing when the display that owns the menu bar changed, without
    /// relaunching apps.
    func applySpacingForDisplayChange()
}

extension DisplaySettingsManager: DisplayChangeSpacing {}

extension MenuBarDisplayChangeEffects {
    func seedDisplayConfigurations() {
        displaySettings.seedConnectedDisplays()
    }

    /// Runs at the settle, about 0.5 s after the last posting; the observer this replaced waited 1 s.
    func applyDisplaySpacing() {
        displaySettings.applySpacingForDisplayChange()
    }
}
