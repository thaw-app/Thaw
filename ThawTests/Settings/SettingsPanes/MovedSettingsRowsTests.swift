//
//  MovedSettingsRowsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Rows moved between settings panes", .serialized)
struct MovedSettingsRowsTests {
    private func fittingSize(of view: some View) -> NSSize {
        let host = NSHostingView(rootView: view.frame(width: 480))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test("The diagnostic logging rows render")
    func diagnosticLoggingRowsRender() throws {
        try withScratchDefaults { _ in
            let settings = AdvancedSettings()
            #expect(fittingSize(of: DiagnosticLoggingRows(settings: settings)).height > 0)
        }
    }

    @Test("The language row renders")
    func languageRowRenders() {
        #expect(fittingSize(of: LanguageRow()).height > 0)
    }
}
