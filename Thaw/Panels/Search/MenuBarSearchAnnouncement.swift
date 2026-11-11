//
//  MenuBarSearchAnnouncement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// What VoiceOver hears in search. The highlight moves without focus, so
/// nothing would be read otherwise.
enum MenuBarSearchAnnouncement {
    /// The row's name, and its section when it has one.
    @MainActor
    static func row(_ result: MenuBarSearchResult) -> String {
        let name = MenuBarItemDisplayName.displayName(for: result.item)
        guard let section = result.section else {
            return name
        }
        return String(localized: "\(name), \(section)", comment: "VoiceOver: a search result and the section it is listed under.")
    }

    /// The match count and the first match, in one message so they don't interrupt each other.
    @MainActor
    static func results(_ results: [MenuBarSearchResult]) -> String {
        let count = String(AttributedString(localized: "^[\(results.count) result](inflect: true)").characters)
        guard let first = results.first else {
            return count
        }
        return "\(count). \(row(first))"
    }
}
