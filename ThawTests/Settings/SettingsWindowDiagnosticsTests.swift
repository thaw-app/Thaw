//
//  SettingsWindowDiagnosticsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
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

    @Test("A reading takes the window's own frames, style and scale, and the settings passed in")
    func readingOfAWindow() {
        // Never shown, so it has no screen.
        let window = NSWindow(
            contentRect: CGRect(x: 40, y: 60, width: 500, height: 300),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        let reading = SettingsWindowDiagnostics.reading(of: window, zoomPercent: 125, isSimpleMode: true)

        #expect(reading.frame == window.frame)
        #expect(reading.contentLayout == window.contentLayoutRect)
        #expect(reading.contentView == window.contentView?.frame)
        #expect(reading.screen == (window.screen?.frame ?? .zero))
        #expect(reading.backingScale == window.backingScaleFactor)
        #expect(reading.hasFullSizeContent)
        #expect(reading.zoomPercent == 125)
        #expect(reading.isSimpleMode)
        #expect(!SettingsWindowDiagnostics.reading(
            of: NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true),
            zoomPercent: 100,
            isSimpleMode: false
        ).hasFullSizeContent)
    }
}
