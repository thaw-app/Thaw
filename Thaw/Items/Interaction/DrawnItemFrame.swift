//
//  DrawnItemFrame.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import ThawAXCore

/// Where MenuBarAgent actually draws an item, read from its own window.
///
/// On macOS 27 the Accessibility frame of a hidden item opened from the Thaw Bar can be a
/// phantom: a seat another item is drawn in. A real click aimed there opens the neighbour, and
/// a crop there shows a sliver of the item. MenuBarAgent's window has one child per drawn item,
/// owned by the item's app, so for an app with one item drawn it says where that item really is.
/// Its frames span the bar's full height and leave out the padding the Accessibility frame
/// includes, so only their x and width are used.
nonisolated enum DrawnItemFrame {
    /// How far apart, in points, the centres of an item's drawn and Accessibility frames may be
    /// and still describe the same seat.
    static let agreementTolerance: CGFloat = 4

    /// The frame the item is drawn at: x and width from its drawn entry, y and height from
    /// axFrame. Nil unless the read is settled and exactly one entry belongs to the item's app:
    /// its source process for an item MenuBarAgent hosts, whose own entries are other items.
    static func drawnFrame(
        for axFrame: CGRect,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        in entries: [MenuBarAgentWindow.Entry]?
    ) -> CGRect? {
        guard let entries = entries.flatMap(MenuBarAgentWindow.settled),
              let app = processes(ownerPID: ownerPID, sourcePID: sourcePID).first
        else { return nil }
        let own = entries.filter { $0.ownerPID == app }
        guard own.count == 1, let drawn = own.first else { return nil }
        return CGRect(x: drawn.frame.minX, y: axFrame.minY, width: drawn.frame.width, height: axFrame.height)
    }

    /// Whether axFrame sits on an item another app has drawn: a shared left edge or a large
    /// overlap, as MenuBarItem.hasPhantomFrame(among:) decides between items.
    static func isPhantom(
        _ axFrame: CGRect,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        in entries: [MenuBarAgentWindow.Entry]?
    ) -> Bool {
        guard axFrame.width > 0, let entries = entries.flatMap(MenuBarAgentWindow.settled) else { return false }
        let own = Set(processes(ownerPID: ownerPID, sourcePID: sourcePID))
        return entries.contains { entry in
            guard !own.contains(entry.ownerPID),
                  entry.frame.width >= MenuBarItemGeometry.phantomFramePeerMinimumWidth
            else { return false }
            if abs(entry.frame.minX - axFrame.minX) < MenuBarItemGeometry.phantomFrameXTolerance {
                return true
            }
            let overlap = min(axFrame.maxX, entry.frame.maxX) - max(axFrame.minX, entry.frame.minX)
            return overlap >= MenuBarItemGeometry.phantomFrameMinimumOverlap
                && overlap > min(axFrame.width, entry.frame.width) * MenuBarItemGeometry.phantomFrameOverlapFraction
        }
    }

    /// Where a real click on the item should land: its drawn frame, else axFrame unless that is
    /// a phantom, in which case nil and nothing should be clicked.
    static func clickFrame(
        for axFrame: CGRect,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        in entries: [MenuBarAgentWindow.Entry]?
    ) -> CGRect? {
        if let drawn = drawnFrame(for: axFrame, ownerPID: ownerPID, sourcePID: sourcePID, in: entries) {
            return drawn
        }
        return isPhantom(axFrame, ownerPID: ownerPID, sourcePID: sourcePID, in: entries) ? nil : axFrame
    }

    /// Whether a crop at axFrame shows the item: its drawn frame, when there is one, is on the
    /// same seat, and otherwise axFrame is no phantom. A crop can only be cut at the
    /// Accessibility frame, which the capture checks against a fresh read.
    static func canCrop(
        at axFrame: CGRect,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        in entries: [MenuBarAgentWindow.Entry]?
    ) -> Bool {
        if let drawn = drawnFrame(for: axFrame, ownerPID: ownerPID, sourcePID: sourcePID, in: entries) {
            return abs(drawn.midX - axFrame.midX) <= agreementTolerance
        }
        return !isPhantom(axFrame, ownerPID: ownerPID, sourcePID: sourcePID, in: entries)
    }

    /// The item's known processes, the source first, without repeats.
    private static func processes(ownerPID: pid_t, sourcePID: pid_t?) -> [pid_t] {
        var pids: [pid_t] = []
        for pid in [sourcePID, ownerPID].compactMap(\.self) where pid > 0 && !pids.contains(pid) {
            pids.append(pid)
        }
        return pids
    }
}
