//
//  MovePipelineMonitorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
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
        #expect(monitor.dragMoveCount == 0)
        let record = try #require(monitor.records.first)
        #expect(record.itemDescription == "Clock")
        #expect(record.destinationDescription == "Hidden")
        #expect(record.channelDescription == "preferred positions")
        #expect(record.attempts.isEmpty)
        #expect(record.duration == nil)
        #expect(record.succeeded)
    }

    @Test("A drag move tallies attempts by address")
    func dragMoveTalliesAttempts() throws {
        let monitor = MovePipelineMonitor()
        let record = SyntheticMoveEngine.DragAddress.eventRecord(pid: 412, window: 9, frame: .zero)

        monitor.recordDragMove(
            item: "Wi-Fi",
            destination: "Visible",
            attempts: [
                (record, false),
                (.process(412), false),
                (.hidEventTap, true),
            ],
            duration: .milliseconds(300),
            succeeded: true
        )

        #expect(monitor.dragMoveCount == 1)
        #expect(monitor.eventRecordAttemptCount == 1)
        #expect(monitor.eventRecordLandCount == 0)
        #expect(monitor.hidAttemptCount == 2)
        #expect(monitor.hidLandCount == 1)
        let entry = try #require(monitor.records.first)
        #expect(entry.channelDescription == "command-drag")
        #expect(entry.attempts.map(\.addressDescription) == [
            "event record pid 412 window 9", "pid 412", "hidEventTap",
        ])
        #expect(entry.attempts.map(\.landed) == [false, false, true])
        #expect(entry.duration == .milliseconds(300))
    }

    @Test("A landed event-record attempt counts as a land")
    func eventRecordLandCounts() {
        let monitor = MovePipelineMonitor()
        monitor.recordDragMove(
            item: "A",
            destination: "B",
            attempts: [(.eventRecord(pid: 1, window: 2, frame: .zero), true)],
            duration: .zero,
            succeeded: true
        )
        #expect(monitor.eventRecordLandCount == 1)
        #expect(monitor.hidAttemptCount == 0)
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
