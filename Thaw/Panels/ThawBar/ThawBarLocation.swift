//
//  ThawBarLocation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Locations where the Thaw Bar can appear.
nonisolated enum ThawBarLocation: Int, CaseIterable, Codable, Identifiable {
    /// The Thaw Bar will appear in different locations based on context.
    case dynamic = 0

    /// The Thaw Bar will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The Thaw Bar will appear centered below the Thaw icon.
    case thawIcon = 2

    /// The Thaw Bar will appear aligned to the left edge of the display.
    case leftAligned = 3

    /// The Thaw Bar will appear aligned to the right edge of the display.
    case rightAligned = 4

    var id: Int {
        rawValue
    }

    var localized: LocalizedStringKey {
        switch self {
        case .dynamic: "Dynamic"
        case .mousePointer: "Mouse pointer"
        case .thawIcon: "\(Constants.displayName) icon"
        case .leftAligned: "Left aligned"
        case .rightAligned: "Right aligned"
        }
    }

    /// Accepts exact case names or raw integer values.
    static func fromString(_ value: String) -> ThawBarLocation? {
        switch value {
        case "dynamic", "0":
            return .dynamic
        case "mousePointer", "1":
            return .mousePointer
        // "iceIcon" is the Ice-era spelling, kept for script compatibility.
        case "thawIcon", "iceIcon", "2":
            return .thawIcon
        case "leftAligned", "3":
            return .leftAligned
        case "rightAligned", "4":
            return .rightAligned
        default:
            return nil
        }
    }
}
