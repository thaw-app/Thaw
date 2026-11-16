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
/// Its frames span the bar's full height, so only their x and width are used. The width is not the
/// Accessibility frame's: it has been seen both wider and narrower.
nonisolated enum DrawnItemFrame {
    /// The frame the item is drawn at: x and width from its drawn entry, y and height from
    /// axFrame. Nil unless the read is settled and exactly one entry belongs to the item's app:
    /// its source process for an item MenuBarAgent hosts, whose own entries are other items.
    static func drawnFrame(
        for axFrame: CGRect,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        in entries: [MenuBarAgentWindow.Entry]?,
        displays: [CGRect] = []
    ) -> CGRect? {
        guard let entries = entries.flatMap(MenuBarAgentWindow.settled),
              let app = processes(ownerPID: ownerPID, sourcePID: sourcePID).first
        else { return nil }
        let own = onDisplay(of: axFrame, entries, displays: displays).filter { $0.ownerPID == app }
        guard own.count == 1, let drawn = own.first else { return nil }
        return CGRect(x: drawn.frame.minX, y: axFrame.minY, width: drawn.frame.width, height: axFrame.height)
    }

    /// Whether axFrame sits on an item another app has drawn: a shared left edge or a large
    /// overlap, as MenuBarItem.hasPhantomFrame(among:) decides between items.
    static func isPhantom(
        _ axFrame: CGRect,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        in entries: [MenuBarAgentWindow.Entry]?,
        displays: [CGRect] = []
    ) -> Bool {
        guard axFrame.width > 0, let entries = entries.flatMap(MenuBarAgentWindow.settled) else { return false }
        let own = Set(processes(ownerPID: ownerPID, sourcePID: sourcePID))
        return onDisplay(of: axFrame, entries, displays: displays).contains { entry in
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
        in entries: [MenuBarAgentWindow.Entry]?,
        displays: [CGRect] = []
    ) -> CGRect? {
        if let drawn = drawnFrame(for: axFrame, ownerPID: ownerPID, sourcePID: sourcePID, in: entries, displays: displays) {
            return drawn
        }
        return isPhantom(axFrame, ownerPID: ownerPID, sourcePID: sourcePID, in: entries, displays: displays) ? nil : axFrame
    }

    /// How far apart, in points, the centres of an item's drawn and Accessibility frames may be before its
    /// picture is cut at the drawn one. Six items at rest on one Mac (macOS 27.3, no notch) were 0.5 to 0.8 apart.
    static let cropAgreementTolerance: CGFloat = 2

    /// Where a picture of the item is cut: axFrame, moved sideways onto the centre of its drawn frame when
    /// that is known and more than cropAgreementTolerance away. The size stays axFrame's, like every other picture.
    static func cropFrame(
        for axFrame: CGRect,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        in entries: [MenuBarAgentWindow.Entry]?
    ) -> CGRect {
        guard let drawn = drawnFrame(for: axFrame, ownerPID: ownerPID, sourcePID: sourcePID, in: entries) else {
            return axFrame
        }
        let shift = drawn.midX - axFrame.midX
        return abs(shift) > cropAgreementTolerance ? axFrame.offsetBy(dx: shift, dy: 0) : axFrame
    }

    /// The entries on the display holding axFrame, or all when none holds it: MenuBarAgent's first
    /// window can be another display's bar.
    private static func onDisplay(
        of axFrame: CGRect,
        _ entries: [MenuBarAgentWindow.Entry],
        displays: [CGRect]
    ) -> [MenuBarAgentWindow.Entry] {
        guard let display = displays.first(where: { $0.contains(CGPoint(x: axFrame.midX, y: axFrame.midY)) }) else {
            return entries
        }
        return entries.filter { display.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
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
