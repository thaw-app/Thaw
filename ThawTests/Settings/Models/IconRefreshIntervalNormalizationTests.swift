//
//  IconRefreshIntervalNormalizationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins ``AdvancedSettings.normalizedIconRefreshInterval`` to the discrete
/// grid the "Icon refresh rate" slider can express: Off, or 1…30 fps.
///
/// Pure function; safe to run in parallel with the rest of the suite.
@Suite("Icon refresh interval normalization")
struct IconRefreshIntervalNormalizationTests {
    @Test("Zero stays Off")
    func zeroStaysOff() {
        #expect(AdvancedSettings.normalizedIconRefreshInterval(0) == 0)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(-1) == 0)
    }

    @Test("A rate above the capture ceiling snaps down to it")
    func ceilingClamp() {
        let ceiling = MenuBarItemImageCache.maxIconRefreshRate
        let floor = MenuBarItemImageCache.minIconRefreshInterval
        #expect(AdvancedSettings.normalizedIconRefreshInterval(1.0 / 30.0) == floor)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(1.0 / 60.0) == floor)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(floor / 2) == floor)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(1.0 / ceiling) == floor)
    }

    @Test("Slow intervals snap to 1 fps rather than displaying as Off")
    func slowValuesSnapToOneFPS() {
        #expect(AdvancedSettings.normalizedIconRefreshInterval(3.0) == 1.0)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(5.0) == 1.0)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(2.5) == 1.0)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(3.5) == 1.0)
    }

    @Test("A sub-millisecond interval snaps to the floor instead of a zero sleep")
    func subMillisecondSnapsToFloor() {
        let floor = MenuBarItemImageCache.minIconRefreshInterval
        #expect(AdvancedSettings.normalizedIconRefreshInterval(0.0001) == floor)
        #expect(AdvancedSettings.normalizedIconRefreshInterval(0.0005) == floor)
    }

    @Test("Already-on-grid values are idempotent")
    func idempotent() {
        #expect(AdvancedSettings.normalizedIconRefreshInterval(0) == 0)
        let ceiling = Int(MenuBarItemImageCache.maxIconRefreshRate)
        for fps in 1 ... ceiling {
            let interval = 1.0 / Double(fps)
            let once = AdvancedSettings.normalizedIconRefreshInterval(interval)
            let twice = AdvancedSettings.normalizedIconRefreshInterval(once)
            #expect(once == twice)
            #expect(abs(1.0 / once - Double(fps)) < 1e-9)
        }
    }

    @Test("Every on-grid interval survives an interval → fps → interval round trip")
    func roundTrip() {
        let ceiling = Int(MenuBarItemImageCache.maxIconRefreshRate)
        for fps in 0 ... ceiling {
            let interval: TimeInterval = fps == 0 ? 0 : 1.0 / Double(fps)
            let normalized = AdvancedSettings.normalizedIconRefreshInterval(interval)
            let displayedFPS = normalized > 0 ? (1.0 / normalized).rounded() : 0
            let restored: TimeInterval = displayedFPS > 0 ? 1.0 / displayedFPS : 0
            #expect(AdvancedSettings.normalizedIconRefreshInterval(restored) == normalized)
            #expect(Int(displayedFPS) == fps)
        }
    }
}
