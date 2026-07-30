//
//  CustomTooltipPanelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class CustomTooltipPanelTests: XCTestCase {
    func testTooltipAppearsAboveIceBar() {
        let iceBar = IceBarPanel()
        let tooltip = CustomTooltipPanel.shared

        XCTAssertGreaterThan(
            tooltip.level.rawValue,
            iceBar.level.rawValue,
            "Tooltips must be above the Thaw Bar so grid items cannot obscure them"
        )
    }
}
