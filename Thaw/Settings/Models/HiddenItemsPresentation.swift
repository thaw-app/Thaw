//
//  HiddenItemsPresentation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Where hidden items appear, as one choice over the two stored switches.
nonisolated enum HiddenItemsPresentation: CaseIterable, Identifiable {
    /// Hidden items show in the menu bar when the user reveals them.
    case onClick
    /// Hidden items show in the Thaw Bar below the menu bar.
    case thawBar
    /// Hidden items stay in the menu bar all the time.
    case alwaysShown

    /// The two stored switches a choice stands for.
    struct Switches: Equatable {
        let useThawBar: Bool
        let alwaysShowHiddenItems: Bool
    }

    var id: Self {
        self
    }

    /// The Thaw Bar wins when both are on, because the always-show switch was disabled while it was on.
    init(useThawBar: Bool, alwaysShowHiddenItems: Bool) {
        if useThawBar {
            self = .thawBar
        } else if alwaysShowHiddenItems {
            self = .alwaysShown
        } else {
            self = .onClick
        }
    }

    var switches: Switches {
        switch self {
        case .onClick: Switches(useThawBar: false, alwaysShowHiddenItems: false)
        case .thawBar: Switches(useThawBar: true, alwaysShowHiddenItems: false)
        case .alwaysShown: Switches(useThawBar: false, alwaysShowHiddenItems: true)
        }
    }

    var localized: LocalizedStringKey {
        switch self {
        case .onClick: "In the menu bar"
        case .thawBar: "In the \(Constants.displayName) Bar"
        case .alwaysShown: "Always in the menu bar"
        }
    }
}
