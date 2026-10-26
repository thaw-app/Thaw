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
