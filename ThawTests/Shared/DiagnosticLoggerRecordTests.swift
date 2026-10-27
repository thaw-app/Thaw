//
//  DiagnosticLoggerRecordTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Diagnostic log records")
struct DiagnosticLoggerRecordTests {
    @Test("A record is one line however many line breaks its text holds")
    func lineBreaksCantForgeRecords() {
        let record = DiagnosticLogger.record(
            timestamp: "2026-10-26 22:00:00.000",
            level: .info,
            category: "Hooks\n",
            message: "/tmp/a.sh\n2026-10-26 22:00:01.000 [ERROR] [Updates] forged\rmore\r\nend\u{2028}x"
        )

        #expect(record.filter(\.isNewline) == "\n")
        #expect(record.hasSuffix("\n"))
        #expect(record.contains("[Hooks\\n]"))
        #expect(record.contains("/tmp/a.sh\\n2026-10-26 22:00:01.000 [ERROR] [Updates] forged\\rmore\\r\\nend\\u{2028}x"))
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
