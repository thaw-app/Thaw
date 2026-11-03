//
//  PlaceholderIdentityAdoption.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Gives an item that answered under a placeholder name the saved identity it stands for.
///
/// OneDrive's icons answer Accessibility as "OneDrive", or unnamed, until the account loads,
/// while the title Thaw saved names the account. Read as new, the icons are placed as arrivals,
/// and under Native hiding one unassigned icon shows the whole app. Thaw 2 told the icons apart
/// by window; here the place stands in for it: the app's placeholder items, left to right, take
/// the saved titles it has not answered with, in bar order. A walk that reads the account titles
/// overwrites a wrong guess.
public enum PlaceholderIdentityAdoption {
    /// The outcome of one pass.
    public struct Result: Equatable, Sendable {
        /// The items to publish, with the saved identities where a placeholder stood.
        public let items: [MenuBarItem]
        /// The adopted identity by the placeholder identifier it replaced.
        public let adopted: [String: String]
    }

    /// Sections as they sit on the bar, left to right, which is the order saved titles are handed out in.
    static let barOrder: [MenuBarSectionName] = [.alwaysHidden, .hidden, .visible]

    /// Whether a title names no account of a multiline-status app: the bare app name OneDrive
    /// answers with before the account loads, or an unnamed Item-N.
    public static func isPlaceholderTitle(_ title: String, bundleID: String) -> Bool {
        MenuBarItemTag.isGenericItemTitle(title)
            || (MenuBarItemTag.hasMultilineStatusTitles(bundleID) && title == "OneDrive")
    }

    /// The saved titles each app with placeholder names can hand out, by bundle ID, in bar order.
    ///
    /// A placeholder title or a numbered instance names no account, so neither is handed out.
    ///
    /// - Parameter order: Identifiers by section, each `bundleID:title` with an optional `:instance`.
    public static func savedTitles(in order: [String: [String]]) -> [String: [String]] {
        var titles: [String: [String]] = [:]
        for section in barOrder {
            for identifier in (order[section.rawValue] ?? []).map(MenuBarItemTag.canonicalPersistentIdentifier) {
                // A bundle ID never contains a colon, so the first one ends it.
                guard let separator = identifier.firstIndex(of: ":") else { continue }
                let bundleID = String(identifier[..<separator])
                let title = String(identifier[identifier.index(after: separator)...])
                guard MenuBarItemTag.hasMultilineStatusTitles(bundleID), !title.isEmpty, title.wholeMatch(of: /.+:\d+/) == nil, !isPlaceholderTitle(title, bundleID: bundleID), !(titles[bundleID] ?? []).contains(title)
                else { continue }
                titles[bundleID, default: []].append(title)
            }
        }
        return titles
    }

    /// Whether an item answered under a placeholder name that a saved title could stand for.
    public static func hasPlaceholderIdentity(_ item: MenuBarItem) -> Bool {
        guard case let .string(bundleID) = item.tag.namespace, !item.isControlItem else { return false }
        return MenuBarItemTag.hasMultilineStatusTitles(bundleID) && isPlaceholderTitle(item.tag.title, bundleID: bundleID)
    }

    /// Hands each app's saved titles to its placeholder items, left to right.
    ///
    /// A title the app already answered with is not handed out, and a placeholder left over once the
    /// titles run out keeps its name, since nothing saved stands for it. The item keeps its window,
    /// frame, display title and on-screen state.
    public static func adopting(_ items: [MenuBarItem], savedTitles: [String: [String]]) -> Result {
        var result = items
        var adopted: [String: String] = [:]
        for (bundleID, saved) in savedTitles {
            var placeholders: [Int] = []
            var answered = Set<String>()
            for (index, item) in items.enumerated() {
                guard case let .string(itemBundleID) = item.tag.namespace, itemBundleID == bundleID else { continue }
                if hasPlaceholderIdentity(item) {
                    placeholders.append(index)
                } else {
                    answered.insert(item.tag.title)
                }
            }
            guard !placeholders.isEmpty else { continue }
            placeholders.sort { items[$0].bounds.minX < items[$1].bounds.minX }
            let pool = saved.filter { !answered.contains($0) }
            for (index, title) in zip(placeholders, pool) {
                let item = items[index]
                result[index] = MenuBarItem(
                    tag: MenuBarItemTag(namespace: item.tag.namespace, title: title, windowID: item.windowID, instanceIndex: 0),
                    windowID: item.windowID,
                    ownerPID: item.ownerPID,
                    sourcePID: item.sourcePID,
                    bounds: item.bounds,
                    title: item.title,
                    isOnScreen: item.isOnScreen
                )
                adopted[item.uniqueIdentifier] = result[index].uniqueIdentifier
            }
        }
        return Result(items: result, adopted: adopted)
    }
}
