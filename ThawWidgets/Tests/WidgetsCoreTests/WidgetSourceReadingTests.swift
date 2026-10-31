//
//  WidgetSourceReadingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import IOKit.ps
import Testing
@testable import WidgetsCore

@Suite("Widget sources read what the system reports")
struct WidgetSourceReadingTests {
    @Test("Battery level is the current capacity over the maximum")
    func batteryFraction() {
        #expect(BatteryLevelSource.level(from: [kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 80]) == 0.5)
        #expect(BatteryLevelSource.level(from: [kIOPSCurrentCapacityKey: 100, kIOPSMaxCapacityKey: 100]) == 1)
    }

    @Test("A missing or zero maximum never divides by zero")
    func batteryWithoutMaximum() {
        #expect(BatteryLevelSource.level(from: [kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 0]) == 0)
        #expect(BatteryLevelSource.level(from: [kIOPSCurrentCapacityKey: 1]) == 1)
        #expect(BatteryLevelSource.level(from: [:]) == 0)
    }

    @Test("The CPU source reads one counter per logical processor")
    func cpuTicks() throws {
        let source = CPUSource()
        #expect(try source.readTicks().cores.count == ProcessInfo.processInfo.processorCount)
    }
}
