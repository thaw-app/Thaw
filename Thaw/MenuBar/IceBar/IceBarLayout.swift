//
//  IceBarLayout.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Layout modes for the Thaw Bar.
nonisolated enum IceBarLayout: Int, CaseIterable, Codable, Identifiable {
    /// Items are arranged in a single horizontal row.
    case horizontal = 0

    /// Items are stacked vertically in a single column.
    case vertical = 1

    /// Items are arranged in a grid with a configurable number of columns.
    case grid = 2

    var id: Int {
        rawValue
    }

    var localized: LocalizedStringKey {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        case .grid: "Grid"
        }
    }

    /// Accepts case names or raw integer values.
    static func fromString(_ value: String) -> IceBarLayout? {
        switch value {
        case "horizontal", "0":
            return .horizontal
        case "vertical", "1":
            return .vertical
        case "grid", "2":
            return .grid
        default:
            return nil
        }
    }
}
