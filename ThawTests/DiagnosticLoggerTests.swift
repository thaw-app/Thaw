//
//  DiagnosticLoggerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

// MARK: - DiagnosticLogger.Level Tests

/// Pins the raw values of ``DiagnosticLogger/Level``.
///
/// The raw values are written verbatim into every diagnostic log line, so
/// they are a parsed format rather than an implementation detail.
///
/// Reads only: nothing here reaches the shared ``DiagnosticLogger`` or any
/// other process-global state, so the suite is safe to run in parallel with
/// the rest.
@Suite("Diagnostic logger levels")
struct DiagnosticLoggerLevelTests {
    // MARK: - Raw Values

    @Test("The debug level's raw value is DEBUG")
    func debugRawValue() {
        #expect(DiagnosticLogger.Level.debug.rawValue == "DEBUG")
    }

    @Test("The info level's raw value is INFO")
    func infoRawValue() {
        #expect(DiagnosticLogger.Level.info.rawValue == "INFO")
    }

    @Test("The notice level's raw value is NOTICE")
    func noticeRawValue() {
        #expect(DiagnosticLogger.Level.notice.rawValue == "NOTICE")
    }

    @Test("The warning level's raw value is WARNING")
    func warningRawValue() {
        #expect(DiagnosticLogger.Level.warning.rawValue == "WARNING")
    }

    @Test("The error level's raw value is ERROR")
    func errorRawValue() {
        #expect(DiagnosticLogger.Level.error.rawValue == "ERROR")
    }

    // MARK: - Init From Raw Value

    @Test("DEBUG initializes the debug level")
    func initFromDebugRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "DEBUG")
        #expect(level == .debug)
    }

    @Test("INFO initializes the info level")
    func initFromInfoRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "INFO")
        #expect(level == .info)
    }

    @Test("NOTICE initializes the notice level")
    func initFromNoticeRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "NOTICE")
        #expect(level == .notice)
    }

    @Test("WARNING initializes the warning level")
    func initFromWarningRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "WARNING")
        #expect(level == .warning)
    }

    @Test("ERROR initializes the error level")
    func initFromErrorRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "ERROR")
        #expect(level == .error)
    }

    @Test("An unrecognized raw value initializes nothing")
    func initFromInvalidRawValue() {
        let level = DiagnosticLogger.Level(rawValue: "INVALID")
        #expect(level == nil)
    }

    @Test("A lowercase raw value initializes nothing")
    func initFromLowercaseRawValue() {
        // Raw values are case-sensitive
        let level = DiagnosticLogger.Level(rawValue: "debug")
        #expect(level == nil)
    }

    // MARK: - All Levels

    @Test("Every level has an uppercase raw value")
    func allLevelsHaveUppercaseRawValues() {
        let levels: [DiagnosticLogger.Level] = [.debug, .info, .notice, .warning, .error]

        for level in levels {
            #expect(level.rawValue == level.rawValue.uppercased(),
                    "Level \(level) should have uppercase raw value")
        }
    }

    @Test("Every level has a distinct raw value")
    func allLevelsAreDistinct() {
        let levels: [DiagnosticLogger.Level] = [.debug, .info, .notice, .warning, .error]
        let rawValues = Set(levels.map(\.rawValue))

        #expect(rawValues.count == levels.count,
                "All levels should have distinct raw values")
    }
}
