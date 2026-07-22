//
//  SectionDividerStyleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class SectionDividerStyleTests: XCTestCase {
    func testCasesAndRawValuesRemainStable() {
        let expected: [(SectionDividerStyle, Int)] = [(.noDivider, 0), (.chevron, 1)]

        XCTAssertEqual(SectionDividerStyle.allCases, expected.map(\.0))
        for (style, rawValue) in expected {
            XCTAssertEqual(style.rawValue, rawValue)
            XCTAssertEqual(SectionDividerStyle(rawValue: rawValue), style)
        }
        XCTAssertNil(SectionDividerStyle(rawValue: 2))
        XCTAssertNil(SectionDividerStyle(rawValue: -1))
    }
}
