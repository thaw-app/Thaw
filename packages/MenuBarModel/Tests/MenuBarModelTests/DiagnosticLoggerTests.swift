//
//  DiagnosticLoggerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Diagnostic logger")
struct DiagnosticLoggerTests {
    @Test("A test run logs to a temporary folder, a normal run to ~/Library/Logs/Thaw")
    func testRunsLogElsewhere() {
        let testRun = DiagnosticLogger.logDirectory(environment: ["XCTestSessionIdentifier": "1"])
        let normalRun = DiagnosticLogger.logDirectory(environment: [:])
        #expect(testRun.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(normalRun.path.hasSuffix("Library/Logs/Thaw"))
    }

    @Test("Each XCTest variable marks a test host", arguments: ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"])
    func testHostVariables(key: String) {
        #expect(TestHostEnvironment.isActive([key: "x"]))
        #expect(!TestHostEnvironment.isActive(["PATH": "/usr/bin"]))
    }

    @Test("Log-level wire values are stable and case-sensitive")
    func levelWireValues() {
        let expected: [(DiagnosticLogger.Level, String)] = [
            (.debug, "DEBUG"), (.info, "INFO"), (.notice, "NOTICE"), (.warning, "WARNING"), (.error, "ERROR"),
        ]
        for (level, rawValue) in expected {
            #expect(level.rawValue == rawValue)
            #expect(DiagnosticLogger.Level(rawValue: rawValue) == level)
            #expect(DiagnosticLogger.Level(rawValue: rawValue.lowercased()) == nil)
        }
    }
}

@Suite("Diagnostic log records")
struct DiagnosticLoggerRecordTests {
    @Test("A record is one line however many line breaks its text holds")
    func lineBreaksCantForgeRecords() {
        let record = DiagnosticLogger.record(
            timestamp: "2026-10-26 22:00:00.000",
            level: .info,
            category: "Hooks\n",
            message: "/tmp/a.sh\n2026-10-26 22:00:01.000 [ERROR] [Updates] forged\rmore\r\nend\u{2028}x\u{85}y\u{0B}z\u{0C}w"
        )

        #expect(record.filter(\.isNewline) == "\n")
        #expect(record.hasSuffix("\n"))
        #expect(record.contains("[Hooks\\n]"))
        #expect(record.contains("/tmp/a.sh\\n2026-10-26 22:00:01.000 [ERROR] [Updates] forged\\rmore\\r\\nend\\u{2028}x\\u{85}y\\u{b}z\\u{c}w"))
    }

    @Test("Text without line breaks is written as is")
    func plainTextUnchanged() {
        #expect(DiagnosticLogger.escapingLineBreaks("plain \\n text") == "plain \\n text")
        #expect(
            DiagnosticLogger.record(timestamp: "t", level: .error, category: "C", message: "m")
                == "t [ERROR] [C] m\n"
        )
    }
}

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

    @Test("The size is read from disk only at the limit or every check interval, never without a limit")
    func countingSize() {
        typealias Count = DiagnosticLogger.FileSizeCount
        var count = Count(bytes: 10)
        #expect(count.adding(5, limit: 0) == (15, false))
        #expect(count.adding(Count.checkInterval, limit: 0).needsCheck == false)

        count = Count(bytes: 10)
        #expect(count.adding(5, limit: 1000) == (15, false))
        #expect(count.adding(985, limit: 1000) == (1000, true))

        count = Count()
        #expect(count.adding(Count.checkInterval - 1, limit: .max).needsCheck == false)
        #expect(count.adding(1, limit: .max).needsCheck)
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

    @Test("An attached file gets a header and the records, rotates at its size limit, and gets a footer when logging stops")
    func fileLifecycle() throws {
        let logger = DiagnosticLogger.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let attached = dir.appendingPathComponent("attached.log")
        defer {
            logger.isEnabled = false
            logger.policyLock.withLock { $0 = nil }
            try? FileManager.default.removeItem(at: dir)
        }

        logger.attachToFile(at: attached)
        #expect(logger.currentLogFile == attached)
        logger.log(level: .info, category: "Test", message: "first")
        logger.writeQueue.sync {}
        logger.setRotationPolicy(DiagnosticLogger.RotationPolicy(maxFileSizeBytes: 1))
        logger.log(level: .info, category: "Test", message: "second")
        logger.writeQueue.sync {}

        let rotated = try #require(logger.currentLogFile)
        defer { try? FileManager.default.removeItem(at: rotated) }
        #expect(rotated != attached)
        logger.isEnabled = false
        #expect(logger.currentLogFile == nil)

        let attachedText = try String(contentsOf: attached, encoding: .utf8)
        for expected in ["Thaw Diagnostic Log", "[INFO] [Test] first", "[INFO] [Test] second", "Diagnostic logging stopped"] {
            #expect(attachedText.contains(expected))
        }
        let rotatedText = try String(contentsOf: rotated, encoding: .utf8)
        #expect(rotatedText.contains("Thaw Diagnostic Log"))
        #expect(rotatedText.contains("Diagnostic logging stopped"))
    }
}
