//
//  DiagnosticsLayoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// Troubleshooting's Diagnostics rows, laid out like the rest of Settings.
@MainActor
@Suite("Diagnostics layout", .serialized, .scratchDefaults)
struct DiagnosticsLayoutTests {
    /// The view's height in a grouped form as wide as a Settings pane.
    private func formHeight(_ content: some View, appState: AppState) -> CGFloat {
        let host = NSHostingView(rootView: Form { content }
            .formStyle(.grouped)
            .environment(appState)
            .frame(width: 560))
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 2000)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("The bug-report files are two rows with their actions beside them, not stacked buttons")
    func filesSectionIsTwoRows() {
        let appState = AppState()
        let height = formHeight(DiagnosticFilesSection(), appState: appState)
        #expect(height > 0)
        // Two rows of a title, one line of detail and a button capsule. Buttons
        // stacked under the titles would roughly double this.
        #expect(height < 220, "got \(height)")
    }

    @Test("The log settings are three compact rows")
    func logRowsAreCompact() {
        let appState = AppState()
        let height = formHeight(DiagnosticLogRotationRows(settings: appState.settings.tools), appState: appState)
        #expect(height > 0)
        #expect(height < 260, "got \(height)")
    }

    @Test("The log rows show only while detailed logging is on")
    func logRowsFollowLogging() async throws {
        let appState = AppState()
        appState.settings.tools.enableDiagnosticLogging = false
        let size = CGSize(width: 760, height: 1600)
        let render = OffscreenRender(
            ToolsSettingsPane(settings: appState.settings.tools)
                .environment(appState)
                .environment(\.settingsPaneTitle, nil)
                .frame(width: size.width, height: size.height),
            size: size
        )
        await render.settle { (try? render.pixels())?.contains { $0 != 0 } == true }
        let off = try render.pixels()
        appState.settings.tools.enableDiagnosticLogging = true
        await render.settle { (try? render.pixels()) != off }
        #expect(try render.pixels() != off)
    }

    @Test("A search result in the bug-report files opens Diagnostics")
    func filesSectionOpensDiagnostics() {
        #expect(TroubleshootingTab(section: "Files for a bug report") == .diagnostics)
    }

    @Test("Retention reads in days, singular for one")
    func retentionDays() {
        #expect(DiagnosticLogRotationRows.days(1) == "1 day")
        #expect(DiagnosticLogRotationRows.days(7) == "7 days")
    }
}
