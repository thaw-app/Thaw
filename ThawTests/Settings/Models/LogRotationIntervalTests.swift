//
//  LogRotationIntervalTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@Suite("Log rotation interval")
struct LogRotationIntervalTests {
    @Test("Seconds map to the documented intervals")
    func secondsMapping() {
        #expect(LogRotationInterval.off.seconds == 0)
        #expect(LogRotationInterval.hourly.seconds == 3600)
        #expect(LogRotationInterval.daily.seconds == 86400)
    }

    @Test("Raw values are stable strings")
    func rawValues() {
        #expect(LogRotationInterval.off.rawValue == "off")
        #expect(LogRotationInterval.hourly.rawValue == "hourly")
        #expect(LogRotationInterval.daily.rawValue == "daily")
        #expect(LogRotationInterval(rawValue: "hourly") == .hourly)
        #expect(LogRotationInterval(rawValue: "weekly") == nil)
    }

    @Test("Identifiers match the raw values")
    func identifiers() {
        for interval in LogRotationInterval.allCases {
            #expect(interval.id == interval.rawValue)
        }
    }

    @Test("All cases are off, hourly, daily in order")
    func caseOrder() {
        #expect(LogRotationInterval.allCases == [.off, .hourly, .daily])
    }

    @Test("Every case carries a localized label")
    func localizedLabels() {
        for interval in LogRotationInterval.allCases {
            #expect(!"\(interval.localized)".isEmpty)
        }
    }
}
