//
//  RehideStrategy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A type that determines how the auto-rehide feature works.
enum RehideStrategy: Int, CaseIterable, Identifiable {
    /// Menu bar items are rehidden using a smart algorithm.
    case smart = 0
    /// Menu bar items are rehidden after a given time interval.
    case timed = 1
    /// Menu bar items are rehidden when the focused app changes.
    case focusedApp = 2

    var id: Int {
        rawValue
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .smart: "Smart"
        case .timed: "Timed"
        case .focusedApp: "Focus"
        }
    }

    /// Parses a RehideStrategy from a string value.
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
