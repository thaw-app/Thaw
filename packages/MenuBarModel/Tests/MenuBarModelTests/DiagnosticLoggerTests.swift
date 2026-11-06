//
//  DiagnosticLoggerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
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

    @Test("Log-level wire values remain stable")
    func levelWireValuesRemainStable() {
        let expected: [(DiagnosticLogger.Level, String)] = [
            (.debug, "DEBUG"),
            (.info, "INFO"),
            (.notice, "NOTICE"),
            (.warning, "WARNING"),
            (.error, "ERROR"),
        ]

        for (level, rawValue) in expected {
            #expect(level.rawValue == rawValue)
            #expect(DiagnosticLogger.Level(rawValue: rawValue) == level)
        }
    }

    @Test("Log-level parsing is case-sensitive")
    func levelParsingIsCaseSensitive() {
        #expect(DiagnosticLogger.Level(rawValue: "debug") == nil)
        #expect(DiagnosticLogger.Level(rawValue: "INVALID") == nil)
    }
}
