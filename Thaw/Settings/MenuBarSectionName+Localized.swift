//
//  MenuBarSectionName+Localized.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI

nonisolated extension MenuBarSectionName {
    var localized: LocalizedStringKey {
        switch self {
        case .visible: LocalizedStringKey("Visible")
        case .hidden: LocalizedStringKey("Hidden")
        case .alwaysHidden: LocalizedStringKey("Always-Hidden")
        }
    }
}
