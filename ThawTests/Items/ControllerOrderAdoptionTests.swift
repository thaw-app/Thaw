//
//  ControllerOrderAdoptionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Saved order adopted from the controller", .serialized)
struct ControllerOrderAdoptionTests {
    private static let orderKey = "MenuBarItemManager.savedSectionOrder"
    private static let pinKeys = [
        "MenuBarItemManager.pinnedHiddenBundleIDs",
        "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs",
    ]

    /// Runs a body with the defaults keys the adoption writes put back afterwards.
    private func preservingSavedOrder(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let keys = [Self.orderKey] + Self.pinKeys
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                defaults.set(value, forKey: key)
            }
        }
        body()
    }

    @Test("A controller order becomes a saved order keyed by section, without empty sections")
    func savedOrderMapping() {
        let saved = OrderRecording.savedOrder(from: [
            .visible: ["a", "b"],
            .hidden: [],
            .alwaysHidden: ["c"],
        ])
        #expect(saved == ["visible": ["a", "b"], "alwaysHidden": ["c"]])
    }

    @Test("A profile apply leaves Thaw holding the order the controller normalized")
    func profileApplyAdoptsNormalizedOrder() {
        preservingSavedOrder {
            let controller = RecordingSectionController()
            let manager = MenuBarItemManager()
            // The same app listed in two sections: the controller keeps its first slot only.
            let profileOrder = ["visible": ["a", "dup"], "hidden": ["dup", "b"]]

            manager.commitProfileLayout(itemSectionMap: [:], itemOrder: profileOrder, to: controller)

            #expect(controller.sectionItemOrder[.hidden] == ["b"])
            #expect(manager.savedSectionOrder == ["visible": ["a", "dup"], "hidden": ["b"]])
            #expect(manager.savedSectionOrder != profileOrder)
            #expect(UserDefaults.standard.dictionary(forKey: Self.orderKey) as? [String: [String]] == manager.savedSectionOrder)
        }
    }

    @Test("A profile apply keeps the Visible control at the profile's slot and drops the dividers")
    func profileApplyKeepsVisibleControl() {
        preservingSavedOrder {
            let control = MenuBarItemTag.visibleControlItem.tagIdentifier
            let divider = MenuBarItemTag.hiddenControlItem.tagIdentifier
            let controller = RecordingSectionController()
            let manager = MenuBarItemManager()
            let profileOrder = ["visible": ["a", control, "b"], "hidden": [divider, "c"]]

            manager.commitProfileLayout(itemSectionMap: [:], itemOrder: profileOrder, to: controller)

            #expect(manager.savedSectionOrder["visible"] == ["a", control, "b"])
            #expect(manager.savedSectionOrder["hidden"] == ["c"])
        }
    }

    @Test("A profile apply that succeeds takes the controller's order as it stands then")
    func profileSuccessAdoptsCurrentOrder() {
        preservingSavedOrder {
            let controller = RecordingSectionController(order: [.visible: ["a", "b"], .hidden: ["c"]])
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = ["visible": ["b", "a"], "hidden": ["c"]]

            manager.persistProfileStateOnSuccess(source: .profile, controller: controller)

            #expect(manager.savedSectionOrder == ["visible": ["a", "b"], "hidden": ["c"]])
            #expect(UserDefaults.standard.dictionary(forKey: Self.orderKey) as? [String: [String]] == manager.savedSectionOrder)
        }
    }

    @Test("A saved-order apply leaves Thaw's copy alone")
    func savedOrderApplyKeepsThawCopy() {
        preservingSavedOrder {
            let controller = RecordingSectionController(order: [.visible: ["a", "b"]])
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = ["visible": ["b", "a"]]

            manager.persistProfileStateOnSuccess(source: .savedOrder, controller: controller)

            #expect(manager.savedSectionOrder == ["visible": ["b", "a"]])
        }
    }

    @Test("A reset leaves Thaw holding the order the controller kept, not an empty one")
    func resetAdoptsControllerOrder() {
        preservingSavedOrder {
            let controller = RecordingSectionController(
                order: [.visible: ["a", "b"], .hidden: ["c"], .alwaysHidden: ["d"]]
            )
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = ["visible": ["b", "a"], "hidden": ["c"], "alwaysHidden": ["d"]]

            manager.resetControllerAssignment(to: ["c": .hidden], controller: controller)

            #expect(manager.savedSectionOrder == OrderRecording.savedOrder(from: controller.sectionItemOrder))
            #expect(manager.savedSectionOrder == ["visible": ["a", "b"]])
            #expect(UserDefaults.standard.dictionary(forKey: Self.orderKey) as? [String: [String]] == manager.savedSectionOrder)
        }
    }

    @Test("A reset to Visible leaves Thaw holding the controller's order too")
    func resetToVisibleAdoptsControllerOrder() {
        preservingSavedOrder {
            let controller = RecordingSectionController(order: [.visible: ["a"], .hidden: ["b"]])
            let manager = MenuBarItemManager()
            manager.savedSectionOrder = ["visible": ["a"], "hidden": ["b"]]

            manager.resetControllerAssignment(to: [:], controller: controller)

            #expect(manager.savedSectionOrder == OrderRecording.savedOrder(from: controller.sectionItemOrder))
        }
    }
}
