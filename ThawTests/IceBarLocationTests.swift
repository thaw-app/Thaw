//
//  IceBarLocationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Ice bar location")
struct IceBarLocationTests {
    // MARK: - Raw Value Tests

    @Test("dynamic has raw value 0")
    func dynamicRawValue() {
        #expect(IceBarLocation.dynamic.rawValue == 0)
    }

    @Test("mousePointer has raw value 1")
    func mousePointerRawValue() {
        #expect(IceBarLocation.mousePointer.rawValue == 1)
    }

    @Test("iceIcon has raw value 2")
    func iceIconRawValue() {
        #expect(IceBarLocation.iceIcon.rawValue == 2)
    }

    @Test("leftAligned has raw value 3")
    func leftAlignedRawValue() {
        #expect(IceBarLocation.leftAligned.rawValue == 3)
    }

    @Test("rightAligned has raw value 4")
    func rightAlignedRawValue() {
        #expect(IceBarLocation.rightAligned.rawValue == 4)
    }

    // MARK: - Init from Raw Value Tests

    @Test("Raw value 0 initializes dynamic")
    func initFromRawValueZero() {
        #expect(IceBarLocation(rawValue: 0) == .dynamic)
    }

    @Test("Raw value 1 initializes mousePointer")
    func initFromRawValueOne() {
        #expect(IceBarLocation(rawValue: 1) == .mousePointer)
    }

    @Test("Raw value 2 initializes iceIcon")
    func initFromRawValueTwo() {
        #expect(IceBarLocation(rawValue: 2) == .iceIcon)
    }

    @Test("Raw value 3 initializes leftAligned")
    func initFromRawValueThree() {
        #expect(IceBarLocation(rawValue: 3) == .leftAligned)
    }

    @Test("Raw value 4 initializes rightAligned")
    func initFromRawValueFour() {
        #expect(IceBarLocation(rawValue: 4) == .rightAligned)
    }

    @Test("An out-of-range raw value initializes nothing")
    func initFromInvalidRawValue() {
        #expect(IceBarLocation(rawValue: -1) == nil)
        #expect(IceBarLocation(rawValue: 100) == nil)
    }

    // MARK: - Identifiable Tests

    @Test("Every location's identifier is its raw value")
    func idMatchesRawValue() {
        for location in IceBarLocation.allCases {
            #expect(location.id == location.rawValue)
        }
    }

    // MARK: - CaseIterable Tests

    @Test("There are five locations")
    func allCasesCount() {
        #expect(IceBarLocation.allCases.count == 5)
    }

    @Test("allCases lists every location")
    func allCasesContainsAllLocations() {
        #expect(IceBarLocation.allCases.contains(.dynamic))
        #expect(IceBarLocation.allCases.contains(.mousePointer))
        #expect(IceBarLocation.allCases.contains(.iceIcon))
        #expect(IceBarLocation.allCases.contains(.leftAligned))
        #expect(IceBarLocation.allCases.contains(.rightAligned))
    }

    // MARK: - Codable Tests

    @Test("Every location survives a round trip")
    func encodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for location in IceBarLocation.allCases {
            let data = try encoder.encode(location)
            let decoded = try decoder.decode(IceBarLocation.self, from: data)
            #expect(decoded == location)
        }
    }

    @Test("A bare JSON integer decodes to its location")
    func decodeFromRawValueJSON() throws {
        let decoder = JSONDecoder()

        // JSON integers should decode to locations
        let dynamicData = try #require("0".data(using: .utf8))
        let mousePointerData = try #require("1".data(using: .utf8))
        let iceIconData = try #require("2".data(using: .utf8))
        let leftAlignedData = try #require("3".data(using: .utf8))
        let rightAlignedData = try #require("4".data(using: .utf8))

        #expect(try decoder.decode(IceBarLocation.self, from: dynamicData) == .dynamic)
        #expect(try decoder.decode(IceBarLocation.self, from: mousePointerData) == .mousePointer)
        #expect(try decoder.decode(IceBarLocation.self, from: iceIconData) == .iceIcon)
        #expect(try decoder.decode(IceBarLocation.self, from: leftAlignedData) == .leftAligned)
        #expect(try decoder.decode(IceBarLocation.self, from: rightAlignedData) == .rightAligned)
    }

    // MARK: - fromString() Tests

    @Test("The name \"dynamic\" resolves to dynamic")
    func fromStringDynamic() {
        #expect(IceBarLocation.fromString("dynamic") == .dynamic)
    }

    @Test("The name \"mousePointer\" resolves to mousePointer")
    func fromStringMousePointer() {
        #expect(IceBarLocation.fromString("mousePointer") == .mousePointer)
    }

    @Test("The name \"iceIcon\" resolves to iceIcon")
    func fromStringIceIcon() {
        #expect(IceBarLocation.fromString("iceIcon") == .iceIcon)
    }

    @Test("The name \"leftAligned\" resolves to leftAligned")
    func fromStringLeftAligned() {
        #expect(IceBarLocation.fromString("leftAligned") == .leftAligned)
    }

    @Test("The name \"rightAligned\" resolves to rightAligned")
    func fromStringRightAligned() {
        #expect(IceBarLocation.fromString("rightAligned") == .rightAligned)
    }

    @Test("The string \"0\" resolves to dynamic")
    func fromStringNumericZero() {
        #expect(IceBarLocation.fromString("0") == .dynamic)
    }

    @Test("The string \"1\" resolves to mousePointer")
    func fromStringNumericOne() {
        #expect(IceBarLocation.fromString("1") == .mousePointer)
    }

    @Test("The string \"2\" resolves to iceIcon")
    func fromStringNumericTwo() {
        #expect(IceBarLocation.fromString("2") == .iceIcon)
    }

    @Test("The string \"3\" resolves to leftAligned")
    func fromStringNumericThree() {
        #expect(IceBarLocation.fromString("3") == .leftAligned)
    }

    @Test("The string \"4\" resolves to rightAligned")
    func fromStringNumericFour() {
        #expect(IceBarLocation.fromString("4") == .rightAligned)
    }

    @Test("Anything else resolves to nothing")
    func fromStringInvalid() {
        #expect(IceBarLocation.fromString("invalid") == nil)
        #expect(IceBarLocation.fromString("5") == nil)
        #expect(IceBarLocation.fromString("") == nil)
        #expect(IceBarLocation.fromString("Dynamic") == nil) // case sensitive
        #expect(IceBarLocation.fromString("mouse_pointer") == nil) // snake_case not supported
        #expect(IceBarLocation.fromString("ice_icon") == nil)
        #expect(IceBarLocation.fromString("left_aligned") == nil)
        #expect(IceBarLocation.fromString("right_aligned") == nil)
    }
}
