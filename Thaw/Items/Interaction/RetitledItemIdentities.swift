//
//  RetitledItemIdentities.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Synchronization

/// Applies RetitleIdentityMemory to a walk's items, owner by owner, for the in-process walk and the helper's.
nonisolated enum RetitledItemIdentities {
    private static let shared = Mutex(RetitleIdentityMemory())
    private static let diagLog = DiagLog(category: "MenuBarItemAXProvider")

    static func resolve(_ raw: [MenuBarItemAXProvider.RawItem]) -> [MenuBarItemAXProvider.RawItem] {
        shared.withLock { resolve(raw, with: &$0) }
    }

    /// raw with each item whose identity fell back to its live title given back the identity its slot had.
    /// An identity that differs from the displayed text came from an identifier or a canonical title.
    static func resolve(
        _ raw: [MenuBarItemAXProvider.RawItem],
        with memory: inout RetitleIdentityMemory
    ) -> [MenuBarItemAXProvider.RawItem] {
        var resolved = raw
        let indicesByOwner = Dictionary(grouping: raw.indices, by: { raw[$0].ownerPID })
        for (owner, indices) in indicesByOwner {
            let slots = indices.map {
                RetitleIdentityMemory.Slot(raw[$0].identityTitle, isStable: raw[$0].identityTitle != raw[$0].displayTitle)
            }
            let identities = memory.resolve(owner: owner, slots: slots)
            for (index, identity) in zip(indices, identities) where identity != raw[index].identityTitle {
                let item = raw[index]
                diagLog.debug("menuBarItems: kept \(identity) for an item read as '\(item.identityTitle)'")
                resolved[index] = MenuBarItemAXProvider.RawItem(
                    namespace: item.namespace,
                    identityTitle: identity,
                    displayTitle: item.displayTitle,
                    bounds: item.bounds,
                    ownerPID: item.ownerPID
                )
            }
        }
        return resolved
    }
}
