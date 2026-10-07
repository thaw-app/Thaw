//
//  SettingsWindowDiagnosticsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("The Settings window's geometry is written to the diagnostic log")
struct SettingsWindowDiagnosticsTests {
    private let reading = SettingsWindowDiagnostics.Reading(
        frame: CGRect(x: 120, y: 80, width: 900, height: 640),
        contentLayout: CGRect(x: 0, y: 0, width: 900, height: 588),
        contentView: CGRect(x: 0, y: 0, width: 900, height: 640),
        screen: CGRect(x: 0, y: 0, width: 3008, height: 1692),
        backingScale: 2,
        hasFullSizeContent: true,
        zoomPercent: 110,
        isSimpleMode: false
    )

    @Test("The title bar and toolbar are what the content layout leaves out")
    func chromeHeightIsTheDifference() {
        #expect(reading.chromeHeight == 52)
    }

    @Test("The line carries the sizes, the zoom and the layout")
    func summaryNamesEverything() {
        #expect(reading.summary == "window=900x640 at (120, 80) contentLayout=900x588 contentView=900x640"
            + " chromeHeight=52 fullSizeContent=true screen=3008x1692 backingScale=2.0 uiZoom=110% layout=full")
    }
}
