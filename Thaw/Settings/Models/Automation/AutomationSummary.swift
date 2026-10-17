//
//  AutomationSummary.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The one-line descriptions on the Automation page, which say what is set
/// right now instead of explaining the control.
nonisolated enum AutomationSummary {
    /// A profile and the display or Space that switches to it.
    struct Assignment: Equatable {
        let profile: String
        let place: String
    }

    /// Lists past this many names end in a count.
    static let namedLimit = 3

    static func profileSwitching(_ assignments: [Assignment], locale: Locale = .current) -> String {
        guard !assignments.isEmpty else {
            return String(localized: "No display or Space switches profiles yet.")
        }
        let parts = assignments.map { String(localized: "\($0.profile) on \($0.place)") }
        return list(parts, locale: locale) + "."
    }

    /// The script's path with the home folder shortened to ~, or None.
    static func script(path: String?) -> String {
        guard let path, !path.isEmpty else {
            return String(localized: "None")
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private static func list(_ items: [String], locale: Locale) -> String {
        var shown = items
        if items.count > namedLimit {
            shown = Array(items.prefix(namedLimit - 1))
            shown.append(String(localized: "\(items.count - namedLimit + 1) more"))
        }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: shown) ?? shown.joined(separator: ", ")
    }
}
