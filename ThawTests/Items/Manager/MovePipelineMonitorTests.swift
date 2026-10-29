//
//  MovePipelineMonitorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("The move pipeline monitor records what each reorder did")
struct MovePipelineMonitorTests {
    @Test("A store move counts and records a preferred-position entry")
    func storeMoveRecord() throws {
        let monitor = MovePipelineMonitor()

        monitor.recordStoreMove(item: "Clock", destination: "Hidden", satisfied: true)

        #expect(monitor.storeMoveCount == 1)
        let record = try #require(monitor.records.first)
        #expect(record.itemDescription == "Clock")
        #expect(record.destinationDescription == "Hidden")
        #expect(record.succeeded)
    }

    @Test("Records are newest first and capped at 25")
    func recordsAreCapped() {
        let monitor = MovePipelineMonitor()
        for index in 0 ..< 30 {
            monitor.recordStoreMove(item: "Item \(index)", destination: "Hidden", satisfied: index.isMultiple(of: 2))
        }
        #expect(monitor.records.count == 25)
        #expect(monitor.records.first?.itemDescription == "Item 29")
        #expect(monitor.records.last?.itemDescription == "Item 5")
        #expect(monitor.storeMoveCount == 30)
    }

    @Test("An unreachable position table is remembered")
    func storeUnavailable() {
        let monitor = MovePipelineMonitor()
        #expect(!monitor.sawStoreUnavailable)
        monitor.recordStoreUnavailable()
        #expect(monitor.sawStoreUnavailable)
    }
}
