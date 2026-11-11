//
//  DiagnosticLoggerRotationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Diagnostic log rotation")
struct DiagnosticLoggerRotationTests {
    private typealias Policy = DiagnosticLogger.RotationPolicy

    @Test("A stored value out of range can't delete every log or overflow")
    func sanitizing() {
        let wild = Policy(maxFileSizeBytes: .max, rotationInterval: .infinity, retentionDays: -5, maxFileCount: 0).sanitized()
        #expect(wild.retentionDays == 1)
        #expect(wild.maxFileCount == 1)
        #expect(wild.maxFileSizeBytes == Policy.maxSizeBytes)
        #expect(wild.rotationInterval == 0)
        #expect(Policy(rotationInterval: -1).sanitized().rotationInterval == 0)
        #expect(Policy(retentionDays: 30).sanitized().retentionDays == 30)
    }

    @Test("A file rotates once it reaches the size or the age, and never when both are off")
    func rotating() {
        let size = Policy(maxFileSizeBytes: 100)
        #expect(!DiagnosticLogger.shouldRotate(policy: size, fileSize: 99, openFor: 1e9))
        #expect(DiagnosticLogger.shouldRotate(policy: size, fileSize: 100, openFor: 0))
        let hourly = Policy(rotationInterval: 3600)
        #expect(!DiagnosticLogger.shouldRotate(policy: hourly, fileSize: .max, openFor: 3599))
        #expect(DiagnosticLogger.shouldRotate(policy: hourly, fileSize: 0, openFor: 3600))
        #expect(!DiagnosticLogger.shouldRotate(policy: Policy(), fileSize: .max, openFor: 1e9))
    }

    @Test("Pruning drops files past the retention or the count, never the open one")
    func pruning() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func file(_ name: String, daysAgo: Double) -> (url: URL, created: Date) {
            (URL(fileURLWithPath: "/logs/\(name).log"), now.addingTimeInterval(-daysAgo * 86400))
        }
        let files = [file("a", daysAgo: 0.1), file("b", daysAgo: 1), file("c", daysAgo: 3), file("open", daysAgo: 9)]
        let open = URL(fileURLWithPath: "/logs/open.log")

        let byAge = DiagnosticLogger.filesToPrune(files, retentionDays: 2, maxCount: 50, now: now, protected: [open])
        #expect(byAge.map(\.lastPathComponent) == ["c.log"])

        let byCount = DiagnosticLogger.filesToPrune(files, retentionDays: 30, maxCount: 2, now: now, protected: [open])
        #expect(byCount.map(\.lastPathComponent) == ["b.log", "c.log"], "the open file counts against the cap")
    }

    @Test("Two files in one second get distinct names")
    func uniqueNames() {
        let dir = URL(fileURLWithPath: "/logs")
        var taken: Set = ["/logs/thaw_x.log"]
        let second = DiagnosticLogger.uniqueLogFileURL(in: dir, baseName: "thaw_x") { taken.contains($0.path) }
        #expect(second.lastPathComponent == "thaw_x_2.log")
        taken.insert(second.path)
        #expect(DiagnosticLogger.uniqueLogFileURL(in: dir, baseName: "thaw_x") { taken.contains($0.path) }.lastPathComponent == "thaw_x_3.log")
    }
}
