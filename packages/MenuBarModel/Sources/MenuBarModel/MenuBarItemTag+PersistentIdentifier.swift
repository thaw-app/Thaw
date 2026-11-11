//
//  MenuBarItemTag+PersistentIdentifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

public extension MenuBarItemTag {
    /// Splits a persisted namespace:title[:instance] identifier at its first colon (a bundle ID has none).
    /// Nil without a colon; the title keeps any instance suffix and may be empty.
    static func persistentIdentifierParts(_ identifier: String) -> (namespace: String, title: String)? {
        guard let separator = identifier.firstIndex(of: ":") else { return nil }
        return (String(identifier[..<separator]), String(identifier[identifier.index(after: separator)...]))
    }

    /// Whether a persisted title ends in a :<number> that may name a second
    /// instance of the item.
    static func hasInstanceSuffix(_ title: String) -> Bool {
        title.wholeMatch(of: TagRegex.instanceSuffix) != nil
    }
}
