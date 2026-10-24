//
//  MenuBarItem+Ordering.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Exposes non-optional section buckets so CacheRebucketter can use app caches without an app-target dependency.
public protocol MenuBarSectionBucketed {
    subscript(_: MenuBarSectionName) -> [MenuBarItem] { get set }
}

public extension MenuBarItem {
    static func sortByLeadingEdge(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    static func sortByVisualCenter(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.bounds.midX < $1.bounds.midX }
    }

    /// Sorts leading edges on the reference bar, preserving input order for ties.
    /// Returns nil when any item's midpoint is outside the known displays.
    static func sortByLeadingEdge(_ items: [MenuBarItem], displayBounds: [CGRect]) -> [MenuBarItem]? {
        sortReferenceAligned(items, displayBounds: displayBounds, by: \.minX)
    }

    /// Sorts visual centers on the reference bar, preserving input order for ties.
    /// Returns nil when any item's midpoint is outside the known displays.
    static func sortByVisualCenter(_ items: [MenuBarItem], displayBounds: [CGRect]) -> [MenuBarItem]? {
        sortReferenceAligned(items, displayBounds: displayBounds, by: \.midX)
    }

    private static func sortReferenceAligned(
        _ items: [MenuBarItem],
        displayBounds: [CGRect],
        by coordinate: KeyPath<CGRect, CGFloat>
    ) -> [MenuBarItem]? {
        var aligned: [(item: MenuBarItem, coordinate: CGFloat)] = []
        aligned.reserveCapacity(items.count)
        for item in items {
            guard let frame = MirroredBarGeometry.referenceAligned(item.bounds, displayBounds: displayBounds) else { return nil }
            aligned.append((item, frame[keyPath: coordinate]))
        }
        return aligned.sorted { $0.coordinate < $1.coordinate }.map(\.item)
    }

    /// Break midX ties by identifier to keep cache signatures stable during transient reflows.
    static func sortByVisualCenterThenIdentifier(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { lhs, rhs in
            if lhs.bounds.midX == rhs.bounds.midX {
                return lhs.uniqueIdentifier < rhs.uniqueIdentifier
            }
            return lhs.bounds.midX < rhs.bounds.midX
        }
    }
}
