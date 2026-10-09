//
//  StoreMovePeersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct StoreMovePeersTests {
    private static func app(_ bundle: String, id: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: "Item-0", instanceIndex: 0),
            windowID: id,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 4, width: 24, height: 22),
            title: "Item-0",
            isOnScreen: true
        )
    }

    private static let hiddenFar = app("com.example.HiddenFar", id: 1, x: 1400)
    private static let hiddenNear = app("com.example.HiddenNear", id: 2, x: 1466)
    private static let divider = MenuBarItem(
        tag: .hiddenControlItem,
        windowID: 3,
        ownerPID: 500,
        sourcePID: 500,
        bounds: CGRect(x: 1492, y: 4, width: 2, height: 22),
        title: "Hidden",
        isOnScreen: true
    )
    private static let target = app("com.example.Target", id: 4, x: 1502)
    private static let shown = app("com.example.Shown", id: 5, x: 1560)
    private static let moving = app("com.example.Moving", id: 6, x: 1600)
    private static let live = [hiddenFar, hiddenNear, divider, target, shown, moving]

    private static func section(_ item: MenuBarItem) -> MenuBarSectionName {
        item.windowID <= 2 ? .hidden : .visible
    }

    @Test
    func `hidden apps are not neighbours for a move among the shown items`() {
        let peers = StoreMovePeers.drawn(
            among: Self.live,
            moving: Self.moving,
            target: Self.target,
            revealed: nil,
            section: Self.section
        )
        #expect(peers.map(\.windowID) == [3, 4, 5, 6])
    }

    @Test
    func `everything is kept while a section is revealed`() {
        let peers = StoreMovePeers.drawn(
            among: Self.live,
            moving: Self.moving,
            target: Self.target,
            revealed: .hidden,
            section: Self.section
        )
        #expect(peers.count == Self.live.count)
    }

    @Test
    func `everything is kept for a drop beside a hidden app`() {
        let peers = StoreMovePeers.drawn(
            among: Self.live,
            moving: Self.moving,
            target: Self.hiddenNear,
            revealed: nil,
            section: Self.section
        )
        #expect(peers.count == Self.live.count)
    }

    @Test
    func `a hidden app being moved out stays, the other hidden apps go`() {
        let peers = StoreMovePeers.drawn(
            among: Self.live,
            moving: Self.hiddenNear,
            target: Self.target,
            revealed: nil,
            section: Self.section
        )
        #expect(peers.map(\.windowID) == [2, 3, 4, 5, 6])
    }

    @Test
    func `a drop beside the divider keeps the shown side only`() {
        let peers = StoreMovePeers.drawn(
            among: Self.live,
            moving: Self.moving,
            target: Self.divider,
            revealed: nil,
            section: Self.section
        )
        #expect(peers.map(\.windowID) == [3, 4, 5, 6])
    }
}
