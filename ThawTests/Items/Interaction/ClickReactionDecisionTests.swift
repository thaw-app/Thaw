//
//  ClickReactionDecisionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Click reactions are judged by the item's size and its owners")
struct ClickReactionDecisionTests {
    private let before = CGRect(x: 100, y: 0, width: 30, height: 24)

    @Test("A vanished window is a change")
    func vanishedWindowChanged() {
        #expect(ClickReactionVerifier.itemChanged(from: before, to: nil))
    }

    @Test("A moved window of the same size is not a change")
    func movedIsNotChanged() {
        #expect(!ClickReactionVerifier.itemChanged(from: before, to: before.offsetBy(dx: 40, dy: 0)))
    }

    @Test("A wider or taller window is a change")
    func resizedIsChanged() {
        #expect(ClickReactionVerifier.itemChanged(from: before, to: CGRect(x: 100, y: 0, width: 60, height: 24)))
        #expect(ClickReactionVerifier.itemChanged(from: before, to: CGRect(x: 100, y: 0, width: 30, height: 40)))
    }

    @Test("Reaction owners are the owner and, when different, the source")
    func reactionPIDs() {
        let hosted = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.react"), title: "A", instanceIndex: 0),
            windowID: 4,
            ownerPID: 10,
            sourcePID: 20,
            bounds: before,
            title: "A",
            isOnScreen: true
        )
        let own = MenuBarItem(
            tag: hosted.tag,
            windowID: 5,
            ownerPID: 10,
            sourcePID: nil,
            bounds: before,
            title: "A",
            isOnScreen: true
        )
        #expect(hosted.reactionPIDs == [10, 20])
        #expect(own.reactionPIDs == [10])
    }

    @Test("A snapshot of an item whose window does not exist records it as off screen")
    func snapshotOfMissingWindow() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.react"), title: "B", instanceIndex: 0),
            windowID: CGWindowID(UInt32.max - 11),
            ownerPID: 999_975,
            sourcePID: 999_976,
            bounds: before,
            title: "B",
            isOnScreen: true
        )

        let snapshot = ClickReactionVerifier.snapshot(for: item)

        #expect(snapshot.pids == [999_975, 999_976])
        #expect(snapshot.itemWindowID == item.windowID)
        #expect(snapshot.itemBounds == before)
        #expect(!snapshot.itemWindowWasOnScreen)
        #expect(!snapshot.onScreenWindowIDs.contains(item.windowID))
    }
}
