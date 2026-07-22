//
//  KeyCodeTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox
@testable import Thaw
import XCTest

final class KeyCodeTests: XCTestCase {
    // MARK: - Raw Value Tests

    func testLetterKeyCodes() {
        XCTAssertEqual(KeyCode.a.rawValue, kVK_ANSI_A)
        XCTAssertEqual(KeyCode.b.rawValue, kVK_ANSI_B)
        XCTAssertEqual(KeyCode.c.rawValue, kVK_ANSI_C)
        XCTAssertEqual(KeyCode.z.rawValue, kVK_ANSI_Z)
    }

    func testNumberKeyCodes() {
        XCTAssertEqual(KeyCode.zero.rawValue, kVK_ANSI_0)
        XCTAssertEqual(KeyCode.one.rawValue, kVK_ANSI_1)
        XCTAssertEqual(KeyCode.nine.rawValue, kVK_ANSI_9)
    }

    func testSpecialKeyCodes() {
        XCTAssertEqual(KeyCode.space.rawValue, kVK_Space)
        XCTAssertEqual(KeyCode.tab.rawValue, kVK_Tab)
        XCTAssertEqual(KeyCode.returnKey.rawValue, kVK_Return)
        XCTAssertEqual(KeyCode.delete.rawValue, kVK_Delete)
    }

    // MARK: - RawRepresentable Tests

    func testRawRepresentableInit() {
        let keyCode = KeyCode(rawValue: kVK_ANSI_A)
        XCTAssertEqual(keyCode.rawValue, kVK_ANSI_A)
    }

    func testDifferentCodesNotEqual() {
        XCTAssertNotEqual(KeyCode.a, KeyCode.b)
        XCTAssertNotEqual(KeyCode.one, KeyCode.two)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = KeyCode.a

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(KeyCode.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testEncodeDecodeMultiple() throws {
        let keyCodes: [KeyCode] = [.a, .b, .space, .returnKey, .one]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for keyCode in keyCodes {
            let data = try encoder.encode(keyCode)
            let decoded = try decoder.decode(KeyCode.self, from: data)
            XCTAssertEqual(decoded, keyCode)
        }
    }

    // MARK: - Set Usage Tests

    func testUseInSet() {
        var keySet: Set<KeyCode> = []
        keySet.insert(.a)
        keySet.insert(.b)
        keySet.insert(.a) // Duplicate

        XCTAssertEqual(keySet.count, 2)
        XCTAssertTrue(keySet.contains(.a))
        XCTAssertTrue(keySet.contains(.b))
        XCTAssertFalse(keySet.contains(.c))
    }

    // MARK: - Dictionary Key Usage Tests

    func testUseAsDictionaryKey() {
        var dict: [KeyCode: String] = [:]
        dict[.a] = "Letter A"
        dict[.space] = "Space Bar"

        XCTAssertEqual(dict[.a], "Letter A")
        XCTAssertEqual(dict[.space], "Space Bar")
        XCTAssertNil(dict[.b])
    }
}
