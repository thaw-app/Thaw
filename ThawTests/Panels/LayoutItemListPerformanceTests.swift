//
//  LayoutItemListPerformanceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Layout window list at scale", .serialized, .scratchDefaults)
struct LayoutItemListPerformanceTests {
    private typealias World = LayoutEditorWorld

    /// 165 items over the three sections, about the most anyone has reported.
    private static func seat165(in world: World) {
        let items = (0 ..< 165).map { World.item("Item \($0)") }
        world.seat(Array(items[0 ..< 40]), in: .visible)
        world.seat(Array(items[40 ..< 120]), in: .hidden)
        world.seat(Array(items[120...]), in: .alwaysHidden)
    }

    @Test("Building the list for 165 items stays well inside a frame")
    func buildTime() {
        let world = World()
        Self.seat165(in: world)
        let clock = ContinuousClock()
        _ = LayoutItemList.sections(appState: world.appState, query: "")
        let rounds = 20
        let elapsed = clock.measure {
            for _ in 0 ..< rounds {
                _ = LayoutItemList.sections(appState: world.appState, query: "")
            }
        }
        #expect(elapsed / rounds < .milliseconds(16))
    }

    @Test("While the query stays the same, a redraw doesn't match all over again")
    func filteredRedraw() {
        let world = World()
        Self.seat165(in: world)
        let first = LayoutItemList.sections(appState: world.appState, query: "item 1")
        let clock = ContinuousClock()
        let rounds = 20
        var again = [LayoutItemListSection]()
        let elapsed = clock.measure {
            for _ in 0 ..< rounds {
                again = LayoutItemList.sections(appState: world.appState, query: "item 1")
            }
        }
        #expect(again == first)
        #expect(elapsed / rounds < .milliseconds(16))
        #expect(LayoutItemList.sections(appState: world.appState, query: "item 99") != first, "a new query ranks again")
    }
}
