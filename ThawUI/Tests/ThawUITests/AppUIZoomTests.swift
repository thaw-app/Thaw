//
//  AppUIZoomTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawUI

@Suite("App UI zoom")
struct AppUIZoomTests {
    @Test("Zoom steps through the fixed levels and stops at either end")
    func zoomSteps() {
        #expect(AppUIZoom.next(100, increasing: true) == 110)
        #expect(AppUIZoom.next(100, increasing: false) == 90)
        #expect(AppUIZoom.next(200, increasing: true) == 200)
        #expect(AppUIZoom.next(75, increasing: false) == 75)
        #expect(AppUIZoom.next(42, increasing: true) == 110, "an unknown level counts as 100")
        #expect(AppUIZoom.normalized(125) == 125)
        #expect(AppUIZoom.normalized(130) == 100)
    }
}
