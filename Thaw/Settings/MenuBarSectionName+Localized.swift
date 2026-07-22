//
//  MenuBarSectionName+Localized.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI

nonisolated extension MenuBarSectionName {
    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .visible: LocalizedStringKey("Visible")
        case .hidden: LocalizedStringKey("Hidden")
        case .alwaysHidden: LocalizedStringKey("Always-Hidden")
        }
    }
}
