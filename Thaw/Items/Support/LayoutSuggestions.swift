//
//  LayoutSuggestions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import PlatformRuntimeKit

/// Notch suggestions can be evaluated without a live menu bar.
nonisolated enum LayoutSuggestions {
    /// Visible items a notch covers, per MenuBarNotchGeometry.
    static func itemsBehindNotch(_ visibleItems: [MenuBarItem], notchRects: [CGRect]) -> [MenuBarItem] {
        visibleItems.filter { item in
            !item.isControlItem && item.isOnScreen && MenuBarNotchGeometry.isOccluded(item, by: notchRects)
        }
    }

    /// Little Snitch's menu bar agent. Its icon is only enumerable while Little Snitch allows GUI scripting.
    static let littleSnitchAgentBundleID = "at.obdev.littlesnitch.agent"

    /// The app whose settings hold the GUI Scripting switch.
    static let littleSnitchAppBundleID = "at.obdev.littlesnitch"

    /// Whether Little Snitch is running while none of its items was enumerated.
    /// An empty inventory proves nothing, so it never reports.
    static func littleSnitchItemIsMissing(runningBundleIDs: Set<String>, items: [MenuBarItem]) -> Bool {
        guard runningBundleIDs.contains(littleSnitchAgentBundleID), !items.isEmpty else { return false }
        return !items.contains { "\($0.tag.namespace)" == littleSnitchAgentBundleID }
    }

    /// A short, locale-formatted list of names, with "and N more" past three.
    @MainActor
    static func names(of items: [MenuBarItem]) -> String {
        let names = items.map { MenuBarItemDisplayName.displayName(for: $0) }
        guard names.count > 3 else {
            return names.formatted(.list(type: .and))
        }
        // The count is the list's last entry, so the locale joins it like
        // any other name: "A, B, C and 2 more".
        let more = String(localized: "\(names.count - 3) more", comment: "Last entry of a shortened list of menu bar item names")
        return (Array(names.prefix(3)) + [more]).formatted(.list(type: .and))
    }
}

/// When the user last dismissed a suggestion, so "Not Now" holds for a
/// while instead of returning on the next visit.
@MainActor
enum LayoutSuggestionDismissal {
    enum Kind: String {
        case itemsBehindNotch
        case littleSnitchScriptingAccess
    }

    /// How long a dismissal holds.
    static let quietInterval: TimeInterval = 30 * 24 * 60 * 60

    private static func key(_ kind: Kind) -> String {
        "LayoutSuggestions.dismissed.\(kind.rawValue)"
    }

    static func isQuiet(_ kind: Kind, now: Date = .now) -> Bool {
        guard let date = UserDefaults.standard.object(forKey: key(kind)) as? Date else { return false }
        return now.timeIntervalSince(date) < quietInterval
    }

    static func dismiss(_ kind: Kind) {
        UserDefaults.standard.set(Date.now, forKey: key(kind))
    }
}
