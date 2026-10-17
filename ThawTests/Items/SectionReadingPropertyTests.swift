//
//  SectionReadingPropertyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import GameplayKit
import MenuBarModel
import Testing
@testable import Thaw

/// Section reading over generated dividers and weights, on both axes. Each seed is one bar.
@Suite("Section reading properties")
struct SectionReadingPropertyTests {
    private static func item(_ index: Int) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.property.app\(index)"), title: "Item-0", instanceIndex: 0),
            windowID: CGWindowID(index + 1), ownerPID: 1, sourcePID: 1,
            bounds: CGRect(x: CGFloat(index) * 30, y: 3, width: 24, height: 24), title: "Item-0", isOnScreen: true
        )
    }

    @Test("Misplaced dividers never move anything", arguments: 0 ..< 300)
    func misplacedDividersMoveNothing(seed: Int) {
        let random = GKMersenneTwisterRandomSource(seed: UInt64(seed))
        let sign = random.nextBool() ? 1 : -1
        let visible = sign * 100
        let hidden = sign * (200 + random.nextInt(upperBound: 300))
        // Anywhere short of the Hidden divider, the Visible control's side included.
        let alwaysHidden = sign * (random.nextInt(upperBound: abs(hidden) + 1))
        let reading = ObservedMembership.readDividers(
            visibleControl: visible, hidden: hidden, alwaysHidden: alwaysHidden, alwaysHiddenEnabled: true
        )
        let candidates = (0 ..< 8).map { index in
            ObservedMembership.Candidate(item: Self.item(index), weight: sign * random.nextInt(upperBound: 3000), authored: .visible)
        }
        #expect(reading == .outOfOrder, "seed \(seed)")
        #expect(reading.moves(for: candidates).isEmpty, "seed \(seed)")
    }

    @Test("Ordered dividers read every item into the section its weight falls in", arguments: 0 ..< 300)
    func orderedDividersReadEachSide(seed: Int) throws {
        let random = GKMersenneTwisterRandomSource(seed: UInt64(seed))
        let sign = random.nextBool() ? 1 : -1
        let dividers = try #require(ObservedMembership.Dividers(
            hidden: sign * 300, alwaysHidden: sign * 1000, visibleControl: sign * 100
        ))
        let candidates = (0 ..< 10).map { index in
            ObservedMembership.Candidate(
                item: Self.item(index), weight: sign * random.nextInt(upperBound: 2000), authored: nil
            )
        }
        for (section, items) in ObservedMembership.moves(for: candidates, dividers: dividers) {
            for item in items {
                let weight = abs(try #require(candidates.first { $0.item.windowID == item.windowID }).weight)
                switch section {
                case .alwaysHidden: #expect(weight > 1000, "seed \(seed)")
                case .hidden: #expect(weight > 300 && weight <= 1000, "seed \(seed)")
                default: #expect(weight <= 300, "seed \(seed)")
                }
            }
        }
    }

    @Test("An item already in the section it reads as never moves", arguments: 0 ..< 200)
    func settledItemsStay(seed: Int) throws {
        let random = GKMersenneTwisterRandomSource(seed: UInt64(seed))
        let dividers = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        let candidates = (0 ..< 10).map { index in
            let weight = random.nextInt(upperBound: 2000)
            return ObservedMembership.Candidate(item: Self.item(index), weight: weight, authored: dividers.section(for: weight))
        }
        #expect(ObservedMembership.moves(for: candidates, dividers: dividers).isEmpty, "seed \(seed)")
    }
}
