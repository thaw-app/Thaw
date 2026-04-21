//
//  SettingsNavigationIdentifier.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The navigation identifier type for the "Settings" interface.
enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case general = "General"
    case displays = "Displays"
    case menuBarLayout = "Menu Bar Layout"
    case menuBarAppearance = "Menu Bar Appearance"
    case hotkeys = "Hotkeys"
    case profiles = "Profiles"
    case advanced = "Advanced"
    case automation = "Automation"
    case about = "About"

    var localized: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .displays: "Displays"
        case .menuBarLayout: "Layout"
        case .menuBarAppearance: "Appearance"
        case .hotkeys: "Hotkeys"
        case .profiles: "Profiles"
        case .advanced: "Advanced"
        case .automation: "Automation"
        case .about: "About"
        }
    }

    var iconResource: IconResource {
        switch self {
        case .general: .systemSymbol("gearshape")
        case .displays: .systemSymbol("display.2")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .profiles: .systemSymbol("person.crop.rectangle.stack")
        case .advanced: .systemSymbol("gearshape.2")
        case .automation: .systemSymbol("app.badge.checkmark")
        case .about: .systemSymbol("cube")
        }
    }
}
