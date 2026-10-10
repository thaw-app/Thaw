//
//  MenuBarItemDisplayName.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import MenuBarModel

// MARK: - MenuBarItemDisplayName

/// Memoized access to MenuBarItem.displayName for call sites that re-run
/// frequently, in particular SwiftUI view bodies and NSViewRepresentable
/// update hooks.
///
/// MenuBarItem.displayName resolves the owning process through
/// NSRunningApplication(processIdentifier:), which returns a fresh object on
/// every call, and then reads localizedName/bundleIdentifier off it. Both
/// halves allocate. From a continuously re-evaluating SwiftUI body that
/// allocates faster than the autorelease pool drains, so memory grows without
/// bound (the same problem as OverflowFallbackIcon.cachedAppIcon(forPID:)).
///
/// The cache is keyed by MenuBarItem.uniqueIdentifier
/// ("namespace:canonicalTitle[:instanceIndex]"), which is stable across
/// window-ID changes and relaunches and distinct per item. A size cap guards
/// against title churn (a clock showing seconds mints a new identifier every
/// tick); when it is hit the cache is cleared and refilled lazily.
///
/// Only the auto-detected half of the name is cached, a name the user typed
/// is resolved on every call. See displayName(for:) for why.
@MainActor
enum MenuBarItemDisplayName {
    /// Names resolved without a custom name in play, the spacer name or the
    /// auto-detected one, keyed by MenuBarItem.uniqueIdentifier.
    private static var cache: [String: String] = [:]

    /// Upper bound on entry count, so a rapidly changing status item title
    /// cannot grow the cache without limit or pin a long tail of stale
    /// entries.
    private static let maxCacheSize = 256

    /// The item's display name: the name the user gave it if there is one,
    /// otherwise a name resolved once per MenuBarItem.uniqueIdentifier
    /// and reused thereafter.
    ///
    /// Callers rendering item names in SwiftUI bodies or NSViewRepresentable
    /// update hooks should come through here rather than reading
    /// item.displayName directly, see the type overview for what that
    /// costs inside a re-evaluating body.
    static func displayName(for item: MenuBarItem) -> String {
        // A user rename changes the name without moving the key, so the
        // custom name is read back on each call instead of cached. It is only
        // a dictionary lookup.
        if let custom = item.customName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }

        let key = item.uniqueIdentifier
        if let cached = cache[key] {
            return cached
        }
        // No custom name is set, so this resolves to the spacer or the
        // auto-detected name: the expensive half, and the stable one.
        let resolved = item.displayName
        if cache.count >= maxCacheSize {
            cache.removeAll()
        }
        cache[key] = resolved
        return resolved
    }

    /// Owning-app names, keyed the same way as cache. Only successful
    /// resolutions are stored: a PID that resolves to nothing costs a failed
    /// lookup rather than an allocation, and caching the miss would pin an
    /// item to "no owner" for the rest of the session if its app launched
    /// late.
    private static var ownerCache: [String: String] = [:]

    /// The name of the app the item really belongs to, or nil when its
    /// creating process cannot be resolved.
    ///
    /// sourcePID is preferred because on macOS 26+ every hosted extra reports
    /// Control Center as its owner, which would name every row identically.
    static func ownerName(for item: MenuBarItem) -> String? {
        let key = item.uniqueIdentifier
        if let cached = ownerCache[key] {
            return cached
        }
        let pid = item.sourcePID ?? item.ownerPID
        guard let resolved = NSRunningApplication(processIdentifier: pid)?.localizedName,
              !resolved.isEmpty
        else {
            return nil
        }
        if ownerCache.count >= maxCacheSize {
            ownerCache.removeAll()
        }
        ownerCache[key] = resolved
        return resolved
    }

    /// The owning app's name, when it says something the item's own name
    /// doesn't.
    ///
    /// Every surface that shows a name over its owner (the launcher rows, the
    /// layout editor's inspector) uses this, so they agree on when the second
    /// line would only repeat the first.
    static func subtitle(for item: MenuBarItem) -> String? {
        guard let owner = ownerName(for: item), owner != displayName(for: item) else {
            return nil
        }
        return owner
    }

    /// Drops every cached name.
    ///
    /// Provided for tests and for callers that know the underlying
    /// MenuBarItem population has changed identity (e.g. a profile switch
    /// that re-derives namespaces). Routine cleanup is handled by the size
    /// cap; this is an escape hatch.
    static func clear() {
        cache.removeAll()
        ownerCache.removeAll()
    }
}
