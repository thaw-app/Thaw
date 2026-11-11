//
//  DrawnSeatCaptureReader.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import ThawAXCore
import ThawCapture

/// Reads like base, but checks one item against the seat MenuBarAgent draws it at.
///
/// A capture re-reads each item's frame after the screenshot and keeps a crop only when the
/// frame has not moved. An item cropped at its drawn seat (DrawnItemFrame.cropFrame) would fail
/// that against its Accessibility frame, so the re-read gives the item the crop frame worked
/// out from fresh reads of both: the crop is kept only when that seat has not moved either.
/// An owner-window crop is checked against the item's inventory frame instead, and an item
/// moved onto its drawn seat misses there.
nonisolated struct DrawnSeatCaptureReader: MenuBarCaptureReading {
    let base: any MenuBarCaptureReading
    /// The item as the bar reported it, with its Accessibility frame.
    let item: MenuBarItem
    let drawnBar: @Sendable () async -> [MenuBarAgentWindow.Entry]?

    func captureBand(displayID: CGDirectDisplayID) async -> (frame: CGRect, menuMaxX: CGFloat?) {
        await base.captureBand(displayID: displayID)
    }

    func displayBounds() -> [CGRect] {
        base.displayBounds()
    }

    func overflowBounds(displayID: CGDirectDisplayID) async -> [CGRect] {
        await base.overflowBounds(displayID: displayID)
    }

    func hostingCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        await base.hostingCapture(displayID: displayID)
    }

    func barWindowCapture(ownerPID: pid_t, displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        await base.barWindowCapture(ownerPID: ownerPID, displayID: displayID)
    }

    func displayStripCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        await base.displayStripCapture(displayID: displayID)
    }

    func menuBarItems(displayID: CGDirectDisplayID) async -> [MenuBarItem] {
        await base.menuBarItems(displayID: displayID)
    }

    func liveBounds(
        for candidates: [(item: MenuBarItem, bounds: CGRect)]
    ) async -> (bounds: [String: CGRect], ambiguous: Set<String>) {
        let identifier = item.uniqueIdentifier
        // The base read finds each item by its Accessibility frame.
        var live = await base.liveBounds(for: candidates.map { candidate in
            candidate.item.uniqueIdentifier == identifier ? (candidate.item, item.bounds) : candidate
        })
        guard let axFrame = live.bounds[identifier] else { return live }
        live.bounds[identifier] = await DrawnItemFrame.cropFrame(
            for: axFrame,
            ownerPID: item.ownerPID,
            sourcePID: item.sourcePID,
            in: drawnBar()
        )
        return live
    }
}
