//
//  ThawBarLocation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Locations where the Thaw Bar can appear.
/// Raw values and case names are stored and used by thaw:// links, so only the labels may change.
nonisolated enum ThawBarLocation: Int, CaseIterable, Codable, Identifiable {
    /// Under the pointer when it is on an empty part of the menu bar as the bar opens,
    /// otherwise under the Thaw icon.
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
        case .dynamic: "Pointer or \(Constants.displayName) icon"
        case .mousePointer: "Under the pointer"
        case .thawIcon: "Under the \(Constants.displayName) icon"
        case .leftAligned: "Left edge"
        case .rightAligned: "Right edge"
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

/// Where a shortcut opens the Thaw Bar. Stored as the thawBarLocationOnHotkey switch,
/// which profiles and thaw:// links also read, so both values keep their meaning.
nonisolated enum ThawBarShortcutPlacement: CaseIterable, Hashable, Identifiable {
    /// The shortcut opens the bar where the display's Location says.
    case location
    /// The shortcut opens the bar centered on the pointer, wherever it is on the screen.
    case pointer

    init(opensAtPointer: Bool) {
        self = opensAtPointer ? .pointer : .location
    }

    var opensAtPointer: Bool {
        self == .pointer
    }

    var id: Self {
        self
    }

    var localized: LocalizedStringKey {
        switch self {
        case .location: "Use Location"
        case .pointer: "Centered on the pointer"
        }
    }
}
