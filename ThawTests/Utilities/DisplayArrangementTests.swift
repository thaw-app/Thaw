//
//  DisplayArrangementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// How a change is classified is pinned in EnvironmentSnapshotTests.
@Suite("Display arrangement")
struct DisplayArrangementTests {
    @Test("The current arrangement names a main display exactly when it has displays")
    @MainActor
    func currentReading() {
        let reading = DisplayArrangement.current
        #expect(reading.frames.isEmpty == (reading.mainDisplayID == nil))
    }
}
