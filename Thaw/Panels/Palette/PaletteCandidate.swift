//
//  PaletteCandidate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Ifrit
import MenuBarModel

/// Match display names, owner names and identity keys so app-name queries and live AX titles still find items.
/// The launcher shares SearchPresentation's panel, not the inspector's search policy.
struct PaletteCandidate: Searchable {
    let item: MenuBarItem
    let displayName: String
    let ownerName: String
    let identityKey: String

    var properties: [FuseProp] {
        let weights = SearchWeights.palette
        var props = [FuseProp(displayName, weight: weights.title)]
        if !ownerName.isEmpty, ownerName != displayName {
            props.append(FuseProp(ownerName, weight: weights.keywords))
        }
        if let identityKey = Self.matchableIdentityKey(identityKey) {
            props.append(FuseProp(identityKey, weight: weights.description))
        }
        return props
    }

    /// Show the owner only when it adds a distinct field that the matcher also uses.
    var subtitle: String? {
        guard !ownerName.isEmpty, ownerName != displayName else {
            return nil
        }
        return ownerName
    }

    /// Exclude untitled AX placeholders such as Item-0 so every nameless child does not match "item".
    static func matchableIdentityKey(_ key: String) -> String? {
        guard !key.isEmpty else { return nil }
        let title = key.split(separator: ":").last.map(String.init) ?? key
        guard !isPlaceholderTitle(title) else { return nil }
        return key
    }

    /// Item-<digits>, the AX provider's stand-in for a nameless child.
    private static func isPlaceholderTitle(_ title: String) -> Bool {
        guard title.hasPrefix("Item-") else { return false }
        let suffix = title.dropFirst("Item-".count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }
}

// MARK: - Inventory

extension PaletteCandidate {
    /// Use the warm item cache, not an AX walk: application timeouts do not propagate to children, so hung publishers could stall hotkeys.
    @MainActor
    static func inventory(from itemManager: MenuBarItemManager) -> [PaletteCandidate] {
        let items = itemManager.managedItems.filter(\.isUserActionable)
        // Menu bar order breaks equal-rank ties left to right.
        let ordered = items.sorted { $0.bounds.minX < $1.bounds.minX }
        return ordered.map { item in
            PaletteCandidate(
                item: item,
                // Memoize owner resolution rather than repeating item.displayName's process lookup.
                displayName: MenuBarItemDisplayName.displayName(for: item),
                ownerName: MenuBarItemDisplayName.ownerName(for: item) ?? "",
                identityKey: item.uniqueIdentifier
            )
        }
    }
}

// MARK: - Ranking

extension PaletteCandidate {
    /// Prefer prefixes because fuzzy scores can rank short mid-word matches above longer prefix matches.
    /// Keep Ifrit out of SearchRanker while sharing its relevance and tie ordering within each block.
    static nonisolated func ranked(
        matching query: String,
        in candidates: [PaletteCandidate],
        using fuse: Fuse
    ) -> [PaletteCandidate] {
        let matches = fuse.searchSync(query, in: candidates, by: \.properties)
        let scored = matches.map { (item: candidates[$0.index], diffScore: $0.diffScore) }

        let needle = query.lowercased()
        var prefixed = [(item: PaletteCandidate, diffScore: Double)]()
        var rest = [(item: PaletteCandidate, diffScore: Double)]()
        for entry in scored {
            if entry.item.displayName.lowercased().hasPrefix(needle)
                || entry.item.ownerName.lowercased().hasPrefix(needle)
            {
                prefixed.append(entry)
            } else {
                rest.append(entry)
            }
        }

        return SearchRanker.sortedByRelevance(prefixed) + SearchRanker.sortedByRelevance(rest)
    }
}
