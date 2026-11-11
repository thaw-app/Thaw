//
//  CornersSliderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
struct CornersSliderTests {
    @Test("The Corners slider reads Square and Round at its ends and a percentage between")
    func valueText() {
        #expect(CornersSlider.valueText(0) == "Square")
        #expect(CornersSlider.valueText(1) == "Round")
        #expect(CornersSlider.valueText(0.4) == 0.4.formatted(.percent.precision(.fractionLength(0))))
    }
}
