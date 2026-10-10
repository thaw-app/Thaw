//
//  RevealWalkCompletionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// MenuBarItemManager.completingPartialWalk(_:with:) feeds the structural
/// write 600 ms after a reveal, when the walk can still miss cached members;
/// laddering a partial walk scrambles the bar.
@Suite("Completing a partial reveal walk")
struct RevealWalkCompletionTests {
    private let a = Self.item("A", x: 0, windowID: 1)
    private let b = Self.item("B", x: 30, windowID: 2)
    private let c = Self.item("C", x: 60, windowID: 3)

    @Test("Cached members are inserted at their last-known position")
    func missingMembersAreInsertedByFrame() {
        let completed = MenuBarItemManager.completingPartialWalk([a, c], with: [a, b, c])
        #expect(completed.map(\.uniqueIdentifier) == [a, b, c].map(\.uniqueIdentifier))
    }

    @Test("A complete walk is returned as is")
    func completeWalkIsUntouched() {
        let completed = MenuBarItemManager.completingPartialWalk([a, b, c], with: [a, b, c])
        #expect(completed.map(\.uniqueIdentifier) == [a, b, c].map(\.uniqueIdentifier))
    }

    @Test("Live geometry wins over the cached copy, even under a new window ID")
    func liveGeometryWins() {
        let relaunched = Self.item("B", x: 300, windowID: 42)
        let completed = MenuBarItemManager.completingPartialWalk([a, relaunched], with: [a, b, c])
        // Position now comes from the bar: the relaunched item carries its
        // live frame (x=300) and sorts by it, past the cached C at x=60.
        #expect(completed.map(\.uniqueIdentifier) == [a, c, relaunched].map(\.uniqueIdentifier))
        #expect(completed[2].windowID == 42)
        #expect(completed[2].bounds.minX == 300)
    }

    @Test("An empty cache adds nothing")
    func emptyCacheAddsNothing() {
        #expect(MenuBarItemManager.completingPartialWalk([a], with: []).count == 1)
    }

    private static func item(_ title: String, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}
