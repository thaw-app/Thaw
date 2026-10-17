//
//  DisplayArrangementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// A display change with the same number of displays still counts as a change.
@Suite("Display arrangement")
struct DisplayArrangementTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    private func arrangement(_ frames: [CGDirectDisplayID: CGRect], main: CGDirectDisplayID? = 1) -> DisplayArrangement {
        DisplayArrangement(frames: frames, mainDisplayID: main)
    }

    @Test("The same displays in the same places are unchanged")
    func unchanged() {
        let reading = arrangement([1: builtIn, 2: external])
        #expect(reading.change(from: reading) == .unchanged)
    }

    @Test("More displays is a connect, fewer is a disconnect")
    func countChanges() {
        let one = arrangement([1: builtIn])
        let two = arrangement([1: builtIn, 2: external])
        #expect(two.change(from: one) == .connected)
        #expect(one.change(from: two) == .disconnected)
    }

    @Test("A display swapped for another of the same count is a rearrangement")
    func swappedDisplay() {
        let before = arrangement([1: builtIn, 2: external])
        let after = arrangement([1: builtIn, 3: external])
        #expect(after.change(from: before) == .rearranged)
    }

    @Test("A display moved to another side is a rearrangement")
    func movedDisplay() {
        let before = arrangement([1: builtIn, 2: external])
        let after = arrangement([1: builtIn, 2: external.offsetBy(dx: -4072, dy: 0)])
        #expect(after.change(from: before) == .rearranged)
    }

    @Test("Another main display is a rearrangement")
    func newMainDisplay() {
        let before = arrangement([1: builtIn, 2: external], main: 1)
        let after = arrangement([1: builtIn, 2: external], main: 2)
        #expect(after.change(from: before) == .rearranged)
    }

    @Test("Each change has its own settling reason and log text")
    func reasons() {
        let changes: [DisplayArrangement.Change] = [.unchanged, .connected, .disconnected, .rearranged]
        #expect(Set(changes.map(\.settlingReason)).count == changes.count)
        #expect(Set(changes.map(\.logDescription)).count == changes.count)
        #expect(DisplayArrangement.Change.connected.settlingReason == "displayConnect")
        #expect(DisplayArrangement.Change.disconnected.settlingReason == "displayDisconnect")
    }

    @Test("The watch compares each reading with the one before it")
    func watch() {
        let one = arrangement([1: builtIn])
        let two = arrangement([1: builtIn, 2: external])
        var watch = DisplayArrangementWatch(one)
        #expect(watch.update(to: one) == .unchanged)
        #expect(watch.update(to: two) == .connected)
        #expect(watch.update(to: two) == .unchanged)
        #expect(watch.last == two)
    }

    @Test("The current arrangement can be read")
    @MainActor
    func currentReading() {
        let reading = DisplayArrangement.current
        #expect(reading.change(from: reading) == .unchanged)
    }
}
