//
//  MenuBarShapesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar shapes")
struct MenuBarShapesTests {
    // MARK: - MenuBarEndCap Tests

    @Suite("MenuBarEndCap")
    struct MenuBarEndCapTests {
        @Test("Each end cap keeps its raw value")
        func rawValues() {
            #expect(MenuBarEndCap.square.rawValue == 0)
            #expect(MenuBarEndCap.round.rawValue == 1)
        }

        @Test("Raw values initialize the matching end cap and nothing else")
        func initFromRawValue() {
            #expect(MenuBarEndCap(rawValue: 0) == .square)
            #expect(MenuBarEndCap(rawValue: 1) == .round)
            #expect(MenuBarEndCap(rawValue: 2) == nil)
        }

        @Test("There are two end caps")
        func allCasesCount() {
            #expect(MenuBarEndCap.allCases.count == 2)
        }

        @Test("Every end cap survives a round trip")
        func codable() throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            for endCap in MenuBarEndCap.allCases {
                let data = try encoder.encode(endCap)
                let decoded = try decoder.decode(MenuBarEndCap.self, from: data)
                #expect(decoded == endCap)
            }
        }
    }

    // MARK: - MenuBarShapeKind Tests

    @Suite("MenuBarShapeKind")
    struct MenuBarShapeKindTests {
        @Test("Each shape kind keeps its raw value")
        func rawValues() {
            #expect(MenuBarShapeKind.noShape.rawValue == 0)
            #expect(MenuBarShapeKind.full.rawValue == 1)
            #expect(MenuBarShapeKind.split.rawValue == 2)
            #expect(MenuBarShapeKind.notch.rawValue == 3)
        }

        @Test("Raw values initialize the matching shape kind and nothing else")
        func initFromRawValue() {
            #expect(MenuBarShapeKind(rawValue: 0) == .noShape)
            #expect(MenuBarShapeKind(rawValue: 1) == .full)
            #expect(MenuBarShapeKind(rawValue: 2) == .split)
            #expect(MenuBarShapeKind(rawValue: 3) == .notch)
            #expect(MenuBarShapeKind(rawValue: 4) == nil)
        }

        @Test("There are four shape kinds")
        func allCasesCount() {
            #expect(MenuBarShapeKind.allCases.count == 4)
        }

        @Test("Every shape kind's identifier is its raw value")
        func identifiableId() {
            for kind in MenuBarShapeKind.allCases {
                #expect(kind.id == kind.rawValue)
            }
        }

        @Test("Every shape kind survives a round trip")
        func codable() throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            for kind in MenuBarShapeKind.allCases {
                let data = try encoder.encode(kind)
                let decoded = try decoder.decode(MenuBarShapeKind.self, from: data)
                #expect(decoded == kind)
            }
        }
    }

    // MARK: - MenuBarFullShapeInfo Tests

    @Suite("MenuBarFullShapeInfo")
    struct MenuBarFullShapeInfoTests {
        @Test("The default value rounds both end caps")
        func defaultValue() {
            let defaultInfo = MenuBarFullShapeInfo.defaultValue
            #expect(defaultInfo.leadingEndCap == .round)
            #expect(defaultInfo.trailingEndCap == .round)
        }

        @Test("Two round end caps make a rounded shape")
        func hasRoundedShapeBothRound() {
            let info = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
            #expect(info.hasRoundedShape)
        }

        @Test("A round leading end cap alone makes a rounded shape")
        func hasRoundedShapeLeadingRound() {
            let info = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square)
            #expect(info.hasRoundedShape)
        }

        @Test("A round trailing end cap alone makes a rounded shape")
        func hasRoundedShapeTrailingRound() {
            let info = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
            #expect(info.hasRoundedShape)
        }

        @Test("Two square end caps make no rounded shape")
        func hasRoundedShapeBothSquare() {
            let info = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
            #expect(!info.hasRoundedShape)
        }

        @Test("Both end caps survive a round trip")
        func codable() throws {
            let original = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarFullShapeInfo.self, from: data)

            #expect(decoded.leadingEndCap == original.leadingEndCap)
            #expect(decoded.trailingEndCap == original.trailingEndCap)
        }

        @Test("Equality follows the end caps")
        func hashable() {
            let info1 = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
            let info2 = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
            let info3 = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)

            #expect(info1 == info2)
            #expect(info1 != info3)
        }
    }

    // MARK: - MenuBarSplitShapeInfo Tests

    @Suite("MenuBarSplitShapeInfo")
    struct MenuBarSplitShapeInfoTests {
        @Test("The default value uses the default full shape on both sides")
        func defaultValue() {
            let defaultInfo = MenuBarSplitShapeInfo.defaultValue
            #expect(defaultInfo.leading == MenuBarFullShapeInfo.defaultValue)
            #expect(defaultInfo.trailing == MenuBarFullShapeInfo.defaultValue)
        }

        @Test("A rounded leading side makes a rounded shape")
        func hasRoundedShapeLeadingRounded() {
            let info = MenuBarSplitShapeInfo(
                leading: MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square),
                trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
            )
            #expect(info.hasRoundedShape)
        }

        @Test("A rounded trailing side makes a rounded shape")
        func hasRoundedShapeTrailingRounded() {
            let info = MenuBarSplitShapeInfo(
                leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
                trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
            )
            #expect(info.hasRoundedShape)
        }

        @Test("Two square sides make no rounded shape")
        func hasRoundedShapeNoneRounded() {
            let info = MenuBarSplitShapeInfo(
                leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
                trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
            )
            #expect(!info.hasRoundedShape)
        }

        @Test("The default value survives a round trip")
        func codable() throws {
            let original = MenuBarSplitShapeInfo.defaultValue

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarSplitShapeInfo.self, from: data)

            #expect(decoded == original)
        }
    }

    // MARK: - MenuBarNotchShapeInfo Tests

    @Suite("MenuBarNotchShapeInfo")
    struct MenuBarNotchShapeInfoTests {
        @Test("The default value uses the default full shape on both sides")
        func defaultValue() {
            let defaultInfo = MenuBarNotchShapeInfo.defaultValue
            #expect(defaultInfo.leading == MenuBarFullShapeInfo.defaultValue)
            #expect(defaultInfo.trailing == MenuBarFullShapeInfo.defaultValue)
        }

        @Test("A rounded leading side makes a rounded shape")
        func hasRoundedShapeLeadingRounded() {
            let info = MenuBarNotchShapeInfo(
                leading: MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square),
                trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
            )
            #expect(info.hasRoundedShape)
        }

        @Test("A rounded trailing side makes a rounded shape")
        func hasRoundedShapeTrailingRounded() {
            let info = MenuBarNotchShapeInfo(
                leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
                trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
            )
            #expect(info.hasRoundedShape)
        }

        @Test("Two square sides make no rounded shape")
        func hasRoundedShapeNoneRounded() {
            let info = MenuBarNotchShapeInfo(
                leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
                trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
            )
            #expect(!info.hasRoundedShape)
        }

        @Test("The default value survives a round trip")
        func codable() throws {
            let original = MenuBarNotchShapeInfo.defaultValue

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarNotchShapeInfo.self, from: data)

            #expect(decoded == original)
        }

        @Test("Equality follows the two sides")
        func hashable() {
            let info1 = MenuBarNotchShapeInfo.defaultValue
            let info2 = MenuBarNotchShapeInfo.defaultValue
            let info3 = MenuBarNotchShapeInfo(
                leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
                trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
            )

            #expect(info1 == info2)
            #expect(info1 != info3)
        }

        @Test("The notch shape kind survives a round trip")
        func shapeKindCodableNotch() throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(MenuBarShapeKind.notch)
            let decoded = try decoder.decode(MenuBarShapeKind.self, from: data)
            #expect(decoded == .notch)
        }
    }
}
