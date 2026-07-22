//
//  DiagnosticLoggerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing

@Suite("Diagnostic logger")
struct DiagnosticLoggerTests {
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
