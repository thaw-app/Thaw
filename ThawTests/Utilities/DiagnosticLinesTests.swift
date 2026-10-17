//
//  DiagnosticLinesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Diagnostic log lines")
struct DiagnosticLinesTests {
    @Test("A display change names each display's ID, frame and the main one")
    func screensChanged() {
        let line = DiagnosticLines.screensChanged([
            (id: 3, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true),
            (id: 1, frame: CGRect(x: -2048, y: 0, width: 2048, height: 1152), isMain: false),
        ])
        #expect(line.hasPrefix("Screen parameters changed, 2 screen(s) connected: "))
        #expect(line.contains("3=(0.0, 0.0, 2560.0, 1440.0) main"))
        #expect(line.contains("1=(-2048.0, 0.0, 2048.0, 1152.0)"))
        #expect(!line.contains("1152.0) main"))
    }

    @Test("A boundary repair line carries the frames it compared")
    func boundaryRepair() {
        let line = DiagnosticLines.boundaryRepair(
            item: "Little Snitch", itemX: 1478, section: "hidden section",
            hiddenDividerX: 1686.5, alwaysHiddenDividerX: 1685.5, revealed: "hidden section"
        )
        #expect(line.contains("Little Snitch at x=1478.0 is not in hidden section"))
        #expect(line.contains("hidden divider x=1686.5"))
        #expect(line.contains("always hidden x=1685.5"))
    }

    @Test("Without Always Hidden the line says none")
    func boundaryRepairWithoutAlwaysHidden() {
        let line = DiagnosticLines.boundaryRepair(
            item: "A", itemX: 1, section: "hidden section",
            hiddenDividerX: 2, alwaysHiddenDividerX: nil, revealed: "hidden section"
        )
        #expect(line.contains("always hidden x=none"))
    }

    @Test("Layout tiles list every tile and the ones without a picture")
    func layoutTiles() {
        let line = DiagnosticLines.layoutTiles(
            section: "visible section",
            tiles: [(name: "Clock", hasPicture: false), (name: "Siri", hasPicture: true), (name: "Home", hasPicture: false)]
        )
        #expect(line == "layout tiles (visible section): 3 [Clock, Siri, Home]; no picture: [Clock, Home]")
    }
}
