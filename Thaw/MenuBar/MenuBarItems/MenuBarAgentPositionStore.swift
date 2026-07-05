//
//  MenuBarAgentPositionStore.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Reorders menu bar items on macOS 27 by writing MenuBarAgent's own layout
/// preference instead of synthesizing a Command-drag.
///
/// macOS 27 hosts every status item inside `com.apple.MenuBarAgent` and records
/// the bar's left-to-right arrangement in a single preference value:
///
///     com.apple.MenuBarAgent → TrailingItemPreferredPositions : { key → Int }
///
/// (current-user / **any-host**; read it with `defaults read com.apple.MenuBarAgent`,
/// *not* `-currentHost`). Each key is one of:
///
///   * `module:<Name>`        — Apple Control Center modules (`module:WiFi`,
///                              `module:Clock` = 0, `module:BentoBox-0` = 88, …).
///   * `status:<App>::<ItemID>` — third-party status items, where `<App>` is the
///                              owning app's display name and `<ItemID>` is the
///                              status item's identifier (`status:Codex::Item-0`,
///                              `status:Hidden Bar::hiddenbar_expandcollapse`, …).
///
/// The integer is a sort weight; MenuBarAgent lays the bar out by ordering the
/// keys by that weight. Rewriting a key's weight and nudging the agent to
/// re-read therefore moves the item **without touching the cursor** — the
/// cursor-warp-free reorder path.
///
/// This store performs a *minimal* relative move: it reassigns only the moved
/// item's weight to the midpoint between its destination's two live neighbors,
/// so system anchors (Clock, Control Center) and unrelated items keep their
/// existing weights. The midpoint sorts between the neighbors regardless of
/// whether the global weight axis increases left-to-right or right-to-left, so
/// the store never has to assume a sign for the axis.
///
/// **Empirically uncertain** (validated at runtime by the caller, which falls
/// back to the synthetic ⌘-drag when a move does not verify): the exact
/// `status:` key spelling for a given third-party item, and whether a bare
/// write+synchronize is enough to make the agent re-lay-out without a restart.
/// The live environment plays it safe and SIGTERMs MenuBarAgent (a managed
/// launch agent that relaunches itself within ~1-2 s), mirroring how
/// ``ControlCenterModuleManager`` relaunches Control Center.
@available(macOS 27, *)
@MainActor
enum MenuBarAgentPositionStore {
    private static let diagLog = DiagLog(category: "MenuBarAgentPositionStore")

    private static let domain = "com.apple.MenuBarAgent" as CFString
    private static let positionsKey = "TrailingItemPreferredPositions" as CFString
    private static let agentBundleID = "com.apple.MenuBarAgent"

    // MARK: Environment

    /// Injectable side effects, so tests can drive an in-memory dictionary
    /// instead of the real preference domain and process table.
    @MainActor
    struct Environment {
        let readPositions: @MainActor () -> [String: Int]
        let writePositions: @MainActor ([String: Int]) -> Void
        let nudgeAgent: @MainActor () -> Void

        static var live: Environment {
            Environment(
                readPositions: { MenuBarAgentPositionStore.readPositions() },
                writePositions: { MenuBarAgentPositionStore.writePositions($0) },
                nudgeAgent: { MenuBarAgentPositionStore.nudgeAgent() }
            )
        }
    }

    // MARK: Orchestration

    /// Attempts to move `item` to `destination` by rewriting its preferred
    /// position. Returns `true` when a new weight was written and the agent
    /// nudged; `false` when the move could not be expressed as a position
    /// write (unresolved key, no numeric gap, or an end placement), so the
    /// caller should fall back to the synthetic drag.
    ///
    /// The caller is responsible for re-enumerating and verifying the order
    /// after this returns `true`; this method does not block on the agent
    /// re-laying-out.
    @discardableResult
    static func move(
        item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool = false,
        environment: Environment = .live
    ) -> Bool {
        guard item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) else {
            return false
        }

        let positions = environment.readPositions()
        let keys = Array(positions.keys)

        guard let movedKey = resolveKey(for: item, existingKeys: keys, positions: positions, liveItems: liveItems) else {
            diagLog.debug("No MenuBarAgent key for \(item.logString); deferring to synthetic drag")
            return false
        }

        // Pick the two live neighbors that bracket the drop slot, computed from
        // the observed left-to-right visual order with the moved item removed.
        guard let neighbors = neighborItems(
            forMoving: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) else {
            return false
        }

        guard
            let anchorKey = resolveKey(for: neighbors.anchor, existingKeys: keys, positions: positions, liveItems: liveItems),
            let anchorValue = positions[anchorKey]
        else {
            return false
        }

