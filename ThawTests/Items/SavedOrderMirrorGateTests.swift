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

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int(seconds * 1000))
    }

    @Test("A quiet bar may be mirrored")
    func quietBarMirrors() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(3)))
    }

    @Test("An item arriving holds the mirror past the agent's rewrite 10 s later")
    func arrivalHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        #expect(!gate.allowsMirror(identifiers: items.union(["d"]), restrictionChange: nil, now: at(1)))
        #expect(!gate.allowsMirror(identifiers: items.union(["d"]), restrictionChange: nil, now: at(11.5)))
        #expect(gate.allowsMirror(identifiers: items.union(["d"]), restrictionChange: nil, now: at(13.5)))
    }

    @Test("An item leaving holds the mirror too")
    func departureHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        #expect(!gate.allowsMirror(identifiers: ["a", "b"], restrictionChange: nil, now: at(1)))
    }

    @Test("One item swapped for another in the same pass holds the mirror")
    func swapHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        #expect(!gate.allowsMirror(identifiers: ["a", "b", "d"], restrictionChange: nil, now: at(1)))
    }

    @Test("A recent hiding change holds the mirror")
    func restrictionChangeHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: at(1), now: at(2)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: at(1), now: at(14)))
    }

    @Test("A wake or display change holds the mirror")
    func systemEventHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        _ = gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0))
        gate.noteDisturbance(at: at(10))
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(12)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(23)))
    }

    @Test("The quiet rule on its own")
    func quietRule() {
        #expect(SavedOrderMirrorGate.isQuiet(now: at(10), events: [nil, at(2)], quietPeriod: .seconds(5)))
        #expect(!SavedOrderMirrorGate.isQuiet(now: at(10), events: [at(2), at(8)], quietPeriod: .seconds(5)))
        #expect(SavedOrderMirrorGate.isQuiet(now: at(10), events: [], quietPeriod: .seconds(5)))
    }

    @Test("A revealed section holds the mirror, and the hold outlasts the reveal")
    func revealedSectionHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0)))
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: nil, sectionRevealed: true, now: at(1)))
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: nil, sectionRevealed: true, now: at(20)))
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(25)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(32.5)))
    }

    @Test("An item with a transient frame holds the mirror past the moment it settles")
    func transientFrameHoldsTheMirror() {
        let gate = SavedOrderMirrorGate(observesSystem: false)
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(0)))
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: nil, transientFrame: "a at x 0", now: at(1)))
        #expect(!gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(12.5)))
        #expect(gate.allowsMirror(identifiers: items, restrictionChange: nil, now: at(13.5)))
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
}
