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
    /// Whether conditional placement can safely own this item.
    ///
    /// Some Apple menu extras interpret a synthetic Command-drag into an
    /// off-screen section as removal from the menu bar. For those items, the
    /// drag changes a macOS preference instead of merely changing Thaw's
    /// section membership. Keeping this policy on the tag makes the picker,
    /// planner, and final move preflight share one classification authority.
    enum TriggerTargetPolicy: Equatable {
        case supported
        case systemVisibilityPreferenceSensitive

        var supportsConditionalPlacement: Bool {
            self == .supported
        }
    }

    /// Items that must not be conditionally moved between Thaw sections on
    /// the synthetic-drag backend. Match by namespace and title so live
    /// instance-index changes do not bypass the protection.
    private static let preferenceSensitiveTriggerTargets: [MenuBarItemTag] = [
        .battery,
    ]

    /// The conditional-placement policy for this live tag.
    var triggerTargetPolicy: TriggerTargetPolicy {
        Self.preferenceSensitiveTriggerTargets.contains {
            $0.namespace == namespace && $0.title == title
        } ? .systemVisibilityPreferenceSensitive : .supported
    }

    /// Resolves the policy for a persisted trigger target. The captured base
    /// is authoritative when present; the legacy identifier fallback strips
    /// an instance suffix only against the small set of known protected bases,
    /// so a third-party title ending in `:1` cannot be misclassified.
    static func triggerTargetPolicy(
        for identifier: String,
        capturedBaseIdentifier: String? = nil
    ) -> TriggerTargetPolicy {
        let protectedBases = Set(preferenceSensitiveTriggerTargets.map(\.stableIdentifierBase))
        if let capturedBaseIdentifier,
           protectedBases.contains(capturedBaseIdentifier)
        {
            return .systemVisibilityPreferenceSensitive
        }
        if protectedBases.contains(identifier) {
            return .systemVisibilityPreferenceSensitive
        }
        if let resolvedBase = resolvedBaseIdentifier(
            for: identifier,
            knownBaseIdentifiers: protectedBases
        ), protectedBases.contains(resolvedBase) {
            return .systemVisibilityPreferenceSensitive
        }
        return .supported
    }

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
