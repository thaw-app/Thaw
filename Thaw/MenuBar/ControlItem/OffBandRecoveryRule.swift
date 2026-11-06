//
//  OffBandRecoveryRule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// When a status window's frame means the item failed to land and the
/// off-band ladder should try to seat it again.
@MainActor
enum OffBandRecoveryRule {
    /// A degenerate frame calls for recovery, except on the Thaw icon the user
    /// turned off: that one is collapsed to no width on purpose, so a frame
    /// with no width is what it should measure.
    static func needsRecovery(
        _ frame: CGRect,
        isThawIcon: Bool,
        showsIcon: Bool,
        screenFrames: [CGRect] = NSScreen.screens.map(\.frame)
    ) -> Bool {
        let collapsedOnPurpose = isThawIcon && !showsIcon
        return !collapsedOnPurpose && ControlItem.isDegenerateMenuBarFrame(frame, screenFrames: screenFrames)
    }
}
