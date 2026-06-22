//
//  DiagnosticLoggerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - DiagnosticLogger.Level Tests

final class DiagnosticLoggerLevelTests: XCTestCase {
    // MARK: - Raw Values

    func testDebugRawValue() {
        XCTAssertEqual(DiagnosticLogger.Level.debug.rawValue, "DEBUG")
    }

    func testInfoRawValue() {
        XCTAssertEqual(DiagnosticLogger.Level.info.rawValue, "INFO")
    }

    func testNoticeRawValue() {
        XCTAssertEqual(DiagnosticLogger.Level.notice.rawValue, "NOTICE")
    }

    func testWarningRawValue() {
        XCTAssertEqual(DiagnosticLogger.Level.warning.rawValue, "WARNING")
    }

    func testErrorRawValue() {
        XCTAssertEqual(DiagnosticLogger.Level.error.rawValue, "ERROR")
    }

    // MARK: - Init From Raw Value

    func testInitFromDebugRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "DEBUG")
        XCTAssertEqual(level, .debug)
    }

    func testInitFromInfoRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "INFO")
        XCTAssertEqual(level, .info)
    }

    func testInitFromNoticeRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "NOTICE")
        XCTAssertEqual(level, .notice)
    }

    func testInitFromWarningRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "WARNING")
        XCTAssertEqual(level, .warning)
    }

    func testInitFromErrorRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "ERROR")
        XCTAssertEqual(level, .error)
    }

    func testInitFromInvalidRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "INVALID")
        XCTAssertNil(level)
    }

    func testInitFromLowercaseRawValue() {
        // Raw values are case-sensitive
        let level = DiagnosticLogger.Level(rawValue: "debug")
        XCTAssertNil(level)
    }

    // MARK: - All Levels

    func testAllLevelsHaveUppercaseRawValues() {
        let levels: [DiagnosticLogger.Level] = [.debug, .info, .notice, .warning, .error]

        for level in levels {
            XCTAssertEqual(level.rawValue, level.rawValue.uppercased(),
                           "Level \(level) should have uppercase raw value")
        }
    }

    func testAllLevelsAreDistinct() {
        let levels: [DiagnosticLogger.Level] = [.debug, .info, .notice, .warning, .error]
        let rawValues = Set(levels.map(\.rawValue))

        XCTAssertEqual(rawValues.count, levels.count,
                       "All levels should have distinct raw values")
    }
}

// MARK: - DiagnosticLogger Retention Tests

final class DiagnosticLoggerRetentionTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/tmp/ThawLogs", isDirectory: true)

    private func file(_ name: String) -> URL {
        dir.appendingPathComponent(name)
    }

    private func date(_ daysAgo: Double, from now: Date) -> Date {
        now.addingTimeInterval(-daysAgo * 86400)
    }

    func testRemovesFilesOlderThanRetention() {
        let now = Date()
        let fresh = file("thaw_fresh.log")
        let old = file("thaw_old.log")
        let files = [
            (url: fresh, created: date(0.5, from: now)),
            (url: old, created: date(5, from: now)),
        ]

        let prune = DiagnosticLogger.filesToPrune(
            files, retentionDays: 2, maxCount: 100, now: now, protected: []
        )

        XCTAssertEqual(prune, [old], "Only the file older than 2 days should be pruned")
    }

    func testNeverRemovesProtectedFiles() {
        let now = Date()
        let current = file("thaw_current.log")
        let previous = file("thaw_previous.log")
        let files = [
            (url: current, created: date(10, from: now)),
            (url: previous, created: date(9, from: now)),
        ]

        let prune = DiagnosticLogger.filesToPrune(
            files, retentionDays: 2, maxCount: 1, now: now, protected: [current, previous]
        )

        XCTAssertTrue(prune.isEmpty, "Protected files must never be pruned, even when old or over cap")
    }

    func testEnforcesMaxCountKeepingNewest() {
        let now = Date()
        let f1 = file("thaw_1.log")
        let f2 = file("thaw_2.log")
        let f3 = file("thaw_3.log")
        // All within retention, but cap is 2.
        let files = [
            (url: f1, created: date(0.1, from: now)),
            (url: f2, created: date(0.2, from: now)),
            (url: f3, created: date(0.3, from: now)),
        ]

        let prune = DiagnosticLogger.filesToPrune(
            files, retentionDays: 30, maxCount: 2, now: now, protected: []
        )

        XCTAssertEqual(prune, [f3], "Oldest file beyond the count cap should be pruned")
    }

    func testKeepsEverythingWithinLimits() {
        let now = Date()
        let files = [
            (url: file("thaw_a.log"), created: date(0.1, from: now)),
            (url: file("thaw_b.log"), created: date(0.2, from: now)),
        ]

        let prune = DiagnosticLogger.filesToPrune(
            files, retentionDays: 2, maxCount: 100, now: now, protected: []
        )

        XCTAssertTrue(prune.isEmpty, "Nothing should be pruned when within age and count limits")
    }
}

// MARK: - DiagnosticLogger Unique Filename Tests

final class DiagnosticLoggerUniqueNameTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/tmp/ThawLogs", isDirectory: true)

    func testReturnsBaseNameWhenFree() {
        let url = DiagnosticLogger.uniqueLogFileURL(
            in: dir, baseName: "thaw_2026-06-07_09-48-52", exists: { _ in false }
        )
        XCTAssertEqual(url.lastPathComponent, "thaw_2026-06-07_09-48-52.log")
    }

    func testAddsSuffixOnCollision() {
        let taken = Set([dir.appendingPathComponent("thaw_2026-06-07_09-48-52.log")])
        let url = DiagnosticLogger.uniqueLogFileURL(
            in: dir, baseName: "thaw_2026-06-07_09-48-52", exists: { taken.contains($0) }
        )
        XCTAssertEqual(url.lastPathComponent, "thaw_2026-06-07_09-48-52_2.log")
    }

    func testIncrementsUntilFree() {
        let taken = Set([
            dir.appendingPathComponent("thaw_2026-06-07_09-48-52.log"),
            dir.appendingPathComponent("thaw_2026-06-07_09-48-52_2.log"),
        ])
        let url = DiagnosticLogger.uniqueLogFileURL(
            in: dir, baseName: "thaw_2026-06-07_09-48-52", exists: { taken.contains($0) }
        )
        XCTAssertEqual(url.lastPathComponent, "thaw_2026-06-07_09-48-52_3.log")
    }
}
