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

    /// The heading's name as a String, for menus, VoiceOver values and messages. ``displayString``
    /// is the English name for logs and stays untranslated.
    var localizedName: String {
        localizedName(in: .main)
    }

    /// The same keys as ``localized``, so both read one catalog entry each.
    func localizedName(in bundle: Bundle) -> String {
        switch self {
        case .visible: String(localized: "Visible", bundle: bundle)
        case .hidden: String(localized: "Hidden", bundle: bundle)
        case .alwaysHidden: String(localized: "Always-Hidden", bundle: bundle)
        }
    }
}
