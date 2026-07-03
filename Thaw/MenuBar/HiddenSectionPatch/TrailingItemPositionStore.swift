//
//  TrailingItemPositionStore.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Reads and writes `TrailingItemPreferredPositions` in
/// `com.apple.MenuBarAgent`'s preferences domain.
///
/// On macOS 27 there are no per-item CG windows and AX attributes like
/// `AXHidden` or `AXAlternateUIVisible` are unsupported on menu-bar items
/// (confirmed via AX probe). The only per-item control surface that remains
/// is the position-preference dictionary `TrailingItemPreferredPositions`,
/// used to manage item ordering and, experimentally, visibility.
///
/// This store provides both the position-lock (preserve visible-item weights
/// before assertion reflow) and an experimental plist-based hide/show path
/// (remove/restore keys for per-item visibility control).
@MainActor
final class TrailingItemPositionStore {
    private static let agentDomain = "com.apple.MenuBarAgent" as CFString
    private static let positionKey = "TrailingItemPreferredPositions"
    private static let diagLog = DiagLog(category: "TrailingItemPos")

    /// Injectable side effects, so tests can drive an in-memory dictionary
    /// instead of the real `com.apple.MenuBarAgent` preferences domain.
    @MainActor
    struct Environment {
        let readPositions: @MainActor () -> [String: Int]
        let writePositions: @MainActor ([String: Int]) -> Void

        static var live: Environment {
            Environment(
                readPositions: { TrailingItemPositionStore.readPositionsFromSystem() },
                writePositions: { TrailingItemPositionStore.writePositionsToSystem($0) }
            )
        }
    }

    /// The unmodified position dictionary at lock-time, before we pin visible
    /// items at their current positions. Restored when locking stops.
    private var originalPositions: [String: Int]?

    /// Plist keys currently removed by this store to hide items, along with
    /// the weight they held before removal. Presence here means "hidden via
    /// plist". Keyed by the stable plist key (not Thaw's uniqueIdentifier).
    private var hiddenPlistKeys: [String: Int] = [:]

    private let environment: Environment
    private var terminationObserver: NSObjectProtocol?

