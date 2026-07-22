//
//  SettingsNavigationIdentifier.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The navigation identifier type for the "Settings" interface.
enum SettingsNavigationIdentifier: String, @MainActor NavigationIdentifier {
    case general = "General"
    case menuBarLayout = "Menu Bar Layout"
    case displays = "Displays"
    case menuBarAppearance = "Menu Bar Appearance"
    case hotkeys = "Hotkeys"
    case profiles = "Profiles"
    case advanced = "Advanced"
    case automation = "Automation"
    case tools = "Tools"
    case about = "About"

    var localized: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .menuBarLayout: "Layout"
        case .displays: "Displays"
        case .menuBarAppearance: "Appearance"
        case .hotkeys: "Hotkeys"
        case .profiles: "Profiles"
        case .advanced: "Advanced"
        case .automation: "Automation"
        case .tools: "Tools"
        case .about: "About"
        }
    }

    var iconResource: IconResource {
        switch self {
        case .general: .systemSymbol("gearshape")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .displays: .systemSymbol("display.2")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .profiles: .systemSymbol("person.crop.rectangle.stack")
        case .advanced: .systemSymbol("gearshape.2")
        case .automation: .systemSymbol("app.badge.checkmark")
        case .tools: .systemSymbol("wrench.and.screwdriver")
        case .about: .systemSymbol("cube")
        }
    }
}
