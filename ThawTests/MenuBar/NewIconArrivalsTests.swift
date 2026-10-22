//
//  NewIconArrivalsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// A new icon joins its app's other icons when those are all in one hidden
/// section, so macOS can keep hiding the app as a whole.
@Suite("New icon arrivals")
struct NewIconArrivalsTests {
    private let main = "com.example.app:Main"
    private let alert = "com.example.app:Alert"
    private let player = "com.example.app:Player"

    private func placements(
        seen: Set<String>,
        current: [String],
        sections: [String: MenuBarSectionName]
    ) -> [String: MenuBarSectionName] {
        var arrivals = NewIconArrivals(seen: seen)
        let placed = arrivals.placements(current: current, saved: Array(sections.keys), authored: { sections[$0] ?? .visible })
        return Dictionary(uniqueKeysWithValues: placed.map { ($0.identifier, $0.section) })
    }

    @Test("A new icon follows an app whose other icons are all hidden")
    func followsHiddenApp() {
        let placed = placements(
            seen: [main, alert], current: [main, alert, player], sections: [main: .hidden, alert: .hidden]
        )
        #expect(placed == [player: .hidden])
    }

    @Test("It follows into Always Hidden too")
    func followsAlwaysHidden() {
        let placed = placements(seen: [main], current: [main, player], sections: [main: .alwaysHidden])
        #expect(placed == [player: .alwaysHidden])
    }

    @Test("An app already split across sections is left alone")
    func splitAppIsLeftAlone() {
        let placed = placements(
            seen: [main, alert], current: [main, alert, player], sections: [main: .hidden, alert: .visible]
        )
        #expect(placed.isEmpty)
    }

    @Test("An app with visible icons keeps its new icon visible")
    func visibleAppStaysVisible() {
        #expect(placements(seen: [main], current: [main, player], sections: [:]).isEmpty)
    }

    @Test("An app's first icon has nothing to follow")
    func firstIconStays() {
        #expect(placements(seen: [], current: [player], sections: [:]).isEmpty)
    }

    @Test("A hidden sibling that is saved but off the bar still counts")
    func savedSiblingCounts() {
        let placed = placements(seen: [main], current: [player], sections: [main: .hidden])
        #expect(placed == [player: .hidden])
    }

    @Test("An icon seen before is never moved, wherever the user put it")
    func seenIconIsNotMoved() {
        let placed = placements(
            seen: [main, alert, player], current: [main, alert, player], sections: [main: .hidden, alert: .hidden]
        )
        #expect(placed.isEmpty)
    }

    @Test("An icon is new only once")
    func newOnlyOnce() {
        var arrivals = NewIconArrivals(seen: [main])
        let sections: [String: MenuBarSectionName] = [main: .hidden]
        #expect(arrivals.placements(current: [main, player], saved: [main], authored: { sections[$0] ?? .visible }).count == 1)
        #expect(arrivals.placements(current: [main, player], saved: [main], authored: { sections[$0] ?? .visible }).isEmpty)
    }

    @Test("An app that keeps renaming an icon stops being followed")
    func renamingAppIsCapped() {
        var arrivals = NewIconArrivals(seen: [main])
        let sections: [String: MenuBarSectionName] = [main: .hidden]
        let placed = (0 ..< 6).flatMap { tick in
            arrivals.placements(
                current: [main, "com.example.app:CPU \(tick)%"], saved: [main], authored: { sections[$0] ?? .visible }
            )
        }
        #expect(placed.count == NewIconArrivals.placementsPerApp)
    }

    @Test("Apple's items share a host, not an app, and are left alone")
    func appleItemsAreLeftAlone() {
        let wifi = "com.apple.controlcenter:WiFi", sound = "com.apple.controlcenter:Sound"
        #expect(placements(seen: [wifi], current: [wifi, sound], sections: [wifi: .hidden]).isEmpty)
    }

    @Test("A new app's first icon goes to the New Items section, unless that is Visible")
    func newAppFollowsNewItems() {
        let orca = "dev.orca:Item-0"
        var arrivals = NewIconArrivals(seen: [main])
        let placed = arrivals.placements(current: [main, orca], saved: [main], authored: { _ in .visible }, newItemsSection: .hidden)
        #expect(placed.map(\.identifier) == [orca])
        #expect(placed.map(\.section) == [.hidden])
        #expect(arrivals.placements(current: [main, orca], saved: [main], authored: { _ in .visible }, newItemsSection: .hidden).isEmpty,
                "an arrival is placed once")

        var visible = NewIconArrivals(seen: [main])
        #expect(visible.placements(current: [main, orca], saved: [main], authored: { _ in .visible }, newItemsSection: .visible).isEmpty)
    }

    @Test("An app's new icon still follows its other icons, whatever the New Items section")
    func knownAppIgnoresNewItems() {
        let placed = placements(seen: [main], current: [main, player], sections: [main: .visible])
        #expect(placed.isEmpty)
        var arrivals = NewIconArrivals(seen: [main])
        let hidden = arrivals.placements(current: [main, player], saved: [main], authored: { _ in .alwaysHidden }, newItemsSection: .hidden)
        #expect(hidden.map(\.section) == [.alwaysHidden])
    }

    @Test("Only a new app's icon takes the New Items position; one that follows its app doesn't")
    func onlyNewAppsTakeThePosition() {
        let orca = "dev.orca:Item-0"
        var arrivals = NewIconArrivals(seen: [main])
        let placed = arrivals.placements(
            current: [main, player, orca], saved: [main], authored: { _ in .hidden }, newItemsSection: .alwaysHidden
        )
        #expect(placed.first { $0.identifier == orca }?.isNewApp == true)
        #expect(placed.first { $0.identifier == player }?.isNewApp == false)
    }

    @Test("A new icon goes into its section's order at the placeholder's slot, once")
    func insertsAtTheSlot() {
        let orca = "dev.orca:Item-0"
        #expect(NewIconArrivals.order(placing: orca, in: ["a:1", "b:1", "c:1"], at: 1) == ["a:1", orca, "b:1", "c:1"])
        #expect(NewIconArrivals.order(placing: orca, in: ["a:1", orca, "b:1"], at: 2) == ["a:1", "b:1", orca],
                "the slot counts the order without the icon, which isn't listed twice")
        #expect(NewIconArrivals.order(placing: orca, in: ["a:1"], at: 9) == ["a:1", orca])
        #expect(NewIconArrivals.order(placing: orca, in: [], at: 0) == [orca])
    }
}
