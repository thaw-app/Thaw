//
//  SectionDividerStyle.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The display style for section divider control items.
enum SectionDividerStyle: Int, CaseIterable, Identifiable {
    case noDivider = 0
    case chevron = 1

    var id: Int {
        rawValue
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noDivider: "None"
        case .chevron: "Chevron"
        }
    }
}
