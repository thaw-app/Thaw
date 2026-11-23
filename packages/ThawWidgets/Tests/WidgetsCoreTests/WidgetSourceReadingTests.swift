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

    @Test("The battery reads as charging only while the power source says so")
    func batteryCharging() {
        #expect(BatteryLevelSource.isCharging(from: [kIOPSIsChargingKey: true]))
        #expect(!BatteryLevelSource.isCharging(from: [kIOPSIsChargingKey: false, kIOPSPowerSourceStateKey: kIOPSACPowerValue]))
        #expect(!BatteryLevelSource.isCharging(from: [:]))
        let reading = BatteryLevelSource.reading()
        #expect((0 ... 1).contains(reading.level))
        #expect(BatteryLevelSource.level() == reading.level)
    }

    @Test("The CPU source reads one counter per logical processor")
    func cpuTicks() throws {
        let source = CPUSource()
        #expect(try source.readTicks().cores.count == ProcessInfo.processInfo.processorCount)
    }

    @Test("A tick counter past 2^31 reads as a large count, not a crash")
    func cpuTicksPastSignedRange() {
        // Mach keeps the counters unsigned but hands them over as integer_t,
        // so one that passes 2^31 after about 248 days awake arrives negative.
        #expect(CPUSource.ticks(integer_t(42)) == 42)
        #expect(CPUSource.ticks(integer_t.min) == 1 << 31)
        #expect(CPUSource.ticks(-1) == UInt64(UInt32.max))
    }
}
