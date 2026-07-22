//
//  WindowServerReading.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// The subset of WindowServer reads that ``MenuBarItemImageCache`` performs.
/// Exists so tests can substitute a fake and characterize the cache's
/// orchestration without a live WindowServer connection.
nonisolated protocol WindowServerReading: Sendable {
    func activeMenuBarDisplayID() -> CGDirectDisplayID?
    func windowBounds(for windowID: CGWindowID) -> CGRect?
}

/// Live WindowServer reads delegated through ``Bridging``.
nonisolated struct LiveWindowServerReader: WindowServerReading {
    func activeMenuBarDisplayID() -> CGDirectDisplayID? {
        Bridging.getActiveMenuBarDisplayID()
    }

    func windowBounds(for windowID: CGWindowID) -> CGRect? {
        Bridging.getWindowBounds(for: windowID)
    }
}