        // The far neighbor may be absent (the anchor sits at the end of the
        // movable run). For end placements, compute an offset weight from the
        // anchor rather than deferring to the synthetic drag.
        let farValue: Int
        if let farNeighbor = neighbors.far,
           let farKey = resolveKey(for: farNeighbor, existingKeys: keys, positions: positions, liveItems: liveItems),
           let value = positions[farKey]
        {
            farValue = value
        } else {
            // End placement: step 10 units outward from the anchor.
            farValue = anchorValue + (destination.isRightward ? 20 : -20)
            diagLog.debug("End placement for \(item.logString); computing offset from anchor=\(anchorValue) to far=\(farValue)")
        }

        let newValue: Int
        if let midpoint = midpointPosition(between: anchorValue, and: farValue) {
            newValue = midpoint
        } else {
            diagLog.debug(
                "No numeric gap between \(anchorKey)=\(anchorValue) and far=\(farValue); deferring synthetic drag"
            )
            return false
        }

        var updated = positions
        updated[movedKey] = newValue
        environment.writePositions(updated)
        environment.nudgeAgent()
        diagLog.info("Wrote \(movedKey)=\(newValue) (between \(anchorValue) and \(farValue)) for \(destination.logString)")
        return true
    }

    // MARK: Batch order

    /// Reorders an entire section's items in one preference write instead of the
    /// per-pair, per-restart reconcile loop.
    ///
    /// `desiredOrder` is the section's target left-to-right sequence (item
    /// `uniqueIdentifier`s). The achievable arrangement is computed by
    /// ``LayoutPlanner/achievableOrderSegments(items:desiredOrder:)``, which
    /// partitions the bar at fixed system anchors and orders the movable items
    /// within each independent segment — so an impossible cross-anchor move is
    /// never attempted.
    ///
    /// Within each segment the solver **permutes the items' own existing
    /// weights**: it collects the current weights of the segment's resolvable
    /// items and reassigns them in the segment's direction so the items land in
    /// desired order. Reusing the segment's existing weight values (rather than
    /// inventing new ones) keeps every item between the same surrounding anchors
    /// by construction, sidestepping the anchored-item churn entirely. A
    /// segment's axis direction (whether a smaller weight sits left or right) is
    /// read from the items' current geometry, so a reversed axis self-corrects.
    ///
    /// Returns the `uniqueIdentifier`s whose weight changed (empty when the order
    /// already holds or nothing resolved). The single write + single nudge happen
    /// only when there is at least one change; the caller polls for the agent to
    /// re-sort and leaves any residual (unresolved items, reversed guesses) to
    /// the per-pair reconcile loop.
    @discardableResult
    static func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool = false,
        environment: Environment = .live
    ) -> [String] {
        guard desiredOrder.count > 1 else { return [] }

        let positions = environment.readPositions()
        let keys = Array(positions.keys)
        var updated = positions
        var changed = [String]()

        let segments = LayoutPlanner.achievableOrderSegments(
            items: liveItems,
            desiredOrder: desiredOrder,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )

        for segment in segments {
            // Resolvable items in this segment, paired with key + current weight,
            // kept in the segment's desired left-to-right order.
            let resolvable: [(item: MenuBarItem, key: String, weight: Int)] = segment.compactMap { item in
                guard
                    let key = resolveKey(for: item, existingKeys: keys, positions: positions, liveItems: liveItems),
                    let weight = positions[key]
                else { return nil }
                return (item, key, weight)
            }
            guard resolvable.count > 1 else { continue }

            // Slots = the segment's own weights. Assign them in the axis
            // direction inferred from current geometry: ascending slot values to
            // the desired sequence when smaller weights currently sit left.
            let slots = resolvable.map(\.weight).sorted()
            let assignment = ascendingAxis(for: resolvable.map { ($0.item, $0.weight) }) ? slots : slots.reversed()

            for (target, weight) in zip(resolvable, assignment) where target.weight != weight {
                updated[target.key] = weight
                changed.append(target.item.uniqueIdentifier)
            }
        }

        guard !changed.isEmpty else { return [] }

        environment.writePositions(updated)
        environment.nudgeAgent()
        diagLog.info("Batch-reordered \(changed.count) item(s) via preferred positions")
        return changed
    }

    /// Whether a weight axis ascends left-to-right (smaller weight = further
    /// left), read from the given items' current geometry. A flat or
    /// single-extent input defaults to ascending (the observed system default,
    /// e.g. Clock = 0 at the leading edge). The axis is a single global sort
    /// key shared by the whole bar, so this is valid whether the pairs come
    /// from one reorder segment (``applyOrder``) or from unrelated items
    /// scattered across the bar (``resolvePositionalKey``).
    private static func ascendingAxis(
        for pairs: [(item: MenuBarItem, weight: Int)]
    ) -> Bool {
        let byPosition = pairs.sorted { $0.item.bounds.midX < $1.item.bounds.midX }
        guard let leftmost = byPosition.first, let rightmost = byPosition.last,
              leftmost.weight != rightmost.weight
        else { return true }
        return leftmost.weight < rightmost.weight
    }

    // MARK: Pure planning

    /// The two live items that bracket the slot `item` is moving into: `anchor`
    /// is the destination's target, `far` is the item on the other side of the
    /// slot (nil when the anchor is at the end of the movable run). Computed
    /// with the moved item removed so its current position never skews the slot.
    static func neighborItems(
        forMoving item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool = false
    ) -> (anchor: MenuBarItem, far: MenuBarItem?)? {
        let ordered = liveItems
            .filter { !$0.isSystemClone }
            .filter { $0.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) }
            .filter { !$0.tag.matchesIgnoringWindowID(item.tag) }
            .sorted { $0.bounds.minX < $1.bounds.minX }

        let anchor = destination.targetItem
        guard let anchorIndex = ordered.firstIndex(where: {
            $0.tag.matchesIgnoringWindowID(anchor.tag)
        }) else {
            return nil
        }

        switch destination {
        case .leftOfItem:
            // Slot is between the anchor and its left neighbor.
            let far = anchorIndex > ordered.startIndex ? ordered[anchorIndex - 1] : nil
            return (ordered[anchorIndex], far)
        case .rightOfItem:
            // Slot is between the anchor and its right neighbor.
            let far = anchorIndex + 1 < ordered.endIndex ? ordered[anchorIndex + 1] : nil
            return (ordered[anchorIndex], far)
        }
    }

    /// Returns a weight that sorts strictly between `anchorValue` and
    /// `neighborValue`, or nil when no integer lies between them. Order-agnostic:
    /// the midpoint sorts between the two regardless of which is larger, so the
    /// caller never has to know whether the weight axis grows left or right.
    static func midpointPosition(between anchorValue: Int, and neighborValue: Int) -> Int? {
        let lo = min(anchorValue, neighborValue)
        let hi = max(anchorValue, neighborValue)
        guard hi - lo >= 2 else { return nil }
        return lo + (hi - lo) / 2
    }

    /// Resolves a live item to its existing key in the positions dictionary.
    ///
    /// Three key shapes appear in `TrailingItemPreferredPositions`:
    ///   * `module:<title>` — Apple Control Center modules.
    ///   * `status:<bundleID>::<itemID>` — the common third-party form, where
    ///     `<bundleID>` is the owning app's bundle identifier (== the item's
    ///     namespace) and `<itemID>` == Thaw's `tag.title` (both read the AX
    ///     identifier), e.g. `status:notion.id::Item-0`.
    ///   * `status:<AppDisplayName>::<itemID>` — the minority form used by apps
    ///     that register a display name (e.g. `status:iStat Menus Menubar::…`).
    ///
    /// Resolution tries them in that order. The bundle-ID form is exact, so it
    /// is preferred over the suffix match, which for generic `Item-0` titles has
    /// dozens of candidates that only the owning app's display name disambiguates.
    ///
    /// `positions` and `liveItems` are only consulted by the positional
    /// fallback below; omit them to use the title-only tiers (e.g. from tests).
    static func resolveKey(
        for item: MenuBarItem,
        existingKeys: [String],
        positions: [String: Int] = [:],
        liveItems: [MenuBarItem] = []
    ) -> String? {
        if let key = titleTierKey(for: item, existingKeys: existingKeys) {
            return key
        }

        // Every title-based tier failed outright. Apps like iStat Menus rewrite
        // their item's AX title every second ("CPU 10%" → "CPU 9%" → …), but
        // register their MenuBarAgent key under a stable internal identifier
        // instead (e.g. "com.bjango.istatmenus.cpu") that never appears in the
        // live title, so no title-based tier can ever match it. When the item
        // has sibling items from the same owning app, the bar's left-to-right
        // order is the last stable signal: pair the Nth sibling by X position
        // with the Nth sibling key by weight.
        return resolvePositionalKey(for: item, existingKeys: existingKeys, positions: positions, liveItems: liveItems)
    }

    /// Title-based key resolution — the tiers ``resolveKey`` tries before
    /// falling back to ``resolvePositionalKey``. Factored out so
    /// ``resolvePositionalKey`` can also use it, on *other* live items, to
    /// infer the store's weight axis without recursing into itself.
    private static func titleTierKey(for item: MenuBarItem, existingKeys: [String]) -> String? {
        let title = item.tag.title
        guard !title.isEmpty else { return nil }

        // Apple modules hosted by MenuBarAgent.
        if item.tag.namespace.isMenuBarHostingNamespace {
            let moduleKey = "module:\(title)"
            if existingKeys.contains(moduleKey) {
                return moduleKey
            }
        }

        // Exact bundle-ID form: status:<namespace>::<title>.
        let bundleKey = "status:\(item.tag.namespace.description)::\(title)"
        if existingKeys.contains(bundleKey) {
            return bundleKey
        }

        // Display-name form, disambiguated by the owning app's display name when
        // the item title alone (e.g. "Item-0") matches several apps.
        let suffix = "::\(title)"
        let candidates = existingKeys.filter { $0.hasPrefix("status:") && $0.hasSuffix(suffix) }
        if candidates.count == 1 {
            return candidates[0]
        }
        if candidates.count > 1 {
            let appNames = candidateAppNames(for: item)
            if let match = candidates.first(where: { key in
                let app = key.dropFirst("status:".count).dropLast(suffix.count)
                return appNames.contains(String(app))
            }) {
                return match
            }
        }
        return nil
    }

    /// Last-resort key resolution for items whose title never matches their
    /// store key (see ``resolveKey(for:existingKeys:positions:liveItems:)``).
    /// Requires the owning app's family of live items and the family's keys in
    /// the store to be the same size — an exact count match is the only way to
    /// pair them without guessing at which sibling is which. The weight axis
    /// (does smaller weight mean further left, or further right?) is inferred
    /// from other live items elsewhere in the bar that resolve unambiguously by
    /// title — the axis is one global sort key shared by the whole bar, so any
    /// such reference pair determines it — rather than assumed to be ascending.
    /// Without a reference pair this still defaults to ascending (the observed
    /// system default, e.g. `module:Clock` = 0 at the leading edge); the caller
    /// verifies the resulting live order and falls back to synthetic drag when
    /// it doesn't hold, so a remaining wrong guess is self-correcting.
    private static func resolvePositionalKey(
        for item: MenuBarItem,
        existingKeys: [String],
        positions: [String: Int],
        liveItems: [MenuBarItem]
    ) -> String? {
        let family = liveItems
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
            // Some apps register under a display name instead of their bundle
            // ID; retry with that prefix before giving up.
            let displayPrefixes = candidateAppNames(for: item).map { "status:\($0)::" }
            familyKeys = existingKeys.filter { key in displayPrefixes.contains { key.hasPrefix($0) } }
        }
        guard familyKeys.count == family.count else { return nil }

        let referencePairs: [(item: MenuBarItem, weight: Int)] = liveItems.compactMap { candidate in
            guard
                let key = titleTierKey(for: candidate, existingKeys: existingKeys),
                let weight = positions[key]
            else { return nil }
            return (candidate, weight)
        }
        let ascending = ascendingAxis(for: referencePairs)

        let orderedKeys = familyKeys.sorted { key1, key2 in
            let weight1 = positions[key1] ?? 0
            let weight2 = positions[key2] ?? 0
            return ascending ? weight1 < weight2 : weight1 > weight2
        }
        return orderedKeys[itemIndex]
    }

    /// Display-name candidates MenuBarAgent might use for the item's owning app.
    private static func candidateAppNames(for item: MenuBarItem) -> Set<String> {
        var names = Set<String>()
        if let localized = item.sourceApplication?.localizedName {
            names.insert(localized)
        }
        names.insert(item.displayName)
        return names
    }

    // MARK: Preference I/O

    private static func readPositions() -> [String: Int] {
        // MenuBarAgent owns and continuously rewrites this domain in another
        // process. CFPreferences caches another app's values per reading
        // process, so a long-running Thaw would keep serving the snapshot it
        // cached the first time it touched the domain (near-empty at launch,
        // before the agent populated it) and every key lookup would miss.
        // Synchronizing first flushes that cache so each read reflects the
        // agent's current layout.
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let value = CFPreferencesCopyValue(
            positionsKey,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        guard let dict = value as? [String: Any] else { return [:] }
        return dict.compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    private static func writePositions(_ positions: [String: Int]) {
        let cfValue = positions.mapValues { NSNumber(value: $0) } as CFDictionary
        CFPreferencesSetValue(
            positionsKey,
            cfValue,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Makes MenuBarAgent re-read the layout. The reliable trigger is a restart:
    /// MenuBarAgent is a managed launch agent and relaunches within ~1-2 s (the
    /// same mechanism ``ControlCenterModuleManager`` uses for Control Center),
    /// re-sorting from the just-written positions.
    ///
    /// This restarts immediately, once per ``move(...)``. The per-pair reconcile
    /// loop is sequentially dependent — each move needs the agent to re-sort
    /// before the next is planned and verified — so restarts there cannot be
    /// coalesced without breaking verification. The batch entry point (which
    /// writes every target weight from one snapshot, then nudges once) is where
    /// a multi-item reorder collapses to a single restart.
    private static func nudgeAgent() {
        for app in NSWorkspace.shared.runningApplications
            where app.bundleIdentifier == agentBundleID
        {
            kill(app.processIdentifier, SIGTERM)
        }
    }
}
