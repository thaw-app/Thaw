//
//  CapturePublicationPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// What a capture was admitted against, taken before its first await.
nonisolated struct CapturePublicationAdmission: Equatable, Sendable {
    let layoutGeneration: UInt64
    let displayID: CGDirectDisplayID?
}

/// Decides whether a finished capture may still be published.
///
/// Source geometry, layout revision and display identity are separate
/// concerns: the first is validated per pixel source while capturing, the other
/// two are judged here against what the capture was admitted with.
nonisolated enum CapturePublicationPolicy {
    enum Rejection: Equatable, Sendable {
        case layoutResetting
        case layoutChanged
        case displayChanged
        case recentMove
    }

    static func admit(
        layout: MenuBarLayoutPublicationState,
        displayID: CGDirectDisplayID?
    ) -> CapturePublicationAdmission {
        CapturePublicationAdmission(layoutGeneration: layout.generation, displayID: displayID)
    }

    static func rejection(
        of admission: CapturePublicationAdmission,
        layout: MenuBarLayoutPublicationState,
        displayID: CGDirectDisplayID?,
        isResettingLayout: Bool,
        moveWithinCooldown: Bool,
        ignoreRecentMove: Bool
    ) -> Rejection? {
        if isResettingLayout { return .layoutResetting }
        // Covers a completed newer move, a mutation still running, and an
        // authored invalidation. The forced refresh flag never reaches this:
        // it only waives the cooldown of a move that finished before admission.
        guard layout.canPublish(generation: admission.layoutGeneration) else { return .layoutChanged }
        guard displayID == admission.displayID else { return .displayChanged }
        if moveWithinCooldown, !ignoreRecentMove { return .recentMove }
        return nil
    }
}
