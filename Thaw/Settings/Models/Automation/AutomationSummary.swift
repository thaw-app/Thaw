//
//  AutomationSummary.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// One-line descriptions of what is set now, not of the control.
nonisolated enum AutomationSummary {
    /// A profile and the display or Space that switches to it.
    struct Assignment: Equatable {
        let profile: String
        let place: String
    }

    /// Every display and Space that switches to a profile, in profile order.
    static func assignments(of profiles: [ProfileMetadata]) -> [Assignment] {
        profiles.flatMap { profile -> [Assignment] in
            places(of: profile).map { Assignment(profile: profile.name, place: $0) }
        }
    }

    /// The display and Space that switch to a profile, for its row, or
    /// "Manually or by shortcut" when neither is set.
    static func switches(of profile: ProfileMetadata) -> String {
        let places = places(of: profile)
        return places.isEmpty ? String(localized: "Manually or by shortcut") : places.joined(separator: " · ")
    }

    /// The display and then the Space that switch to a profile.
    private static func places(of profile: ProfileMetadata) -> [String] {
        var places = [String]()
        if profile.associatedDisplayUUID != nil {
            places.append(profile.associatedDisplayName ?? String(localized: "a display"))
        }
        if profile.associatedSpaceKey != nil {
            places.append(profile.associatedSpaceName ?? String(localized: "a Space"))
        }
        return places
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
