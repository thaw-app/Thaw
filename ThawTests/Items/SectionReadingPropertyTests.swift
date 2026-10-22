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

    @Test("A launch read keeps every section set in Layout, and only places items that have none and sit outside Visible", arguments: 0 ..< 200)
    func launchReadKeepsLayoutSections(seed: Int) throws {
        let random = GKMersenneTwisterRandomSource(seed: UInt64(seed))
        let dividers = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        let sections: [MenuBarSectionName?] = [.visible, .hidden, .alwaysHidden, nil]
        let candidates = (0 ..< 12).map { index in
            ObservedMembership.Candidate(
                item: Self.item(index),
                weight: random.nextInt(upperBound: 2000),
                authored: sections[random.nextInt(upperBound: sections.count)]
            )
        }
        let moved = ObservedMembership.moves(for: candidates, dividers: dividers, keepingAuthored: true).flatMap(\.items)
        for item in moved {
            let candidate = try #require(candidates.first { $0.item.windowID == item.windowID })
            #expect(candidate.authored == nil, "seed \(seed): a section set in Layout was overwritten")
        }
        // An item without a section shows in Visible, so only one that reads elsewhere needs placing.
        let unplaced = candidates.filter { $0.authored == nil && dividers.section(for: $0.weight) != .visible }
        #expect(moved.count == unplaced.count, "seed \(seed): every item without a section that sits outside Visible gets one")
    }

    @Test("Without keeping Layout's sections, a read still moves placed items to where they sit")
    func readWithoutKeepingMoves() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        let candidate = ObservedMembership.Candidate(item: Self.item(0), weight: 500, authored: .visible)
        #expect(ObservedMembership.moves(for: [candidate], dividers: dividers).flatMap(\.items).count == 1)
        #expect(ObservedMembership.moves(for: [candidate], dividers: dividers, keepingAuthored: true).isEmpty)
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

    // MARK: After a ⌘-drag

    private static let sectionsWithNone: [MenuBarSectionName?] = [.visible, .hidden, .alwaysHidden, nil]

    @Test("After a ⌘-drag only the dragged item can move, and only when it crossed a divider", arguments: 0 ..< 300)
    func dragMovesOnlyTheDraggedItem(seed: Int) throws {
        let random = GKMersenneTwisterRandomSource(seed: UInt64(seed))
        let dividers = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        // Layout's sections are random, so most items read stale against their weights.
        let before = (0 ..< 12).map { index in
            ObservedMembership.Candidate(
                item: Self.item(index),
                weight: 101 + random.nextInt(upperBound: 1900),
                authored: Self.sectionsWithNone[random.nextInt(upperBound: Self.sectionsWithNone.count)]
            )
        }
        let baseline = ObservedMembership.DragBaseline(candidates: before, dividers: dividers)
        let dragged = random.nextInt(upperBound: before.count)
        let after = before.enumerated().map { index, candidate in
            guard index == dragged else { return candidate }
            return ObservedMembership.Candidate(
                item: candidate.item, weight: 101 + random.nextInt(upperBound: 1900), authored: candidate.authored
            )
        }
        let moved = ObservedMembership.moves(for: after, dividers: dividers, since: baseline).flatMap(\.items)
        #expect(moved.allSatisfy { $0.windowID == before[dragged].item.windowID }, "seed \(seed): an untouched item moved")
        let crossed = dividers.section(for: before[dragged].weight) != dividers.section(for: after[dragged].weight)
        // An item without a section shows in Visible.
        let differsFromLayout = dividers.section(for: after[dragged].weight) != (after[dragged].authored ?? .visible)
        #expect(moved.count == (crossed && differsFromLayout ? 1 : 0), "seed \(seed)")
    }

    @Test("Rows the agent saves again on their own side of every divider never move", arguments: 0 ..< 200)
    func resavedRowsStay(seed: Int) throws {
        let random = GKMersenneTwisterRandomSource(seed: UInt64(seed))
        let dividers = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        let bands = [101 ... 300, 301 ... 1000, 1001 ... 2000]
        let before = (0 ..< 10).map { index in
            let band = bands[random.nextInt(upperBound: bands.count)]
            return ObservedMembership.Candidate(
                item: Self.item(index),
                weight: band.lowerBound + random.nextInt(upperBound: band.count),
                authored: .visible
            )
        }
        let baseline = ObservedMembership.DragBaseline(candidates: before, dividers: dividers)
        let after = before.map { candidate in
            let band = bands.first { $0.contains(candidate.weight) }
            let weight = band.map { $0.lowerBound + random.nextInt(upperBound: $0.count) } ?? candidate.weight
            return ObservedMembership.Candidate(item: candidate.item, weight: weight, authored: candidate.authored)
        }
        #expect(ObservedMembership.moves(for: after, dividers: dividers, since: baseline).isEmpty, "seed \(seed)")
    }

    @Test("A concealed item with an old weight stays when the dividers' weights move past it")
    func staleWeightStaysWhenDividersMove() throws {
        let before = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        let after = try #require(ObservedMembership.Dividers(hidden: 600, alwaysHidden: 1400, visibleControl: 100))
        let concealed = ObservedMembership.Candidate(item: Self.item(0), weight: 450, authored: .hidden)
        let carried = ObservedMembership.Candidate(item: Self.item(1), weight: 350, authored: .hidden)
        let baseline = ObservedMembership.DragBaseline(candidates: [concealed, carried], dividers: before)
        // The dragged Hidden divider passed the item on the bar, which the agent saved at a new weight.
        let carriedAfter = ObservedMembership.Candidate(item: carried.item, weight: 520, authored: .hidden)
        let moves = ObservedMembership.moves(for: [concealed, carriedAfter], dividers: after, since: baseline)
        #expect(moves.map(\.section) == [.visible])
        #expect(moves.first?.items.map(\.windowID) == [carried.item.windowID])
    }

    @Test("An item the drag's start did not see never moves")
    func unseenItemStays() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        let baseline = ObservedMembership.DragBaseline(candidates: [], dividers: dividers)
        let arrived = ObservedMembership.Candidate(item: Self.item(0), weight: 1500, authored: .visible)
        #expect(ObservedMembership.moves(for: [arrived], dividers: dividers, since: baseline).isEmpty)
        #expect(ObservedMembership.DividerReading.ordered(dividers).moves(for: [arrived], since: baseline).isEmpty)
    }

    @Test("Switching to Manual keeps every section set in Layout, however stale the weights", arguments: 0 ..< 100)
    func switchToManualKeepsLayout(seed: Int) throws {
        let random = GKMersenneTwisterRandomSource(seed: UInt64(seed))
        let dividers = try #require(ObservedMembership.Dividers(hidden: 300, alwaysHidden: 1000, visibleControl: 100))
        let placed: [MenuBarSectionName] = [.visible, .hidden, .alwaysHidden]
        let candidates = (0 ..< 12).map { index in
            ObservedMembership.Candidate(
                item: Self.item(index),
                weight: 101 + random.nextInt(upperBound: 1900),
                authored: placed[random.nextInt(upperBound: placed.count)]
            )
        }
        #expect(ObservedMembership.moves(for: candidates, dividers: dividers, keepingAuthored: true).isEmpty, "seed \(seed)")
    }
}