    init(environment: Environment = .live, notificationCenter: NotificationCenter = .default) {
        self.environment = environment
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreAll()
            }
        }
    }

    isolated deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    /// Writes the current on-screen position of each visible item so
    /// MenuBarAgent anchors them in place during the assertion reflow. Call
    /// before every assertion apply/pulse while the experimental flag is on.
    ///
    /// Any item previously locked that is no longer visible gets restored to
    /// its original position (or its key removed).
    ///
    /// - Parameters:
    ///   - visibleItemKeys: `TrailingItemPreferredPositions` keys for items
    ///     that should stay anchored.
    ///   - allItems: The full live item list, used to read current positions.
    @discardableResult
    func lockVisiblePositions(visibleItemKeys _: Set<String>, allItems: [MenuBarItem]) -> Set<String> {
        var positions = environment.readPositions()
        let isFirstApply = originalPositions == nil
        if isFirstApply {
            originalPositions = positions
        }

        let existingKeys = Array(positions.keys)

        // Resolve each live item to its key in the current dictionary.
        // The naive key `status:<namespace>::<title>` uses the AX title,
        // which changes every second for apps like iStat Menus. Those apps
        // register under a stable internal identifier instead, so we must
        // resolve via the same positional heuristic MenuBarAgentPositionStore
        // uses — otherwise we create a new ghost key on every tick that
        // accumulates indefinitely and scrambles the ordering.
        var liveResolvedKeys = Set<String>()
        for item in allItems {
            if let resolved = Self.resolvedPositionKey(
                for: item,
                existingKeys: existingKeys
            ) {
                liveResolvedKeys.insert(resolved)
            } else {
                // Title-based resolution failed (dynamic-title item like iStat).
                // Fall back to the positional heuristic: match items to keys
                // by their left-to-right order within the owning app's family.
                if let positional = Self.resolvePositionalKey(
                    for: item,
                    existingKeys: existingKeys,
                    positions: positions,
                    allItems: allItems
                ) {
                    liveResolvedKeys.insert(positional)
                }
            }
        }

        // Remove any key in the dictionary that does not match a live item.
        // This cleans up ghost entries from previous ticks (e.g. stale iStat
        // keys from prior title values), preventing the dictionary from
        // growing with dead keys that MenuBarAgent may still interpret.
        //
        // Exception: keys belonging to denylisted hiding-unsupported apps are
        // NEVER removed. Volatile title churn makes exact key matching
        // unreliable, and removing their entries from the plist can cause
        // MenuBarAgent to drop them from the bar entirely.
        var changed = false
        for key in positions.keys where !liveResolvedKeys.contains(key) {
            let isHidingUnsupported = MenuBarItemTag.hidingUnsupportedBundleIDs.contains { bundleID in
                key.hasPrefix("status:\(bundleID)::")
            }
            if isHidingUnsupported {
                Self.diagLog.debug("lock: skipping removal of denylisted hiding-unsupported key \(key)")
                continue
            }
            positions.removeValue(forKey: key)
            changed = true
        }

        guard changed else { return liveResolvedKeys }

        environment.writePositions(positions)

        let removedCount = (originalPositions?.count ?? positions.count) - positions.count
        Self.diagLog.info(
            "lock: \(positions.count) keys after cleanup (removed \(removedCount) ghost(s)), " +
                "preserving existing weight order"
        )
        return liveResolvedKeys
    }

    /// Restores all positions to their original values.
    func restoreAll() {
        guard let saved = originalPositions else { return }
        environment.writePositions(saved)
        Self.diagLog.info("restoreAll: restored \(saved.count) position(s)")
        originalPositions = nil
        // Also restore any items hidden via the plist path.
        restoreAllHiddenItems()
    }

    // MARK: Plist-based hide/show (experimental)

    /// Hides items by removing their keys from the position plist. This is
    /// per-item and has no per-bundle collateral damage — experimental on
    /// macOS 27 where the assertion is the primary visibility mechanism.
    ///
    /// Items whose owning bundle is in ``MenuBarItemTag/hidingUnsupportedBundleIDs``
    /// are silently skipped — they can be reordered but never hidden.
    ///
    /// - Returns: The set of plist keys that were removed.
    @discardableResult
    func hideItems(_ items: [MenuBarItem]) -> Set<String> {
        var positions = environment.readPositions()
        let existingKeys = Array(positions.keys)
        var removed = Set<String>()

        for item in items {
            guard !item.tag.isHidingUnsupported,
                  !MenuBarItemTag.hidingUnsupportedBundleIDs.contains(where: {
                      item.tag.namespace.description == $0
                  })
            else {
                Self.diagLog.debug("hideItems: skipping unsupported \(item.uniqueIdentifier)")
                continue
            }

            guard let plistKey = Self.resolvedPositionKey(
                for: item,
                existingKeys: existingKeys
            ) ?? Self.resolvePositionalKey(
                for: item,
                existingKeys: existingKeys,
                positions: positions,
                allItems: items
            )
            else {
                Self.diagLog.debug("hideItems: no plist key for \(item.uniqueIdentifier)")
                continue
            }

            guard let weight = positions[plistKey] else { continue }

            hiddenPlistKeys[plistKey] = weight
            positions.removeValue(forKey: plistKey)
            removed.insert(plistKey)
            Self.diagLog.debug("hideItems: removed \(plistKey) (weight=\(weight))")
        }

        guard !removed.isEmpty else { return [] }

        environment.writePositions(positions)
        Self.diagLog.info("hideItems: removed \(removed.count) key(s) from plist")
        return removed
    }

    /// Shows previously-hidden items by restoring their keys to the position
    /// plist with weights that preserve the visual ordering. Items that are
    /// not in the hidden set are silently skipped.
    ///
    /// - Parameters:
    ///   - items: The items to show (only those previously hidden are restored).
    ///   - allItems: The full live item list, used to compute neighbor weights.
    /// - Returns: The set of plist keys that were restored.
    @discardableResult
    func showItems(_ items: [MenuBarItem], allItems: [MenuBarItem]) -> Set<String> {
        guard !hiddenPlistKeys.isEmpty else { return [] }

        var positions = environment.readPositions()
        let existingKeys = Array(positions.keys)
        var restored = Set<String>()

        for item in items {
            guard let plistKey = Self.resolvedPositionKey(
                for: item,
                existingKeys: existingKeys
            ) ?? Self.resolvePositionalKey(
                for: item,
                existingKeys: existingKeys,
                positions: positions,
                allItems: allItems
            )
            else { continue }

            guard let savedWeight = hiddenPlistKeys[plistKey] ?? hiddenPlistKeys.first(where: {
                Self.keysReferToSameApp($0.key, plistKey)
            })?.value
            else { continue }

            // Compute a weight that places the item between its visual neighbors.
            let weight = Self.computeRestoreWeight(
                for: item,
                savedWeight: savedWeight,
                existingKeys: existingKeys,
                positions: positions,
                allItems: allItems
            )

            positions[plistKey] = weight
            hiddenPlistKeys.removeValue(forKey: plistKey)
            restored.insert(plistKey)
            Self.diagLog.debug("showItems: restored \(plistKey) (weight=\(weight))")
        }

        guard !restored.isEmpty else { return [] }

        environment.writePositions(positions)
        Self.diagLog.info("showItems: restored \(restored.count) key(s) to plist")
        return restored
    }

    /// Whether any items are currently hidden via the plist path.
    var hasHiddenItems: Bool {
        !hiddenPlistKeys.isEmpty
    }

    /// Restores all items hidden via the plist path.
    private func restoreAllHiddenItems() {
        guard !hiddenPlistKeys.isEmpty else { return }
        var positions = environment.readPositions()
        for (key, weight) in hiddenPlistKeys {
            positions[key] = weight
        }
        environment.writePositions(positions)
        Self.diagLog.info("restoreAllHiddenItems: restored \(hiddenPlistKeys.count) key(s)")
        hiddenPlistKeys.removeAll()
    }

    /// Computes a weight for a restored item that places it between its
    /// left and right visual neighbors in the live menu bar.
    static func computeRestoreWeight(
        for item: MenuBarItem,
        savedWeight: Int,
        existingKeys: [String],
        positions: [String: Int],
        allItems: [MenuBarItem]
    ) -> Int {
        let visible = allItems
            .filter { $0.isOnScreen && !$0.isSystemClone }
            .sorted { $0.bounds.midX < $1.bounds.midX }

        guard let itemIndex = visible.firstIndex(where: {
            $0.tag.matchesIgnoringWindowID(item.tag)
        }) else {
            return savedWeight
        }

        // Find the nearest neighboring weights on each side.
        var leftWeight: Int?
        var rightWeight: Int?
        for neighbor in visible[..<itemIndex].reversed() {
            if let key = Self.resolvedPositionKey(for: neighbor, existingKeys: existingKeys),
               let weight = positions[key]
            {
                leftWeight = weight
                break
            }
        }
        for neighbor in visible[(itemIndex + 1)...] {
            if let key = Self.resolvedPositionKey(for: neighbor, existingKeys: existingKeys),
               let weight = positions[key]
            {
                rightWeight = weight
                break
            }
        }

        switch (leftWeight, rightWeight) {
        case let (.some(lo), .some(hi)):
            let mid = lo + (hi - lo) / 2
            return mid != lo && mid != hi ? mid : savedWeight
        case let (.some(lo), .none):
            return lo + 10
        case let (.none, .some(hi)):
            return hi - 10
        case (.none, .none):
            return savedWeight
        }
    }

    /// Whether two plist keys refer to the same owning app (same namespace
    /// prefix), used as a fallback when the exact key doesn't match.
    private static func keysReferToSameApp(_ a: String, _ b: String) -> Bool {
        let aPrefix = a.hasPrefix("status:") ? String(a.dropFirst("status:".count).prefix(while: { $0 != ":" })) : ""
        let bPrefix = b.hasPrefix("status:") ? String(b.dropFirst("status:".count).prefix(while: { $0 != ":" })) : ""
        return !aPrefix.isEmpty && aPrefix == bPrefix
    }

    /// Builds the `TrailingItemPreferredPositions` key for a menu-bar item.
    /// Format: `status:{bundleID}::{title}`
    static func key(for item: MenuBarItem) -> String {
        "status:\(item.tag.namespace)::\(item.tag.title)"
    }

    /// Resolves a live item to its existing key in the
    /// `TrailingItemPreferredPositions` dictionary.
    ///
    /// Three key shapes appear in the dictionary (documented in
    /// ``MenuBarAgentPositionStore/resolveKey(for:existingKeys:positions:liveItems:)``):
    ///   * `module:<title>` — Apple Control Center modules
    ///   * `status:<bundleID>::<itemID>` — third-party items
    ///   * `status:<AppDisplayName>::<itemID>` — display-name form
    ///
    /// For apps like iStat Menus that rewrite their AX title every second,
    /// none of the title-based tiers match. In that case we fall back to the
    /// positional heuristic: match the item by its sibling order within the
    /// owning app's key family.
    static func resolvedPositionKey(
        for item: MenuBarItem,
        existingKeys: [String]
    ) -> String? {
        let title = item.tag.title
        guard !title.isEmpty else { return nil }

        // 1. Apple module (`module:Clock`, `module:WiFi`, etc.).
        if item.tag.namespace.isMenuBarHostingNamespace {
            let moduleKey = "module:\(title)"
            if existingKeys.contains(moduleKey) {
                return moduleKey
            }
        }

        // 2. Exact bundle-ID form: `status:<namespace>::<title>`.
        let naiveKey = key(for: item)
        if existingKeys.contains(naiveKey) {
            return naiveKey
        }

        // 3. Display-name form: suffix-match `::<title>`.
        let suffix = "::\(title)"
        let candidates = existingKeys.filter { $0.hasPrefix("status:") && $0.hasSuffix(suffix) }
        if candidates.count == 1 {
            return candidates[0]
        }
        if candidates.count > 1 {
            let displayPrefixes = candidateDisplayNamePrefixes(for: item)
            for key in candidates {
                let middle = key.dropFirst("status:".count).dropLast(suffix.count)
                if displayPrefixes.contains(String(middle)) {
                    return key
                }
            }
        }

        // No title-based match — item uses a stable internal identifier
        // (e.g. iStat Menus). Without `positions` and `liveItems` (the full
        // positional fallback) we cannot disambiguate; return nil so the
        // caller can use the full `MenuBarAgentPositionStore.resolveKey`
        // when available.
        return nil
    }

    /// Display-name prefixes MenuBarAgent might use for the item's owning app.
    private static func candidateDisplayNamePrefixes(for item: MenuBarItem) -> Set<String> {
        var names = Set<String>()
        if let localized = item.sourceApplication?.localizedName {
            names.insert(localized)
        }
        names.insert(item.displayName)
        return names
    }

    /// Resolves a live item to its key in the dictionary by matching its
    /// left-to-right position within the owning app's family of items against
    /// the same app's family of keys (ordered by weight).
    ///
    /// This is the last-resort fallback for apps like iStat Menus that register
    /// under a stable internal identifier that never appears in the live AX
    /// title. Requires the family sizes to match exactly so we can pair
    /// siblings without guessing.
    static func resolvePositionalKey(
        for item: MenuBarItem,
        existingKeys: [String],
        positions: [String: Int],
        allItems: [MenuBarItem]
    ) -> String? {
        let family = allItems
            .filter { !$0.isSystemClone && $0.tag.namespace == item.tag.namespace }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        guard
            family.count > 1,
            let itemIndex = family.firstIndex(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        else {
            return nil
        }

        var familyKeys = existingKeys.filter { $0.hasPrefix("status:\(item.tag.namespace.description)::") }
        if familyKeys.count != family.count {
            let displayPrefixes = candidateDisplayNamePrefixes(for: item).map { "status:\($0)::" }
            familyKeys = existingKeys.filter { key in displayPrefixes.contains { key.hasPrefix($0) } }
        }
        guard familyKeys.count == family.count else { return nil }

        let orderedKeys = familyKeys.sorted { (positions[$0] ?? 0) < (positions[$1] ?? 0) }
        return orderedKeys[itemIndex]
    }

    // MARK: Private

    /// Reads the live positions dictionary. Delegates to ``environment``, so
    /// tests can substitute an in-memory dictionary; production callers get
    /// ``readPositionsFromSystem()`` via ``Environment/live``.
    func readPositions() -> [String: Int] {
        environment.readPositions()
    }

    /// Writes the positions dictionary. Delegates to ``environment``, so
    /// tests can substitute an in-memory dictionary; production callers get
    /// ``writePositionsToSystem(_:)`` via ``Environment/live``.
    func writePositions(_ dict: [String: Int]) {
        environment.writePositions(dict)
    }

    /// The real `com.apple.MenuBarAgent` preferences read, used by
    /// ``Environment/live``.
    static func readPositionsFromSystem() -> [String: Int] {
        // Try CFPreferences with AnyHost first (matches `defaults read`).
        if let dict = CFPreferencesCopyValue(
            positionKey as CFString,
            agentDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Int] {
            return dict
        }
        // Fallback: read the plist file directly.
        let plistPath = ("~/Library/Preferences/\(Self.agentDomain as String).plist" as NSString).expandingTildeInPath
        if let plist = NSDictionary(contentsOfFile: plistPath),
           let dict = plist[Self.positionKey] as? [String: Int]
        {
            Self.diagLog.debug("readPositions: read \(dict.count) entries from plist file")
            return dict
        }
        // Also try CurrentHost as last resort.
        if let dict = CFPreferencesCopyValue(
            Self.positionKey as CFString,
            Self.agentDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String: Int] {
            return dict
        }
        Self.diagLog.debug("readPositions: no existing dict, starting empty")
        return [:]
    }

    /// The real `com.apple.MenuBarAgent` preferences write, used by
    /// ``Environment/live``.
    static func writePositionsToSystem(_ dict: [String: Int]) {
        // CFPreferences path.
        CFPreferencesSetValue(
            positionKey as CFString,
            dict as CFPropertyList,
            agentDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let synced = CFPreferencesSynchronize(
            Self.agentDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        // Direct plist write fallback so MenuBarAgent sees the change even
        // if CFPreferences sync doesn't propagate cross-process.
        guard !synced else { return }

        let plistPath = ("~/Library/Preferences/\(Self.agentDomain as String).plist" as NSString).expandingTildeInPath
        let plist = (NSMutableDictionary(contentsOfFile: plistPath) as NSMutableDictionary?) ?? NSMutableDictionary()
        plist[Self.positionKey] = dict
        plist.write(toFile: plistPath, atomically: true)
        Self.diagLog.warning("writePositions: CFPreferencesSynchronize failed; used direct plist fallback")
    }
}
