//
//  HoverPauseLatch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Decides when a press in the menu bar pauses show-on-hover and when the pause ends.
/// MenuBarManager.showOnHoverAllowed holds the state; these functions only decide.
enum HoverPauseLatch {
    /// A press in empty menu bar space pauses hover only while the Hidden section
    /// is revealed, because a hidden section has no reveal for hover to undo.
    static nonisolated func pausesOnEmptySpacePress(hiddenSectionIsRevealed: Bool) -> Bool {
        hiddenSectionIsRevealed
    }

    /// A pause ends once the pointer is outside the menu bar hover band, so the
    /// pointer's next return can reveal again. Zen Mode keeps hover paused until it ends.
    static nonisolated func releasesOnPointerMove(
        isPaused: Bool,
        pointerIsInsideHoverBand: Bool,
        isZenModeActive: Bool
    ) -> Bool {
        isPaused && !pointerIsInsideHoverBand && !isZenModeActive
    }
}
