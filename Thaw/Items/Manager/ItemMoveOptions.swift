//
//  ItemMoveOptions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// How MenuBarItemManager.move(item:to:on:options:) may carry out one move.
///
/// The defaults describe an automatic move: it waits for the user to stop
/// typing or pointing, and refuses unusual sources and targets.
nonisolated struct ItemMoveOptions {
    /// Skips waiting for the user to pause input, for callers that already did.
    var skipInputPause = false
    /// Allows a control item as the destination, for deliberate section transitions.
    var allowSectionBoundaryTarget = false
    /// Allows moving an item parked outside the menu bar band.
    var allowParkedOffMenuBarSource = false
    /// Alternates captured beside the anchor at planning time, tried in order if it vanished.
    var anchorFallbacks: [MoveDestination] = []
    /// Marks the user's own action, which preempts background passes.
    var isUserInitiated = false
    /// Skips the after-move position check, which a recovery move cannot pass.
    var recoveringUnplacedItem = false
}
