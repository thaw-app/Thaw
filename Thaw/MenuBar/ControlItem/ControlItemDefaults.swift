//
//  ControlItemDefaults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

// MARK: - ControlItemDefaults

/// Wraps AppKit placement and visibility keys derived from autosaveName.
/// Persisted keys allow corrections across launches, even after a status item no longer exists.
nonisolated enum ControlItemDefaults {
    /// The key fragment AppKit uses for a status item's stored placement.
    fileprivate static let preferredPositionKeyName = "Preferred Position"

    /// Drop divider placement writes; persisted slots compete with relative positioning on each layout pass.
    static subscript<Value>(key: Key<Value>, autosaveName: String) -> Value? {
        get {
            UserDefaults.standard.object(forKey: key.stringKey(for: autosaveName)) as? Value
        }
        set {
            guard !(key.isPreferredPosition && isSectionDivider(autosaveName: autosaveName)) else {
                return
            }
            UserDefaults.standard.set(newValue, forKey: key.stringKey(for: autosaveName))
        }
    }

    /// Whether autosaveName identifies one of the two section dividers.
    static func isSectionDivider(autosaveName: String) -> Bool {
        autosaveName == ControlItem.Identifier.hidden.rawValue ||
            autosaveName == ControlItem.Identifier.alwaysHidden.rawValue
    }

    /// Moves the value stored for key from one autosave name to another,
    /// leaving nothing behind under the old name.
    static func migrate(key: Key<some Any>, from oldAutosaveName: String, to newAutosaveName: String) {
        guard newAutosaveName != oldAutosaveName else {
            return
        }
        Self[key, newAutosaveName] = Self[key, oldAutosaveName]
        Self[key, oldAutosaveName] = nil
    }

    /// Seed before registration, which reads defaults immediately to determine first appearance.
    static func prepareDefaults(for identifier: ControlItem.Identifier) {
        let autosaveName = identifier.rawValue

        // The Thaw icon carries no seeded placement: it only needs its
        // visibility flags reasserted before it is published.
        guard identifier != .visible else {
            restoreVisibilityIfNeeded(autosaveName: autosaveName)
            return
        }

        // Request the trailing group's leading slot; the subscript intentionally drops divider placement writes.
        if identifier == .hidden {
            Self[.preferredPosition, autosaveName] = 1
        }

        // Default new controls to published; their length determines subsequent visibility.
        if Self[.visible, autosaveName] == nil {
            Self[.visible, autosaveName] = true
        }
        if Self[.visibleCC, autosaveName] == nil {
            Self[.visibleCC, autosaveName] = true
        }

        restoreVisibilityIfNeeded(autosaveName: autosaveName)
    }

    /// Keep the icon and hidden divider published; length and alpha control their appearance.
    /// VisibleCC = 0 prevents AppKit publication, which later appearance updates cannot repair.
    static func restoreVisibilityIfNeeded(autosaveName: String) {
        switch autosaveName {
        case ControlItem.Identifier.visible.rawValue:
            markPublished(autosaveName: autosaveName)
            // A non-positive stored placement is discarded rather than trusted,
            // which hands placement of the icon back to the system.
            if let position = Self[.preferredPosition, autosaveName], position <= 0 {
                Self[.preferredPosition, autosaveName] = nil
            }
        case ControlItem.Identifier.hidden.rawValue:
            markPublished(autosaveName: autosaveName)
        default:
            break
        }
    }

    private static func markPublished(autosaveName: String) {
        Self[.visible, autosaveName] = true
        Self[.visibleCC, autosaveName] = true
    }
}

// MARK: - ControlItemDefaults.Key

nonisolated extension ControlItemDefaults {
    /// A typed name for one of AppKit's per-status-item preferences.
    nonisolated struct Key<Value> {
        /// The portion of the defaults key that names the preference itself.
        let rawValue: String

        /// Whether this key names a status item's stored placement.
        var isPreferredPosition: Bool {
            rawValue == ControlItemDefaults.preferredPositionKeyName
        }

        /// The full defaults key this preference occupies for autosaveName.
        func stringKey(for autosaveName: String) -> String {
            "NSStatusItem \(rawValue) \(autosaveName)"
        }
    }
}

// MARK: ControlItemDefaults.Key<CGFloat>

nonisolated extension ControlItemDefaults.Key<CGFloat> {
    /// String key: "NSStatusItem Preferred Position autosaveName"
    static let preferredPosition = Self(rawValue: ControlItemDefaults.preferredPositionKeyName)
}

// MARK: ControlItemDefaults.Key<Bool>

nonisolated extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
