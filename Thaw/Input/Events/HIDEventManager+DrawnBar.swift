//
//  HIDEventManager+DrawnBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawAXCore

/// What MenuBarAgent draws under the pointer. An app that refuses accessibility
/// reads is in no item list, but its icon is still drawn and takes the click.
extension HIDEventManager {
    /// Whether MenuBarAgent draws another app's item under location, from the cached read.
    func isMouseInsideDrawnBarItem(appState: AppState, at location: CGPoint) -> Bool {
        guard let answer = pointerAXCache.drawnBarAnswer() else { return false }
        reportUnreadableOwners(in: answer.entries, readAt: answer.answeredAt, appState: appState)
        let context = Self.displayContext(for: location)
        return Self.drawnBarContains(
            location,
            entries: answer.entries,
            ownPID: getpid(),
            destinationDisplay: context.destination,
            displayBounds: context.all,
            laneMinX: context.laneMinX
        )
    }

    /// The pointer is already inside the bar, so only x is compared: an item's
    /// frame is shorter than the bar and a click above it still lands on it.
    static nonisolated func drawnBarContains(
        _ location: CGPoint,
        entries: [MenuBarAgentWindow.Entry],
        ownPID: pid_t,
        destinationDisplay: CGRect?,
        displayBounds: [CGRect],
        laneMinX: CGFloat?
    ) -> Bool {
        entries.contains { entry in
            guard entry.ownerPID != ownPID,
                  entry.frame.width <= maxReasonableItemWidth,
                  let drawn = MirroredBarGeometry.drawnFrame(
                      entry.frame, on: destinationDisplay, displayBounds: displayBounds, laneMinX: laneMinX
                  )
            else {
                return false
            }
            return drawn.minX <= location.x && location.x < drawn.maxX
        }
    }

    /// Logs an app once when the bar keeps drawing it and the walk keeps missing it.
    private func reportUnreadableOwners(
        in entries: [MenuBarAgentWindow.Entry],
        readAt: ContinuousClock.Instant,
        appState: AppState
    ) {
        guard pointerAXCache.unreadableOwnersComparedAt != readAt else { return }
        pointerAXCache.unreadableOwnersComparedAt = readAt
        let items = appState.itemManager.onScreenItemSnapshot.items + appState.itemManager.managedItems
        let read = Set(items.flatMap { [$0.ownerPID, $0.sourcePID].compactMap(\.self) })
        let drawn = Set(entries.map(\.ownerPID)).subtracting([getpid()])
        let change = pointerAXCache.unreadableOwners.note(drawn: drawn, read: read)
        for pid in change.readableAgain {
            Self.diagLog.info("drawn bar: pid \(pid) is readable again")
        }
        for pid in change.unreadable {
            let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
            Task.detached(priority: .utility) {
                let result = AXPrimitives.extrasMenuBarReadResult(pid: pid)
                Self.diagLog.warning(
                    "drawn bar: \(bundle) (pid \(pid)) has an icon on the bar but gives the walk no items; extras bar read=\(result.rawValue)"
                )
            }
        }
    }
}
