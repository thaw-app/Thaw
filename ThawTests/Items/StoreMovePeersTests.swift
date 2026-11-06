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
    /// Each app has its own process: the window ID doubles as the PID.
    private static func app(_ bundle: String, id: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: "Item-0", instanceIndex: 0),
            windowID: id,
            ownerPID: pid_t(id),
            sourcePID: pid_t(id),
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

    /// Items 1 and 2 are assigned to Hidden.
    private static func section(_ item: MenuBarItem) -> MenuBarSectionName {
        item.windowID <= 2 ? .hidden : .visible
    }

    private func peers(
        moving: MenuBarItem = moving,
        target: MenuBarItem = target,
        drawnOwners: Set<pid_t>?,
        revealed: MenuBarSectionName? = nil
    ) -> [CGWindowID] {
        StoreMovePeers.drawn(
            among: Self.live,
            moving: moving,
            target: target,
            drawnOwners: drawnOwners,
            revealed: revealed,
            section: Self.section
        ).map(\.windowID)
    }

    // MARK: What macOS draws is known

    @Test
    func `an app macOS is not drawing is not a neighbour`() {
        #expect(peers(drawnOwners: [500, 4, 5, 6]) == [3, 4, 5, 6])
    }

    @Test
    func `an item assigned to Hidden that macOS still draws stays a neighbour`() {
        // macOS cannot hide every app. Its icon is on the bar, so it is a real neighbour.
        #expect(peers(drawnOwners: [500, 2, 4, 5, 6]) == [2, 3, 4, 5, 6])
    }

    @Test
    func `a revealed section needs no special case, its items are drawn`() {
        #expect(peers(drawnOwners: [500, 1, 2, 4, 5, 6], revealed: .hidden) == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func `everything is kept for a drop beside an item that is not drawn`() {
        #expect(peers(target: Self.hiddenNear, drawnOwners: [500, 4, 5, 6]) == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func `an undrawn item being moved out stays, the other undrawn items go`() {
        #expect(peers(moving: Self.hiddenNear, drawnOwners: [500, 4, 5, 6]) == [2, 3, 4, 5, 6])
    }

    @Test
    func `Thaw's controls are kept whatever is drawn`() {
        #expect(peers(drawnOwners: [4, 5, 6]) == [3, 4, 5, 6])
        #expect(peers(target: Self.divider, drawnOwners: [4, 5, 6]) == [3, 4, 5, 6])
    }

    // MARK: What macOS draws could not be read

    @Test
    func `without a reading, an item in a closed section is taken as not drawn`() {
        #expect(peers(drawnOwners: nil) == [3, 4, 5, 6])
    }

    @Test
    func `without a reading, everything is kept while a section is revealed`() {
        #expect(peers(drawnOwners: nil, revealed: .hidden) == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func `without a reading, everything is kept for a drop beside an item in a closed section`() {
        #expect(peers(target: Self.hiddenNear, drawnOwners: nil) == [1, 2, 3, 4, 5, 6])
    }
}
