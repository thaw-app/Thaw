//
//  SwapTransmutedOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// Swaps preserve group order and other sections; unhideable items remain Visible after the arriving group.
struct SwapTransmutedOrderTests {
    @Test("visible and hidden trade places, each keeping its order")
    func tradesGroups() {
        let order = [
            "visible": ["a", "b", "c"],
            "hidden": ["x", "y"],
            "alwaysHidden": ["z"],
        ]
        let result = MenuBarManager.transmutedOrder(order) { _ in true }
        #expect(result["visible"] == ["x", "y"])
        #expect(result["hidden"] == ["a", "b", "c"])
        #expect(result["alwaysHidden"] == ["z"])
    }

    @Test("items that cannot be hidden stay visible, after the arriving group")
    func keepsUnhideableVisible() {
        let order = [
            "visible": ["clock", "a", "b"],
            "hidden": ["x"],
        ]
        let result = MenuBarManager.transmutedOrder(order) { $0 != "clock" }
        #expect(result["visible"] == ["x", "clock"])
        #expect(result["hidden"] == ["a", "b"])
    }

    @Test("a missing section reads as empty and swaps to empty")
    func missingSections() {
        let result = MenuBarManager.transmutedOrder(["visible": ["a"]]) { _ in true }
        #expect(result["visible"] == [])
        #expect(result["hidden"] == ["a"])
    }

    @Test("an unhideable item settles at the right end rather than round-tripping")
    func unhideableSettlesRight() {
        let order = ["visible": ["clock", "a", "b"], "hidden": ["x"]]
        let once = MenuBarManager.transmutedOrder(order) { $0 != "clock" }
        #expect(once["visible"] == ["x", "clock"])
        // macOS pins the clock at the right edge, so swapping back cannot restore its original left position.
        let twice = MenuBarManager.transmutedOrder(once) { $0 != "clock" }
        #expect(twice["visible"] == ["a", "b", "clock"])
        #expect(twice["hidden"] == ["x"])
        // From there it is stable: every further pair of swaps round-trips.
        let thrice = MenuBarManager.transmutedOrder(twice) { $0 != "clock" }
        let fourth = MenuBarManager.transmutedOrder(thrice) { $0 != "clock" }
        #expect(fourth == twice)
    }

    @Test("swapping twice restores the original order")
    func roundTrip() {
        let order = ["visible": ["a", "b"], "hidden": ["x", "y", "w"]]
        let once = MenuBarManager.transmutedOrder(order) { _ in true }
        let twice = MenuBarManager.transmutedOrder(once) { _ in true }
        #expect(twice == order)
    }
}
