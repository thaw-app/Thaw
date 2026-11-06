//
//  LayoutDetailTab.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// What the Layout page shows under its bars, one list at a time.
nonisolated enum LayoutDetailTab: CaseIterable, ThawTab {
    case options
    case groups
    case spacers
    case appleItems

    var title: LocalizedStringResource {
        switch self {
        case .groups: "Groups"
        case .spacers: "Spacers"
        case .options: "Options"
        case .appleItems: "Apple’s Items"
        }
    }

    var systemImage: String {
        switch self {
        case .groups: "square.stack.3d.up"
        case .spacers: "arrow.left.and.right"
        case .options: "slider.horizontal.3"
        case .appleItems: "apple.logo"
        }
    }

    /// The tab a search result opens, so the setting it names is on screen.
    static func tab(for disclosure: AppNavigationState.SettingsDisclosure?) -> LayoutDetailTab? {
        switch disclosure {
        case .layoutSpacers: .spacers
        case .layoutOptions: .options
        case .layoutAppleItems: .appleItems
        default: nil
        }
    }
}
