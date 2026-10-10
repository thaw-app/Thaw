//
//  RecordingWatchScreen.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import SwiftUI

/// Recording events may happen away from the pointer, so users can pin banners to a predictable display.
nonisolated enum RecordingWatchScreen: Hashable {
    /// Defaults to the pointer's screen, matching HUD confirmations.
    case screenWithPointer

    /// The primary display, the one the others are arranged around.
    case mainDisplay

    /// Uses the same getDisplayUUIDString identity as per-display settings.
    /// Fall back to the primary display when disconnected so announcements never silently vanish.
    case display(uuid: String)

    // MARK: Storage

    /// Persist the case name or display:<uuid> to support associated values.
    var storageKey: String {
        switch self {
        case .screenWithPointer: "screenWithPointer"
        case .mainDisplay: "mainDisplay"
        case let .display(uuid): "display:\(uuid)"
        }
    }

    /// Unknown encodings return nil for default fallback.
    /// Reject empty display UUIDs rather than treating them as chosen screens.
    static func from(storageKey: String) -> Self? {
        switch storageKey {
        case "screenWithPointer": return RecordingWatchScreen.screenWithPointer
        case "mainDisplay": return RecordingWatchScreen.mainDisplay
        default:
            guard storageKey.hasPrefix("display:") else {
                return nil
            }
            let uuid = String(storageKey.dropFirst("display:".count))
            return uuid.isEmpty ? nil : .display(uuid: uuid)
        }
    }

    // MARK: Resolution

    /// Pure display selection from the caller's live screen snapshot.
    /// - Parameters:
    ///   - pointerDisplayID: The pointer's display, or nil if unknown.
    ///   - primaryDisplayID: The primary display, or nil if no screens exist.
    ///   - connectedDisplays: Every connected display, by UUID.
    func resolve(
        pointerDisplayID: CGDirectDisplayID?,
        primaryDisplayID: CGDirectDisplayID?,
        connectedDisplays: [(uuid: String, displayID: CGDirectDisplayID)]
    ) -> CGDirectDisplayID? {
        switch self {
        case .screenWithPointer:
            pointerDisplayID ?? primaryDisplayID
        case .mainDisplay:
            primaryDisplayID
        case let .display(uuid):
            connectedDisplays.first { $0.uuid == uuid }?.displayID ?? primaryDisplayID
        }
    }

    /// Panes use the display's own name for display choices instead of this generic label.
    var localized: LocalizedStringKey {
        switch self {
        case .screenWithPointer: "Screen with pointer"
        case .mainDisplay: "Main display"
        case .display: "Chosen display"
        }
    }
}
