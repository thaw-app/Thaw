//
//  DrawnSeating.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Puts one crop's items at the seats MenuBarAgent draws them in, when the crop asks for it.
/// AXBoundsCropper.Request.seatsOnDrawnBar says why.
nonisolated struct DrawnSeating: Sendable {
    let isOn: Bool
    let displayID: CGDirectDisplayID
    /// The reported frame of each item cut at its drawn seat.
    private(set) var reportedBounds: [String: CGRect] = [:]

    /// The candidates at their drawn seats, for those drawn away from the frame they report. One that no
    /// crop is safe for (DrawnSeats.occupied) is left out and rejected into pass, keeping its picture.
    mutating func seat(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        using reader: any MenuBarCaptureReading,
        rejectingInto pass: inout MenuBarItemImageCache.CapturePass
    ) async -> [(item: MenuBarItem, bounds: CGRect)] {
        guard isOn else { return candidates }
        let seats = await reader.drawnSeats(for: candidates, displayID: displayID)
        var seated = [(item: MenuBarItem, bounds: CGRect)]()
        for (item, bounds) in candidates {
            if seats.occupied.contains(item.uniqueIdentifier) {
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: \(item.logString) at \(bounds) can't be cut clear of another app's drawn item; keeping its prior image"
                )
                pass.reject(item, .keepPrior)
            } else if let seat = seats.moved[item.uniqueIdentifier] {
                reportedBounds[item.uniqueIdentifier] = bounds
                MenuBarItemImageCache.diagLog.debug(
                    "axBoundsCapture: \(item.logString) reports \(bounds) but is drawn to one side; cropping at \(seat)"
                )
                seated.append((item, seat))
            } else {
                seated.append((item, bounds))
            }
        }
        return seated
    }

    /// The candidates at the frames they report, which is what their apps are asked about.
    func reported(_ candidates: [(item: MenuBarItem, bounds: CGRect)]) -> [(item: MenuBarItem, bounds: CGRect)] {
        candidates.map { (item: $0.item, bounds: reportedBounds[$0.item.uniqueIdentifier] ?? $0.bounds) }
    }

    /// Frames read after a source's pixels, moved onto the seats MenuBarAgent draws now.
    struct Seated {
        /// Each item's frame, at its drawn seat when it is drawn away from it. A seat that changed
        /// meanwhile reads as movement.
        var bounds: [String: CGRect]
        /// Items another app's item is now drawn over, left out of bounds. Their crops are rejected
        /// even where a missing frame is forgiven.
        var occupied: Set<String> = []
    }

    /// See Seated.
    func seated(
        _ bounds: [String: CGRect],
        of items: [MenuBarItem],
        using reader: any MenuBarCaptureReading
    ) async -> Seated {
        guard isOn else { return Seated(bounds: bounds) }
        let live = items.compactMap { item in bounds[item.uniqueIdentifier].map { (item: item, bounds: $0) } }
        let seats = await reader.drawnSeats(for: live, displayID: displayID)
        for identifier in seats.occupied.sorted() {
            MenuBarItemImageCache.diagLog.debug("axBoundsCapture: another app's item is now drawn where \(identifier) was cut; keeping its prior image")
        }
        let seated = bounds.merging(seats.moved) { _, seat in seat }.filter { !seats.occupied.contains($0.key) }
        return Seated(bounds: seated, occupied: seats.occupied)
    }
}
