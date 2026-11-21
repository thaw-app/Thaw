//
//  CapturedTagValidity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Which cached pictures still name an item: a system item by its exact tag, any other ignoring the
/// window ID (matchesIgnoringWindowID), since a picture loaded from disk has none. Built once per pass.
nonisolated struct CapturedTagValidity {
    private struct Key: Hashable {
        let namespace: MenuBarItemTag.Namespace
        let canonicalTitle: String
        let instanceIndex: Int

        init(_ tag: MenuBarItemTag) {
            namespace = tag.namespace
            canonicalTitle = tag.canonicalTitle
            instanceIndex = tag.instanceIndex
        }
    }

    private let exact: Set<MenuBarItemTag>
    private let ignoringWindowID: Set<Key>

    init(keeping tags: Set<MenuBarItemTag>) {
        exact = tags
        ignoringWindowID = Set(tags.map(Key.init))
    }

    func keeps(_ tag: MenuBarItemTag) -> Bool {
        tag.isSystemItem ? exact.contains(tag) : ignoringWindowID.contains(Key(tag))
    }
}
