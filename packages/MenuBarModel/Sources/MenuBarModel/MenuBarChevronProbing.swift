//
//  MenuBarChevronProbing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Finds the native overflow chevron by hit-testing the menu bar strip.
///
/// The chevron is not reliably a child of the extras bar (the accessibility
/// walk has been seen returning nothing while it was on screen and being
/// clicked), so it is located by probing the strip instead of by enumeration.
/// Both the item provider and the cover need that answer, and neither should
/// have to know how it is obtained.
public protocol MenuBarChevronProbing: Sendable {
    /// Chevron frames found within displayBounds, in display coordinates.
    ///
    /// additionalOwnerBundleIDs is empty in production, where only the menu
    /// bar host draws a real chevron; a test harness passes its own bundle
    /// identifier to have a decoy status item detected through the real path.
    func detectChevrons(
        in displayBounds: CGRect,
        additionalOwnerBundleIDs: Set<String>
    ) -> [CGRect]
}

public extension MenuBarChevronProbing {
    /// Chevron frames drawn by the menu bar host alone.
    func detectChevrons(in displayBounds: CGRect) -> [CGRect] {
        detectChevrons(in: displayBounds, additionalOwnerBundleIDs: [])
    }
}
