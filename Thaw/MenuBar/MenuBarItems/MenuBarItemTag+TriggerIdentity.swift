//
//  MenuBarItemTag+TriggerIdentity.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Instance-independent tag identity used by conditional triggers.
///
/// A trigger targets an *item*, not a particular live instance of it, so its
/// stored target must survive an instance-index change (which happens when a
/// same-titled sibling comes or goes). ``tagIdentifier`` cannot serve that
/// role because it folds the instance index into the string.
nonisolated extension MenuBarItemTag {
    /// The exact namespace-and-title identity for this live tag. Unlike the
    /// persisted string form, it is never ambiguous when a title ends in a
    /// colon followed by a number.
    var stableIdentifierBase: String {
        "\(namespace):\(title)"
    }

    /// Resolves a persisted identifier to a base only when live tag data makes
    /// the instance suffix unambiguous. String identifiers use the legacy
    /// `namespace:title[:index]` form, and titles are free-form; blindly
    /// stripping a numeric suffix could turn the title "Meeting:30" into the
    /// unrelated item "Meeting".
    static func resolvedBaseIdentifier(
        for uniqueIdentifier: String,
        knownBaseIdentifiers: Set<String>
    ) -> String? {
        if knownBaseIdentifiers.contains(uniqueIdentifier) {
            return uniqueIdentifier
        }
        guard
            let suffixStart = uniqueIdentifier.lastIndex(of: ":"),
            let instanceIndex = Int(uniqueIdentifier[uniqueIdentifier.index(after: suffixStart)...]),
            // Current tags omit the zero suffix, but older persisted layouts
            // may contain an explicit `:0`. Once the live namespace/title
            // base is known, both forms identify that same first instance.
            instanceIndex >= 0,
            knownBaseIdentifiers.contains(String(uniqueIdentifier[..<suffixStart]))
        else {
            return nil
        }
        return String(uniqueIdentifier[..<suffixStart])
    }
}
