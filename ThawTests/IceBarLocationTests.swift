//
//  IceBarLocationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class IceBarLocationTests: XCTestCase {
    func testCasesAndRawValuesRemainStable() {
        let expected: [(IceBarLocation, Int)] = [
            (.dynamic, 0),
            (.mousePointer, 1),
            (.iceIcon, 2),
            (.leftAligned, 3),
            (.rightAligned, 4),
        ]

        XCTAssertEqual(IceBarLocation.allCases, expected.map(\.0))
        for (location, rawValue) in expected {
            XCTAssertEqual(location.rawValue, rawValue)
            XCTAssertEqual(IceBarLocation(rawValue: rawValue), location)
        }
        XCTAssertNil(IceBarLocation(rawValue: -1))
        XCTAssertNil(IceBarLocation(rawValue: 100))
    }

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for location in IceBarLocation.allCases {
            let data = try encoder.encode(location)
            let decoded = try decoder.decode(IceBarLocation.self, from: data)
            XCTAssertEqual(decoded, location)
        }
    }

    func testStringParsing() {
        let valid: [(String, IceBarLocation)] = [
            ("dynamic", .dynamic), ("0", .dynamic),
            ("mousePointer", .mousePointer), ("1", .mousePointer),
            ("iceIcon", .iceIcon), ("2", .iceIcon),
            ("leftAligned", .leftAligned), ("3", .leftAligned),
            ("rightAligned", .rightAligned), ("4", .rightAligned),
        ]
        for (value, expected) in valid {
            XCTAssertEqual(IceBarLocation.fromString(value), expected)
        }
        for invalid in ["invalid", "5", "", "Dynamic", "mouse_pointer", "ice_icon", "left_aligned", "right_aligned"] {
            XCTAssertNil(IceBarLocation.fromString(invalid))
        }
    }
}
