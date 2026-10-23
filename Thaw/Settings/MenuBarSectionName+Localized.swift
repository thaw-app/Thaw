//
//  MenuBarSectionName+Localized.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

nonisolated extension MenuBarSectionName {
    var localized: LocalizedStringResource {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always-Hidden"
        }
    }
}
