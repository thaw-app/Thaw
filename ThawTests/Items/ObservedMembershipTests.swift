//
//  ObservedMembershipTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Membership read from the position table")
struct ObservedMembershipTests {
    private static func item(_ title: String, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: pid_t(windowID),
            sourcePID: pid_t(windowID),
            bounds: CGRect(x: 0, y: 3, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static func candidate(
        _ title: String,
        weight: Int,
        authored: MenuBarSectionName?
    ) -> ObservedMembership.Candidate {
        .init(item: item(title, windowID: CGWindowID(abs(weight) + 1)), weight: weight, authored: authored)
    }

    /// The reporter's bar right after turning Always Hidden on: higher weights sit further left, and the
    /// Always Hidden divider landed between the Visible control (161) and the Hidden divider (328).
    private static let misplacedAlwaysHidden = 200

    /// Ten hidden items, two visible items past the misplaced divider, and two next to the Visible control.
    private static let reporterBar: [ObservedMembership.Candidate] =
        (0 ..< 10).map { candidate("hidden\($0)", weight: 400 + $0 * 80, authored: .hidden) } + [
            candidate("vpn", weight: 260, authored: .visible),
            candidate("home", weight: 230, authored: .visible),
            candidate("colorPicker", weight: 180, authored: .visible),
            candidate("clockNeighbour", weight: 170, authored: .visible),
        ]

    // MARK: Out-of-order dividers

    @Test("The reporter's dividers are refused")
    func reporterDividersAreRefused() {
        #expect(ObservedMembership.Dividers(
            hidden: 328, alwaysHidden: Self.misplacedAlwaysHidden, visibleControl: 161
        ) == nil)
    }

    @Test("Read against the misplaced divider, every item past it would land in Always Hidden")
    func misplacedDividerSweepsItemsIntoAlwaysHidden() {
        let swept = Self.reporterBar.filter {
            StoredWeights.observedSection(
                weight: $0.weight, hiddenDivider: 328,
                alwaysHiddenDivider: Self.misplacedAlwaysHidden, visibleControl: 161
            ) == .alwaysHidden
        }
        // This is the bug the order check prevents: 12 of 14 items, leaving only the two nearest the control.
        #expect(swept.count == 12)
    }

