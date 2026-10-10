//
//  RehideStrategy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A type that determines how the auto-rehide feature works.
nonisolated enum RehideStrategy: Int, CaseIterable, Identifiable {
    case smart = 0
    case timed = 1
    /// Menu bar items are rehidden when the focused app changes.
    case focusedApp = 2

    var id: Int {
        rawValue
    }

    var localized: LocalizedStringKey {
        switch self {
        case .smart: "Smart"
        case .timed: "Timed"
        case .focusedApp: "Focus"
        }
    }

    /// Supports exact case names: "smart", "timed", "focusedApp"
    /// Or raw integer values: "0", "1", "2"
    static func fromString(_ value: String) -> RehideStrategy? {
        switch value {
        case "smart", "0":
            return .smart
        case "timed", "1":
            return .timed
        case "focusedApp", "2":
            return .focusedApp
        default:
            return nil
        }
    }
}
