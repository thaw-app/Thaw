//
//  MenuBarTwoPartShapeInfoTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

struct MenuBarTwoPartShapeInfoTests {
    private let leading = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square, roundness: 0.4)
    private let trailing = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)

    @Test("Split and notch shapes take their outer caps from the outer ends and the leading roundness")
    func outerEndCaps() {
        let expected = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square, roundness: 0.4)
        #expect(MenuBarSplitShapeInfo(leading: leading, trailing: trailing).outerEndCaps == expected)
        #expect(MenuBarNotchShapeInfo(leading: leading, trailing: trailing).outerEndCaps == expected)
    }

    @Test("A two-part shape is rounded when either part is")
    func roundedWhenEitherPartIs() {
        #expect(MenuBarSplitShapeInfo(leading: leading, trailing: trailing).hasRoundedShape)
        #expect(MenuBarNotchShapeInfo(leading: trailing, trailing: leading).hasRoundedShape)
        #expect(!MenuBarSplitShapeInfo(leading: trailing, trailing: trailing).hasRoundedShape)
    }

    @Test("A saved split or notch shape stores only its two parts")
    func storedKeys() throws {
        let split = try JSONEncoder().encode(MenuBarSplitShapeInfo(leading: leading, trailing: trailing))
        let notch = try JSONEncoder().encode(MenuBarNotchShapeInfo(leading: leading, trailing: trailing))
        for data in [split, notch] {
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(object.keys) == ["leading", "trailing"])
        }
        let decoded = try JSONDecoder().decode(MenuBarNotchShapeInfo.self, from: notch)
        #expect(decoded.leading == leading)
        #expect(decoded.trailing == trailing)
    }
}