    @Test("The mirrored reporter bar is refused too")
    func mirroredReporterDividersAreRefused() {
        #expect(ObservedMembership.Dividers(
            hidden: -328, alwaysHidden: -Self.misplacedAlwaysHidden, visibleControl: -161
        ) == nil)
    }

    @Test(
        "Any Always Hidden divider short of the Hidden divider is refused",
        arguments: [100, 161, 162, 200, 327, 328]
    )
    func alwaysHiddenShortOfHiddenIsRefused(alwaysHidden: Int) {
        #expect(ObservedMembership.Dividers(hidden: 328, alwaysHidden: alwaysHidden, visibleControl: 161) == nil)
    }

    @Test("A Hidden divider on the Visible control is refused")
    func hiddenOnVisibleControlIsRefused() {
        #expect(ObservedMembership.Dividers(hidden: 161, alwaysHidden: nil, visibleControl: 161) == nil)
        #expect(ObservedMembership.Dividers(hidden: 161, alwaysHidden: 900, visibleControl: 161) == nil)
    }

    // MARK: Reading the dividers

    @Test("With Always Hidden off, a stray Always Hidden weight between Visible and Hidden is ignored")
    func strayAlwaysHiddenWeightIsIgnoredWhenOff() throws {
        let reading = ObservedMembership.readDividers(
            visibleControl: 161, hidden: 328, alwaysHidden: Self.misplacedAlwaysHidden, alwaysHiddenEnabled: false
        )
        let expected = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: nil, visibleControl: 161))
        #expect(reading == .ordered(expected))
    }

    @Test("With Always Hidden on, a misplaced Always Hidden weight reads as out of order")
    func misplacedAlwaysHiddenWeightIsOutOfOrderWhenOn() {
        #expect(ObservedMembership.readDividers(
            visibleControl: 161, hidden: 328, alwaysHidden: Self.misplacedAlwaysHidden, alwaysHiddenEnabled: true
        ) == .outOfOrder)
    }

    @Test("A missing Visible control or Hidden divider weight leaves the reading unavailable", arguments: [
        (Int?.none, Int?.some(328)),
        (Int?.some(161), Int?.none),
    ])
    func missingWeightIsUnavailable(visibleControl: Int?, hidden: Int?) {
        #expect(ObservedMembership.readDividers(
            visibleControl: visibleControl, hidden: hidden, alwaysHidden: 1368, alwaysHiddenEnabled: true
        ) == .unavailable)
    }

    @Test("A ⌘-drag read against misplaced dividers moves no item")
    func dragWithMisplacedDividersMovesNothing() {
        let reading = ObservedMembership.readDividers(
            visibleControl: 161, hidden: 328, alwaysHidden: Self.misplacedAlwaysHidden, alwaysHiddenEnabled: true
        )
        #expect(reading.moves(for: Self.reporterBar).isEmpty)
    }

    // MARK: Dividers in order

    @Test("With the dividers in order the reporter's bar needs no moves")
    func reporterBarInOrderNeedsNoMoves() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: 1368, visibleControl: 161))
        #expect(ObservedMembership.moves(for: Self.reporterBar, dividers: dividers).isEmpty)
    }

    @Test("Only items whose section differs move")
    func onlyChangedItemsMove() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: 1368, visibleControl: 161))
        let moves = ObservedMembership.moves(for: [
            Self.candidate("stays", weight: 200, authored: .visible),
            Self.candidate("draggedLeft", weight: 900, authored: .visible),
            Self.candidate("draggedFar", weight: 2000, authored: .hidden),
        ], dividers: dividers)
        let destinations = moves.reduce(into: [String: MenuBarSectionName]()) { result, move in
            for item in move.items {
                result[item.tag.title] = move.section
            }
        }
        #expect(destinations == ["draggedLeft": .hidden, "draggedFar": .alwaysHidden])
    }

    @Test("An item with no section yet takes the one it sits in")
    func unassignedItemTakesObservedSection() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: 1368, visibleControl: 161))
        let moves = ObservedMembership.moves(for: [Self.candidate("new", weight: 900, authored: nil)], dividers: dividers)
        #expect(moves.count == 1)
        #expect(moves.first?.section == .hidden)
    }

    /// The agent seats an icon it has never saved leftmost, past every weight on the bar.
    @Test("A new icon lands in Always Hidden when that section is saved, and in Hidden when it is off", arguments: [
        (true, MenuBarSectionName.alwaysHidden),
        (false, MenuBarSectionName.hidden),
    ])
    func newIconLandsLeftmost(alwaysHiddenEnabled: Bool, expected: MenuBarSectionName) throws {
        let bar = [
            Self.candidate("hiddenItem", weight: 900, authored: .hidden),
            Self.candidate("farItem", weight: 1500, authored: .alwaysHidden),
        ]
        let newIcon = try Self.candidate("new", weight: #require(bar.map(\.weight).max()) + 26, authored: nil)
        let reading = ObservedMembership.readDividers(
            visibleControl: 161, hidden: 328, alwaysHidden: 1368, alwaysHiddenEnabled: alwaysHiddenEnabled
        )
        let moves = reading.moves(for: bar + [newIcon])
        #expect(moves.map(\.section) == [expected])
        #expect(moves.first?.items.map(\.title) == (alwaysHiddenEnabled ? ["new"] : ["farItem", "new"]))
    }

    @Test("Items moving to one section keep their reading order")
    func groupedItemsKeepOrder() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: 1368, visibleControl: 161))
        let moves = ObservedMembership.moves(for: [
            Self.candidate("a", weight: 400, authored: .visible),
            Self.candidate("b", weight: 1000, authored: .visible),
            Self.candidate("c", weight: 700, authored: .alwaysHidden),
        ], dividers: dividers)
        #expect(moves.count == 1)
        #expect(moves.first?.items.map(\.title) == ["a", "b", "c"])
    }

    @Test("Without Always Hidden nothing moves into it")
    func withoutAlwaysHiddenNothingMovesThere() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: nil, visibleControl: 161))
        let moves = ObservedMembership.moves(for: [
            Self.candidate("far", weight: 5000, authored: .alwaysHidden),
        ], dividers: dividers)
        #expect(moves.map(\.section) == [.hidden])
    }

    @Test("A weight on a divider reads as the section nearer the Visible control")
    func weightOnDividerReadsNearerSection() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: 1368, visibleControl: 161))
        #expect(dividers.section(for: 328) == .visible)
        #expect(dividers.section(for: 1368) == .hidden)
        #expect(dividers.section(for: 161) == .visible)
    }

    @Test("An ascending axis reads the same sections")
    func ascendingAxis() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: -328, alwaysHidden: -1368, visibleControl: -161))
        #expect(dividers.section(for: -2000) == .alwaysHidden)
        #expect(dividers.section(for: -900) == .hidden)
        #expect(dividers.section(for: -200) == .visible)
        #expect(dividers.section(for: 50) == .visible)
    }

    @Test("No candidates, no moves")
    func emptyCandidates() throws {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: 1368, visibleControl: 161))
        #expect(ObservedMembership.moves(for: [], dividers: dividers).isEmpty)
    }

    // MARK: Candidates from the assignment table

    /// Weights read as in the reporter's table: Always Hidden 1368, Hidden 328, Visible control 161.
    private static func adoptionMoves(
        weights: [String: Int],
        assignment: [String: MenuBarSectionName],
        keepingAuthored: Bool
    ) throws -> [String: MenuBarSectionName] {
        let dividers = try #require(ObservedMembership.Dividers(hidden: 328, alwaysHidden: 1368, visibleControl: 161))
        let items = weights.keys.sorted().map { item($0, windowID: CGWindowID(abs(weights[$0] ?? 0) + 1)) }
        let candidates = ObservedMembership.candidates(
            among: items,
            weight: { weights[$0.title ?? ""] },
            assignment: assignment,
            isEligible: { _ in true }
        )
        return ObservedMembership.moves(for: candidates, dividers: dividers, keepingAuthored: keepingAuthored)
            .reduce(into: [:]) { result, move in
                for item in move.items {
                    result[item.title ?? ""] = move.section
                }
            }
    }

    @Test("Launch adoption places an item the user never assigned from its weight, and keeps assigned ones")
    func launchAdoptionPlacesUnassignedItems() throws {
        let assigned = Self.item("assigned", windowID: 2)
        let assignment = [MenuBarItemTag.canonicalPersistentIdentifier(assigned.uniqueIdentifier): MenuBarSectionName.visible]
        let moves = try Self.adoptionMoves(
            weights: ["legacy": 900, "assigned": 2000],
            assignment: assignment,
            keepingAuthored: true
        )
        #expect(moves == ["legacy": .hidden])
    }

    @Test("Candidates carry only explicit assignments, keyed by canonical identifier")
    func candidatesCarryExplicitAssignments() {
        let assigned = Self.item("assigned", windowID: 2)
        let assignment = [MenuBarItemTag.canonicalPersistentIdentifier(assigned.uniqueIdentifier): MenuBarSectionName.hidden]
        let candidates = ObservedMembership.candidates(
            among: [assigned, Self.item("unassigned", windowID: 3), Self.item("ineligible", windowID: 4), Self.item("unweighted", windowID: 5)],
            weight: { $0.title == "unweighted" ? nil : 500 },
            assignment: assignment,
            isEligible: { $0.title != "ineligible" }
        )
        #expect(candidates.map(\.item.title) == ["assigned", "unassigned"])
        #expect(candidates.map(\.authored) == [.hidden, nil])
    }

    @Test("An item the user never assigned that sits in Visible is not moved")
    func unassignedVisibleItemStays() throws {
        #expect(try Self.adoptionMoves(weights: ["plain": 200], assignment: [:], keepingAuthored: false).isEmpty)
        #expect(try Self.adoptionMoves(weights: ["plain": 200], assignment: [:], keepingAuthored: true).isEmpty)
    }
}
