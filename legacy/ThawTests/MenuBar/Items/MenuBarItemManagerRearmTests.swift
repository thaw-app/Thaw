//
//  MenuBarItemManagerRearmTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// When the user updates the active profile, rearmActiveProfileLayout must
/// refresh activeProfileLayout and activeProfileItemIdentifiers, or the next
/// late-arrival re-sort drags items back to the last applied layout.
///
/// Serialized: a real `MenuBarItemManager` reads shared `UserDefaults` keys.
@MainActor
@Suite("Menu bar item manager re-arm", .serialized)
struct MenuBarItemManagerRearmTests {
    /// The late-arrival detector consults the flattened identifier set.
    @Test("Re-arming refreshes the cached layout and the identifier set")
    func rearmRefreshesCachedLayoutAndIdentifiers() {
        let manager = MenuBarItemManager()
        #expect(manager.activeProfileLayout == nil, "Nothing should be armed before a profile is applied or updated")

        let sectionOrder = [
            "hidden": ["com.example.a:Item-0", "com.example.b:Item-0"],
            "alwaysHidden": [String](),
        ]
        let itemSectionMap = [
            "com.example.a:Item-0": "hidden",
            "com.example.b:Item-0": "hidden",
        ]

        manager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: sectionOrder
        )

        #expect(manager.activeProfileLayout?.sectionOrder == sectionOrder)
        #expect(manager.activeProfileLayout?.itemSectionMap == itemSectionMap)
        #expect(
            manager.activeProfileItemIdentifiers
                == ["com.example.a:Item-0", "com.example.b:Item-0"]
        )
    }

    /// The user moves an item from Always-Hidden to Hidden and updates the
    /// profile; re-arming must move the cached section too.
    @Test("Re-arming moves a cached item from Always-Hidden to Hidden")
    func rearmMovesCachedItemFromAlwaysHiddenToHidden() {
        let manager = MenuBarItemManager()
        let uid = "com.if.Amphetamine:Amphetamine"

        // State A: as applied, the item lives in Always-Hidden.
        manager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["alwaysHidden": [uid]],
            itemSectionMap: [uid: "alwaysHidden"],
            itemOrder: ["alwaysHidden": [uid]]
        )
        #expect(
            manager.activeProfileLayout?.itemSectionMap[uid] == "alwaysHidden",
            "Precondition: the applied spec has the item in Always-Hidden"
        )

        // State B: user moved it to Hidden and updated the active profile.
        manager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["hidden": [uid]],
            itemSectionMap: [uid: "hidden"],
            itemOrder: ["hidden": [uid]]
        )

        #expect(
            manager.activeProfileLayout?.itemSectionMap[uid] == "hidden",
            "Re-arm must refresh the cached section so the late-arrival re-sort targets the updated layout, not the pre-update spec"
        )
        #expect(manager.activeProfileItemIdentifiers == [uid])
    }
}
