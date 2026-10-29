//
//  MenuBarItemImageCache+CaptureInputs.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension MenuBarItemImageCache {
    /// How one capture pass treats the items it is given.
    nonisolated struct CaptureOptions {
        /// Re-read item geometry before the screenshot and check it again afterward.
        var freshBounds = false
        var concealedIdentifiers: Set<String> = []
        /// Items captured even though they would normally be skipped.
        var forgivenTags: Set<MenuBarItemTag> = []
    }

    /// What appendAXBoundsCrops checks each crop against, gathered from one capture source.
    nonisolated struct AXCropRules {
        let knockOutBackground: Bool
        let validateFreshBounds: Bool
        let absenceMeansMoved: Bool
        let postCaptureBoundsByID: [String: CGRect]
        let captureTimeBoundsByID: [String: CGRect]
        let overflowBounds: [CGRect]
        let concealedIdentifiers: Set<String>
        let ambiguousIdentifiers: Set<String>
        let forgivenTags: Set<MenuBarItemTag>
    }

    /// The display a grouped reveal captures from, and the one its item cache
    /// was on when the reveal was chosen.
    nonisolated struct RevealCaptureTarget {
        let displayID: CGDirectDisplayID
        let admittedDisplayID: CGDirectDisplayID?
        let scale: CGFloat
    }
}
