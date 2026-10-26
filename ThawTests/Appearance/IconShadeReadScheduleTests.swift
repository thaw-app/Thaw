//
//  IconShadeReadScheduleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("When the overlay reads the icons' shade")
struct IconShadeReadScheduleTests {
    private let dark = MenuBarAverageColorInfo(color: NSColor.black.cgColor, source: .menuBarWindow)
    private let light = MenuBarAverageColorInfo(color: NSColor.white.cgColor, source: .menuBarWindow)

    /// Runs each step on one schedule and returns what each answered.
    private func answers(_ steps: [(inout IconShadeReadSchedule) -> Bool]) -> [Bool] {
        var schedule = IconShadeReadSchedule()
        return steps.map { $0(&schedule) }
    }

    private func start(
        bar: MenuBarAverageColorInfo?,
        hasShade: Bool
    ) -> (inout IconShadeReadSchedule) -> Bool {
        { $0.shouldStart(bar: bar, hasShade: hasShade) }
    }

    private func finish(found: Bool) -> (inout IconShadeReadSchedule) -> Bool {
        { $0.finish(found: found) }
    }

    @Test("An unknown shade is read once at a time, and a known one only when the bar changes")
    func oneReadAtATime() {
        let result = answers([
            start(bar: dark, hasShade: false),
            start(bar: dark, hasShade: false),
            finish(found: true),
            start(bar: dark, hasShade: true),
            start(bar: light, hasShade: true),
        ])
        #expect(result == [true, false, false, false, true])
    }

    @Test("A bar change during a read gets a read of its own once that one ends")
    func barChangeDuringRead() {
        let result = answers([
            start(bar: dark, hasShade: false),
            start(bar: light, hasShade: false),
            finish(found: true),
            start(bar: light, hasShade: true),
            finish(found: true),
        ])
        #expect(result == [true, false, true, true, false])
    }

    @Test("After a read finds nothing, only a bar change reads again")
    func failedReadWaitsForBarChange() {
        let result = answers([
            start(bar: dark, hasShade: false),
            finish(found: false),
            start(bar: dark, hasShade: false),
            start(bar: light, hasShade: false),
            finish(found: true),
            { !$0.isReading },
        ])
        #expect(result == [true, false, false, true, false, true])
    }

    @Test("A cancelled read is forgotten, and the next start reads the bar afresh")
    func resetForgetsTheRead() {
        let result = answers([
            start(bar: dark, hasShade: false),
            start(bar: light, hasShade: false),
            { schedule in
                schedule.reset()
                return !schedule.isReading
            },
            start(bar: light, hasShade: true),
            finish(found: true),
        ])
        #expect(result == [true, false, true, true, false])
    }

    @Test("The same bar again reads nothing, as when only another display's average changed")
    func unchangedBarReadsNothing() {
        let result = answers([
            start(bar: dark, hasShade: false),
            finish(found: true),
            start(bar: dark, hasShade: true),
            start(bar: dark, hasShade: true),
        ])
        #expect(result == [true, false, false, false])
    }

    @Test("A bar change while no finish followed the shade reads once one does again")
    func barChangeWhileNotFollowed() {
        // Nothing asks while no finish follows the shade, so the next start sees the new bar.
        let result = answers([
            start(bar: dark, hasShade: false),
            finish(found: true),
            start(bar: light, hasShade: true),
        ])
        #expect(result == [true, false, true])
    }
}
