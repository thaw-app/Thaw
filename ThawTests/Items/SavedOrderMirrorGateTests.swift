//
//  SavedOrderMirrorGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// The live order becomes the saved order only once the bar has been quiet for a while.
@MainActor
@Suite("Saved order mirror gate")
struct SavedOrderMirrorGateTests {
    private let start = ContinuousClock.now
    private let items: Set<String> = ["a", "b", "c"]
    private let clock = TestClock()
    private let settling: BarSettling
    private let gate: SavedOrderMirrorGate

    init() {
        let clock = clock
        settling = BarSettling(now: { clock.now })
        gate = SavedOrderMirrorGate(settling: settling)
        clock.now = start
    }

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int(seconds * 1000))
    }

    /// Asks the gate at the given second on the test's clock.
    private func allows(
        _ identifiers: Set<String>? = nil,
        restrictionChange: ContinuousClock.Instant? = nil,
        sectionRevealed: Bool = false,
        transientFrame: String? = nil,
        at seconds: Double
    ) -> Bool {
        clock.now = at(seconds)
        return gate.allowsMirror(
            identifiers: identifiers ?? items,
            restrictionChange: restrictionChange,
            sectionRevealed: sectionRevealed,
            transientFrame: transientFrame
        )
    }

    @Test("A quiet bar may be mirrored")
    func quietBarMirrors() {
        #expect(allows(at: 0))
        #expect(allows(at: 3))
    }

    @Test("An item arriving holds the mirror past the agent's rewrite 10 s later")
    func arrivalHoldsTheMirror() {
        _ = allows(at: 0)
        #expect(!allows(items.union(["d"]), at: 1))
        #expect(!allows(items.union(["d"]), at: 11.5))
        #expect(allows(items.union(["d"]), at: 13.5))
    }

    @Test("An item leaving holds the mirror too")
    func departureHoldsTheMirror() {
        _ = allows(at: 0)
        #expect(!allows(["a", "b"], at: 1))
    }

    @Test("One item swapped for another in the same pass holds the mirror")
    func swapHoldsTheMirror() {
        _ = allows(at: 0)
        #expect(!allows(["a", "b", "d"], at: 1))
    }

    @Test("A recent hiding change holds the mirror")
    func restrictionChangeHoldsTheMirror() {
        #expect(!allows(restrictionChange: at(1), at: 2))
        #expect(allows(restrictionChange: at(1), at: 14))
    }

    @Test("A wake or display change holds the mirror")
    func systemEventHoldsTheMirror() {
        _ = allows(at: 0)
        clock.now = at(10)
        settling.note(.screensWoke)
        #expect(!allows(at: 12))
        #expect(allows(at: 23))
    }

    @Test("A revealed section holds the mirror, and the hold outlasts the reveal")
    func revealedSectionHoldsTheMirror() {
        #expect(allows(at: 0))
        #expect(!allows(sectionRevealed: true, at: 1))
        #expect(!allows(sectionRevealed: true, at: 20))
        #expect(!allows(at: 25))
        #expect(allows(at: 32.5))
    }

    @Test("An item with a transient frame holds the mirror past the moment it settles")
    func transientFrameHoldsTheMirror() {
        #expect(allows(at: 0))
        #expect(!allows(transientFrame: "a at x 0", at: 1))
        #expect(!allows(at: 12.5))
        #expect(allows(at: 13.5))
    }

    private static let displays = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 1920, y: -400, width: 1920, height: 1080),
    ]

    private static func item(x: CGFloat, y: CGFloat = 3.5, width: CGFloat = 24, onScreen: Bool = true, windowID: CGWindowID = 1) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.app\(windowID)"), title: "Item-0", instanceIndex: 0),
            windowID: windowID,
            ownerPID: pid_t(windowID),
            sourcePID: pid_t(windowID),
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: "Item-0",
            isOnScreen: onScreen
        )
    }

    @Test("Frames on a bar, on a higher display's bar, or parked are settled")
    func settledFrames() {
        let items = [
            Self.item(x: 1700, windowID: 1),
            Self.item(x: 3500, y: -396.5, windowID: 2),
            Self.item(x: -1, windowID: 3),
            Self.item(x: 7, y: 1068, windowID: 4),
            Self.item(x: 0, width: 0, windowID: 5),
            Self.item(x: 0, onScreen: false, windowID: 6),
        ]
        #expect(SavedOrderMirrorGate.transientFrame(among: items, displays: Self.displays) == nil)
    }

    @Test("A frame at x == 0 is transient")
    func zeroXIsTransient() throws {
        let found = try #require(SavedOrderMirrorGate.transientFrame(among: [Self.item(x: 1700), Self.item(x: 0, windowID: 2)], displays: Self.displays))
        #expect(found.contains("com.example.app2"))
    }

    @Test("A frame above its display's bar is transient")
    func aboveTheBarIsTransient() {
        #expect(SavedOrderMirrorGate.transientFrame(among: [Self.item(x: 1700, y: -30)], displays: Self.displays) != nil)
        #expect(SavedOrderMirrorGate.transientFrame(among: [Self.item(x: 3500, y: -430)], displays: Self.displays) != nil)
    }

    @Test("A frame over no display is transient")
    func offEveryDisplayIsTransient() {
        #expect(SavedOrderMirrorGate.transientFrame(among: [Self.item(x: 5000)], displays: Self.displays) != nil)
    }

    @Test("With no displays known nothing can be judged")
    func noDisplays() {
        #expect(SavedOrderMirrorGate.transientFrame(among: [Self.item(x: 0)], displays: []) == nil)
    }

    @Test("Without a drag the mirror is never behind")
    func noDragIsNotBehind() {
        #expect(!gate.mirrorIsBehind(userDragEndedAt: nil))
        gate.noteMirrored(at: at(0))
        #expect(!gate.mirrorIsBehind(userDragEndedAt: nil))
    }

    @Test("A drag after the last mirror leaves the mirror behind")
    func dragAfterTheMirrorIsBehind() {
        gate.noteMirrored(at: at(0))
        #expect(gate.mirrorIsBehind(userDragEndedAt: at(2)))
    }

    @Test("A mirror after the drag catches up")
    func mirrorAfterTheDragIsNotBehind() {
        gate.noteMirrored(at: at(14))
        #expect(!gate.mirrorIsBehind(userDragEndedAt: at(2)))
    }

    @Test("A drag with no mirror ever is behind")
    func dragWithoutAnyMirrorIsBehind() {
        #expect(gate.mirrorIsBehind(userDragEndedAt: at(2)))
    }

    @Test("A Hidden divider read right of the Clock holds the mirror, even after a ⌘-drag")
    func dividerRightOfClockHoldsTheMirror() {
        let key = "MenuBarItemManager.savedSectionOrder"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let clock = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 20,
            ownerPID: 400,
            sourcePID: 400,
            bounds: CGRect(x: 1840, y: 3.5, width: 56, height: 24),
            title: "com.apple.menuextra.clock",
            isOnScreen: true
        )
        let visible = [Self.item(x: 1600, windowID: 1), Self.item(x: 1700, windowID: 2), clock]
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = visible
        let manager = MenuBarItemManager()
        let visibleKey = MenuBarSectionName.visible.rawValue
        let saved = [visibleKey: [visible[1], visible[0]].map(\.uniqueIdentifier)]
        manager.savedSectionOrder = saved

        manager.mirrorSavedSectionOrderIfSettled(
            from: cache, controlItems: Self.hiddenDivider(x: 1900), placedByUser: true, displays: Self.displays
        )
        #expect(manager.savedSectionOrder == saved)

        manager.mirrorSavedSectionOrderIfSettled(
            from: cache, controlItems: Self.hiddenDivider(x: 1500), placedByUser: true, displays: Self.displays
        )
        #expect(manager.savedSectionOrder != saved)
    }

    private static func hiddenDivider(x: CGFloat) -> ControlItemPair {
        let hidden = MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 9,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 4.5, width: 2, height: 24),
            title: ControlItemIdentifier.hidden.rawValue,
            isOnScreen: true
        )
        return ControlItemPair(hidden: hidden, alwaysHidden: nil)
    }

    @Test("A ⌘-drag becomes the saved order while the hold is still on")
    func userDragSkipsTheHold() {
        let key = "MenuBarItemManager.savedSectionOrder"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let visible = [Self.item(x: 1600, windowID: 1), Self.item(x: 1700, windowID: 2)]
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = visible
        let manager = MenuBarItemManager()
        let visibleKey = MenuBarSectionName.visible.rawValue
        let saved = [visibleKey: visible.reversed().map(\.uniqueIdentifier)]
        manager.savedSectionOrder = saved
        manager.barSettling.note(.screensWoke)

        manager.mirrorSavedSectionOrderIfSettled(from: cache, displays: Self.displays)
        #expect(manager.savedSectionOrder == saved)

        manager.mirrorSavedSectionOrderIfSettled(from: cache, placedByUser: true, displays: Self.displays)
        #expect(manager.savedSectionOrder[visibleKey] == visible.map(\.uniqueIdentifier))
    }
}
