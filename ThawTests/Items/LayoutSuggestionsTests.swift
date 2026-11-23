//
//  LayoutSuggestionsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Layout suggestions")
struct LayoutSuggestionsTests {
    private func item(_ title: String, x: CGFloat = 100) -> MenuBarItem {
        ItemsFixture.item(title, x: x, sourcePID: 100)
    }

    @Test("Only items mostly under the notch are reported")
    func reportsItemsBehindTheNotch() {
        let notch = CGRect(x: 600, y: 0, width: 200, height: 37)
        let under = item("Under", x: 700)
        let beside = item("Beside", x: 900)
        let result = LayoutSuggestions.itemsBehindNotch([under, beside], notchRects: [notch])
        #expect(result.map(\.title) == ["Under"])
    }

    private func littleSnitchItem() -> MenuBarItem {
        ItemsFixture.item("Item-0", bundle: LayoutSuggestions.littleSnitchAgentBundleID, x: 200, windowID: 2, ownerPID: 200)
    }

    @Test("Little Snitch running without an enumerated item is reported")
    func reportsMissingLittleSnitchItem() {
        let running: Set = [LayoutSuggestions.littleSnitchAgentBundleID, "com.example.Other"]
        #expect(LayoutSuggestions.littleSnitchItemIsMissing(runningBundleIDs: running, items: [item("Other")]))
    }

    @Test("Nothing is reported when its item is enumerated, when it is not running, or before any item is known")
    func staysQuietOtherwise() {
        let running: Set = [LayoutSuggestions.littleSnitchAgentBundleID]
        #expect(!LayoutSuggestions.littleSnitchItemIsMissing(runningBundleIDs: running, items: [item("Other"), littleSnitchItem()]))
        #expect(!LayoutSuggestions.littleSnitchItemIsMissing(runningBundleIDs: ["com.example.Other"], items: [item("Other")]))
        #expect(!LayoutSuggestions.littleSnitchItemIsMissing(runningBundleIDs: running, items: []))
    }
}

@MainActor
@Suite("Thaw Bar keyboard focus")
struct ThawBarKeyboardFocusTests {
    @Test("Nothing is highlighted until the keyboard is used")
    func startsUnfocused() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 3, arrangement: .row)
        #expect(focus.index == nil)
        focus.begin()
        #expect(focus.index == 0)
    }

    @Test("A row moves left and right, stops at the ends, and ignores up and down")
    func rowMovement() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 3, arrangement: .row)
        focus.begin()
        focus.move(dx: -1, dy: 0)
        #expect(focus.index == 0)
        focus.move(dx: 1, dy: 0)
        focus.move(dx: 1, dy: 0)
        focus.move(dx: 1, dy: 0)
        #expect(focus.index == 2)
        focus.move(dx: 0, dy: -1)
        #expect(focus.index == 2)
    }

    @Test("A grid moves a whole row with up and down")
    func gridMovement() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 8, arrangement: .grid(columns: 3))
        focus.begin()
        focus.move(dx: 0, dy: 1)
        #expect(focus.index == 3)
        focus.move(dx: 1, dy: 0)
        #expect(focus.index == 4)
        focus.move(dx: 0, dy: 1)
        #expect(focus.index == 7)
    }

    @Test("Removing items keeps the highlight inside them")
    func clampsWhenItemsLeave() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 5, arrangement: .row)
        focus.begin()
        for _ in 0 ..< 4 {
            focus.move(dx: 1, dy: 0)
        }
        focus.update(itemCount: 2, arrangement: .row)
        #expect(focus.index == 1)
    }

    @Test("The pointer takes the highlight only while the keyboard is in use")
    func pointerTakesOver() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 4, arrangement: .row)
        focus.pointerEntered(2)
        #expect(focus.index == nil)
        focus.begin()
        focus.pointerEntered(2)
        #expect(focus.index == 2)
        focus.move(dx: 1, dy: 0)
        #expect(focus.index == 3)
    }

    @Test("Return only asks for a click while something is highlighted")
    func activation() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 2, arrangement: .row)
        focus.activate()
        #expect(focus.activationRequest == 0)
        focus.begin()
        focus.activate()
        #expect(focus.activationRequest == 1)
    }
}

@MainActor
@Suite("Suggestion texts name a few items and count the rest", .scratchDefaults)
struct LayoutSuggestionNamesTests {
    private func named(_ name: String) -> MenuBarItem {
        var item = ItemsFixture.item(name, bundle: "com.example.suggest.\(name)", x: 0, width: 22, windowID: 5, ownerPID: 999_972, sourcePID: 999_972)
        item.customName = name
        return item
    }

    @Test("Up to three names are joined as a list")
    func shortList() {
        let names = LayoutSuggestions.names(of: ["Alpha", "Beta", "Gamma"].map(named))
        #expect(names == ["Alpha", "Beta", "Gamma"].formatted(.list(type: .and)))
    }

    @Test("Past three names, the rest are counted")
    func longListIsShortened() {
        let names = LayoutSuggestions.names(of: ["A", "B", "C", "D", "E"].map(named))
        let more = String(localized: "\(2) more", comment: "Last entry of a shortened list of menu bar item names")
        #expect(names == ["A", "B", "C", more].formatted(.list(type: .and)))
        #expect(!names.contains("D"))
    }
}
