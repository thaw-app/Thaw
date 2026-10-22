//
//  MenuBarShapeRoundnessTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Testing
@testable import Thaw

@MainActor
struct MenuBarShapeRoundnessTests {
    @Test
    func `the slider at 0 squares every end, above 0 rounds them by its value`() {
        let square = MenuBarShapeRoundness.info(for: 0)
        #expect(square.leadingEndCap == .square && square.trailingEndCap == .square)
        let half = MenuBarShapeRoundness.info(for: 0.5)
        #expect(half.leadingEndCap == .round && half.trailingEndCap == .round)
        #expect(half.roundness == 0.5)
        #expect(MenuBarShapeRoundness.info(for: 3).roundness == 1)
        let below = MenuBarShapeRoundness.info(for: -0.5)
        #expect(below.leadingEndCap == .square && below.trailingEndCap == .square)
        #expect(below.roundness == 0)
    }

    @Test
    func `a shape reads as its roundness, or 0 with only square ends`() {
        #expect(MenuBarShapeRoundness.value(of: [MenuBarShapeRoundness.info(for: 0.4)]) == 0.4)
        let squareButOld = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square, roundness: 1)
        #expect(MenuBarShapeRoundness.value(of: [squareButOld, squareButOld]) == 0)
        #expect(MenuBarShapeRoundness.value(of: []) == 0)
        let oneRoundEnd = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round, roundness: 0.3)
        #expect(MenuBarShapeRoundness.value(of: [squareButOld, oneRoundEnd]) == 0.3, "Only parts with a round end count")
    }

    @Test
    func `a look saved before the slider keeps its fully round ends`() throws {
        let json = Data(#"{"leadingEndCap":1,"trailingEndCap":0}"#.utf8)
        let info = try JSONDecoder().decode(MenuBarFullShapeInfo.self, from: json)
        #expect(info.roundness == 1)
        let encoded = try JSONEncoder().encode(MenuBarShapeRoundness.info(for: 0.25))
        #expect(try JSONDecoder().decode(MenuBarFullShapeInfo.self, from: encoded).roundness == 0.25)
    }

    @Test
    func `a saved roundness out of range is read inside 0 to 1`() throws {
        func decoded(_ roundness: String) throws -> Double {
            let json = Data("{\"leadingEndCap\":1,\"trailingEndCap\":1,\"roundness\":\(roundness)}".utf8)
            return try JSONDecoder().decode(MenuBarFullShapeInfo.self, from: json).roundness
        }
        #expect(try decoded("-2") == 0)
        #expect(try decoded("4.5") == 1)
        #expect(try decoded("0.6") == 0.6)
    }

    @Test
    func `roundness 1 is a half-circle of the bar's height, and never more than the shape fits`() {
        let bar = CGRect(x: 0, y: 0, width: 200, height: 24)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: bar, roundness: 1) == 12)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: bar, roundness: 0.5) == 6)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: bar, roundness: 0) == 0)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: CGRect(x: 0, y: 0, width: 10, height: 24), roundness: 1) == 5)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: .zero, roundness: 1) == 0)
    }

    @Test
    func `a square end fills its corner, a round end leaves it open`() throws {
        let screen = try #require(NSScreen.screens.first)
        let bar = CGRect(x: 0, y: 0, width: 200, height: 24)
        let mixed = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round, roundness: 1)
        let path = MenuBarShapePathBuilder.shapePath(in: bar, caps: mixed, screen: screen)
        #expect(path.contains(CGPoint(x: 1.5, y: 2)))
        #expect(!path.contains(CGPoint(x: 198.5, y: 2)))
        #expect(path.contains(CGPoint(x: 100, y: 12)))
    }
}
