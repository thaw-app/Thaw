//
//  MoveFailureDiagnosticReportTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Testing
@testable import Thaw

/// The parts of the report that need no live menu bar: which log lines it
/// keeps and how it names its file.
@Suite("Move failure diagnostic report")
struct MoveFailureDiagnosticReportTests {
    @Test("The log excerpt keeps move-engine categories and drops the rest")
    func logFilter() {
        let lines = [
            "2026-08-28 22:16:43.817 [DEBUG] [MenuBarItemManager] Move points: startX=-3733.0",
            "2026-08-28 22:16:43.818 [INFO] [SystemStateMonitor] wifi=HomeNet",
            "2026-08-28 22:16:43.819 [DEBUG] [Bridging] getMenuBarWindowList: 11 raw",
            "2026-08-28 22:16:43.820 [ERROR] [LayoutBarPaddingView] Error moving menu bar item",
            "not a log line",
        ]

        #expect(MoveFailureDiagnosticReport.filterLogLines(lines) == [lines[0], lines[3]])
    }

    @Test("The log excerpt is capped to the newest lines")
    func logCap() {
        let lines = (0 ..< 10).map { index in
            "2026-08-28 22:16:43.\(String(format: "%03d", index)) [DEBUG] [MenuBarItemManager] line \(index)"
        }

        let kept = MoveFailureDiagnosticReport.filterLogLines(lines, limit: 3).map { String($0.suffix(6)) }

        #expect(kept == ["line 7", "line 8", "line 9"])
    }

    @Test("The category is the second bracketed field")
    func logCategory() {
        #expect(MoveFailureDiagnosticReport.logCategory(of: "2026-08-28 22:16:43.817 [DEBUG] [MenuBarItem] created 10 items") == "MenuBarItem")
        #expect(MoveFailureDiagnosticReport.logCategory(of: "Started: 2026-08-28 22:16:43") == nil)
    }

    @Test("The suggested file name carries the app name and a timestamp")
    func fileName() {
        let name = MoveFailureDiagnosticReport.suggestedFileName(for: Date(timeIntervalSince1970: 0))

        #expect(name.hasPrefix("\(Constants.displayName)-move-diagnostic-"))
        #expect(name.hasSuffix(".txt"))
    }

    @Test("The report reuses the default OK button and adds one working save button")
    @MainActor
    func alertButtons() {
        let alerts = [
            NSAlert(),
            NSAlert(error: NSError(domain: "MoveFailureDiagnosticReportTests", code: 1)),
        ]

        for alert in alerts {
            let saveResponse = MoveFailureDiagnosticReport.configureButtons(on: alert)

            #expect(alert.buttons.map(\.title) == [String(localized: "OK"), String(localized: "Save Diagnostic Report…")])
            #expect(saveResponse == .alertSecondButtonReturn)
        }
    }

    @Test("Export writes the exact redacted report text")
    func export() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-move-diagnostic.txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let report = MoveFailureDiagnosticReport(
            text: "user=<user> network=<wifi-network>\n",
            suggestedFileName: url.lastPathComponent
        )

        try report.write(to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == report.text)
    }
}
