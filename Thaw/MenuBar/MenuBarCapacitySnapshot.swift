//
//  MenuBarCapacitySnapshot.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

/// A display-specific, horizontal-only view of the space available to menu bar
/// items. AppKit, AX, and Core Graphics agree on global X coordinates even
/// though their Y axes differ, so capacity calculations deliberately ignore Y.
nonisolated struct MenuBarCapacitySnapshot: Equatable, Sendable {
    enum Region: Sendable {
        /// The contiguous status-item lane nearest Control Center.
        case trailing
        /// Every usable inline lane, including space to the left of a notch.
        case inline
    }

    enum ApplicationMenus: Sendable {
        case visible
        case hidden
    }

    /// The clearance macOS keeps on each horizontal side of a notch.
    static let notchGap: CGFloat = 24

    let displayID: CGDirectDisplayID
    let displayBounds: CGRect
    let notchFrame: CGRect?
    let applicationMenuFrame: CGRect?
    let trailingBoundary: CGFloat?
    let overflowControlBounds: [CGRect]

    @MainActor
    static func capture(
        on screen: NSScreen,
        items: [MenuBarItem],
        overflowControlBounds: [CGRect] = []
    ) -> Self {
        let displayBounds = CGDisplayBounds(screen.displayID)
        let displayItems = items.filter { displayBounds.contains($0.bounds.center) }
        let controlCenters = displayItems.filter { $0.tag == .controlCenter }
        let trailingBoundary: CGFloat? = if controlCenters.isEmpty {
            displayBounds.maxX
        } else if let controlCenter = controlCenters.min(by: { $0.bounds.minX < $1.bounds.minX }),
                  displayBounds.contains(controlCenter.bounds.center)
        {
            controlCenter.bounds.minX
        } else {
            nil
        }

        return Self(
            displayID: screen.displayID,
            displayBounds: displayBounds,
            notchFrame: screen.frameOfNotch,
            applicationMenuFrame: screen.getApplicationMenuFrame(),
            trailingBoundary: trailingBoundary,
            overflowControlBounds: overflowControlBounds
        )
    }

    /// Returns the usable width after clipping and unioning all occupied
    /// intervals. Unioning prevents stale AX and live item bounds that overlap
    /// from being subtracted twice.
    func availableWidth(
        in region: Region,
        applicationMenus: ApplicationMenus,
        reserving occupiedBounds: [CGRect] = []
    ) -> CGFloat? {
        guard let lanes = lanes(in: region, applicationMenus: applicationMenus) else {
            return nil
        }

        let reservations = (occupiedBounds + overflowControlBounds).filter {
            displayBounds.contains($0.center)
        }
        return lanes.reduce(0) { total, lane in
            let laneWidth = lane.upperBound - lane.lowerBound
            return total + max(0, laneWidth - reservedWidth(in: lane, reservations: reservations))
        }
    }

    private func lanes(
        in region: Region,
        applicationMenus: ApplicationMenus
    ) -> [Range<CGFloat>]? {
        guard !displayBounds.isNull,
              !displayBounds.isEmpty,
              displayBounds.minX.isFinite,
              displayBounds.maxX.isFinite,
              let trailingBoundary,
              trailingBoundary.isFinite,
              trailingBoundary > displayBounds.minX,
              trailingBoundary <= displayBounds.maxX
        else {
            return nil
        }

        let menuBoundary: CGFloat
        switch applicationMenus {
        case .hidden:
            menuBoundary = displayBounds.minX
        case .visible:
            guard let applicationMenuFrame,
                  !applicationMenuFrame.isNull,
                  !applicationMenuFrame.isEmpty,
                  applicationMenuFrame.maxX.isFinite
            else {
                return nil
            }
            menuBoundary = max(displayBounds.minX, applicationMenuFrame.maxX)
        }

        guard let notchFrame else {
            let lowerBound = min(max(menuBoundary, displayBounds.minX), trailingBoundary)
            return [lowerBound ..< trailingBoundary]
        }
        guard !notchFrame.isNull,
              !notchFrame.isEmpty,
              notchFrame.minX.isFinite,
              notchFrame.maxX.isFinite
        else {
            return nil
        }

        let leftEnd = min(trailingBoundary, notchFrame.minX - Self.notchGap)
        let rightStart = max(
            notchFrame.maxX + Self.notchGap,
            applicationMenus == .visible ? menuBoundary : displayBounds.minX
        )
        let trailingLane = min(max(rightStart, displayBounds.minX), trailingBoundary) ..< trailingBoundary

        switch region {
        case .trailing:
            return [trailingLane]
        case .inline:
            let leftStart = min(max(menuBoundary, displayBounds.minX), leftEnd)
            return [leftStart ..< leftEnd, trailingLane]
        }
    }

    private func reservedWidth(
        in lane: Range<CGFloat>,
        reservations: [CGRect]
    ) -> CGFloat {
        let intervals = reservations.compactMap { bounds -> Range<CGFloat>? in
            guard !bounds.isNull,
                  !bounds.isEmpty,
                  bounds.minX.isFinite,
                  bounds.maxX.isFinite
            else {
                return nil
            }
            let lower = max(lane.lowerBound, bounds.minX)
            let upper = min(lane.upperBound, bounds.maxX)
            return lower < upper ? lower ..< upper : nil
        }.sorted { lhs, rhs in
            lhs.lowerBound == rhs.lowerBound
                ? lhs.upperBound < rhs.upperBound
                : lhs.lowerBound < rhs.lowerBound
        }

        guard var current = intervals.first else { return 0 }
        var width: CGFloat = 0
        for interval in intervals.dropFirst() {
            if interval.lowerBound <= current.upperBound {
                current = current.lowerBound ..< max(current.upperBound, interval.upperBound)
            } else {
                width += current.upperBound - current.lowerBound
                current = interval
            }
        }
        return width + current.upperBound - current.lowerBound
    }
}
