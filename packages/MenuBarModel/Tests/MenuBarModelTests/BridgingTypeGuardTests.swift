//
//  BridgingTypeGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// A CF value that is not an array must never reach the array bridge, which
/// aborts on it; the guards have to answer nil instead.
struct BridgingTypeGuardTests {
    @Test
    func arrayValueReadsAnArray() {
        let array = ["one", "two"] as CFArray
        let elements = Bridging.arrayValue(of: array)
        #expect(elements?.count == 2)
        #expect(elements as? [String] == ["one", "two"])
    }

    @Test
    func arrayValueRejectsOtherTypes() {
        #expect(Bridging.arrayValue(of: "text" as CFString) == nil)
        #expect(Bridging.arrayValue(of: 7 as CFNumber) == nil)
        #expect(Bridging.arrayValue(of: ["k": 1] as CFDictionary) == nil)
        #expect(Bridging.arrayValue(of: nil) == nil)
    }

    @Test
    func dictionaryValueReadsADictionary() {
        let dictionary = ["key": 42] as CFDictionary
        let entries: [String: Any]? = Bridging.dictionaryValue(of: dictionary)
        #expect(entries?["key"] as? Int == 42)
    }

    @Test
    func dictionaryValueRejectsOtherTypes() {
        let fromString: [String: Any]? = Bridging.dictionaryValue(of: "text" as CFString)
        let fromArray: [String: Any]? = Bridging.dictionaryValue(of: ["one"] as CFArray)
        let fromNil: [String: Any]? = Bridging.dictionaryValue(of: nil)
        #expect(fromString == nil)
        #expect(fromArray == nil)
        #expect(fromNil == nil)
    }
}
