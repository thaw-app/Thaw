//
//  ReducedModeHider+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// Hides whole apps without reading the menu bar, through the kit's hide that trusts a given
/// owner map instead of a walk.
@MainActor
final class ReducedModeHider {
    private let session = RuntimeSessionController()

    var isAvailable: Bool { session.refreshAvailability() }

    /// Hides exactly these apps. An empty set shows everything.
    @discardableResult
    func apply(hiding bundleIDs: Set<String>) -> Bool {
        let input = Self.input(hiding: bundleIDs)
        return session.applyPersisted(sectionAssignment: input.assignment, knownBundleIDs: input.owners)
    }
}
