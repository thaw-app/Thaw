//
//  ObservedOrderRecordingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Mirrored order recorded into the controller")
struct ObservedOrderRecordingTests {
    private static let displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    private static let defaultsKey = "MenuBarItemManager.savedSectionOrder"

    private static func item(x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.app\(windowID)"), title: "Item-0", instanceIndex: 0),
            windowID: windowID,
            ownerPID: pid_t(windowID),
            sourcePID: pid_t(windowID),
            bounds: CGRect(x: x, y: 3.5, width: 24, height: 24),
            title: "Item-0",
            isOnScreen: true
        )
    }

    private static func cache(visible: [MenuBarItem]) -> MenuBarItemCache {
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = visible
        return cache
    }

    @Test("Section keys map to section names and unknown keys are dropped")
    func keyMapping() {
        let mapped = OrderRecording.observedOrder(from: [
            "visible": ["a"],
            "hidden": ["b"],
            "alwaysHidden": ["c"],
            "retired": ["d"],
        ])
        #expect(mapped == [.visible: ["a"], .hidden: ["b"], .alwaysHidden: ["c"]])
    }

    @Test("A mirror that reordered Visible leaves the controller in the same Visible order")
    func mirrorReachesController() {
        let previous = UserDefaults.standard.object(forKey: Self.defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: Self.defaultsKey) }

        let items = [Self.item(x: 100, windowID: 1), Self.item(x: 160, windowID: 2), Self.item(x: 220, windowID: 3)]
        let ids = items.map(\.uniqueIdentifier)
        let controller = RecordingSectionController(order: [.visible: [ids[0], ids[1], ids[2]]])
        let manager = MenuBarItemManager()
        manager.savedSectionOrder = ["visible": [ids[0], ids[1], ids[2]]]

        // The bar now shows the third item first.
        let moved = [items[2], items[0], items[1]].enumerated().map { index, item in
            Self.item(x: 100 + CGFloat(index) * 60, windowID: item.windowID)
        }
        manager.mirrorSavedSectionOrderIfSettled(
            from: Self.cache(visible: moved),
            displays: Self.displays,
            controller: controller
        )

        #expect(manager.savedSectionOrder["visible"] == [ids[2], ids[0], ids[1]])
        #expect(controller.sectionItemOrder[.visible] == [ids[2], ids[0], ids[1]])
        #expect(controller.observedCommits == 1)
    }

    @Test("A mirror that equals both records commits nothing in the controller")
    func equalMirrorCommitsNothing() {
        let previous = UserDefaults.standard.object(forKey: Self.defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: Self.defaultsKey) }

        let items = [Self.item(x: 100, windowID: 1), Self.item(x: 160, windowID: 2)]
        let ids = items.map(\.uniqueIdentifier)
        let controller = RecordingSectionController(order: [.visible: ids])
        let manager = MenuBarItemManager()
        manager.savedSectionOrder = ["visible": ids]

        manager.mirrorSavedSectionOrderIfSettled(
            from: Self.cache(visible: items),
            displays: Self.displays,
            controller: controller
        )

        #expect(controller.sectionItemOrder[.visible] == ids)
        #expect(controller.observedCommits == 0)
    }

    @Test("A mirror Thaw already holds still reaches a controller that is behind")
    func equalToThawButBehindController() {
        let previous = UserDefaults.standard.object(forKey: Self.defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: Self.defaultsKey) }

        let items = [Self.item(x: 100, windowID: 1), Self.item(x: 160, windowID: 2)]
        let ids = items.map(\.uniqueIdentifier)
        let controller = RecordingSectionController(order: [.visible: ids.reversed()])
        let manager = MenuBarItemManager()
        manager.savedSectionOrder = ["visible": ids]

        manager.mirrorSavedSectionOrderIfSettled(
            from: Self.cache(visible: items),
            displays: Self.displays,
            controller: controller
        )

        #expect(controller.sectionItemOrder[.visible] == ids)
    }

    @Test("A mirror the guards refuse records nothing")
    func refusedMirrorRecordsNothing() {
        let items = [Self.item(x: 100, windowID: 1), Self.item(x: 160, windowID: 2)]
        let ids = items.map(\.uniqueIdentifier)
        let controller = RecordingSectionController(order: [.visible: ids])
        let manager = MenuBarItemManager()
        manager.savedSectionOrder = ["visible": ids.reversed()]
        manager.isRestoringItemOrder = true

        manager.mirrorSavedSectionOrderIfSettled(
            from: Self.cache(visible: items),
            displays: Self.displays,
            controller: controller
        )

        #expect(controller.observedOrders.isEmpty)
    }
}
