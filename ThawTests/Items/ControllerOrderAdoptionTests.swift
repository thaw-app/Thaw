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

    /// Runs a body with the saved-order key put back afterwards.
    private func preservingSavedOrder(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Self.orderKey)
        defer { defaults.set(previous, forKey: Self.orderKey) }
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
