//
//  MoveLandingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Where a menu move left an item, read from a position table the test supplies.
/// Higher weights sit further left: Always Hidden 1368, Hidden 247, Visible control 113.
@MainActor
@Suite("Move landing")
struct MoveLandingTests {
    private static let thaw = ThawMenuBarIdentity.bundleIdentifier

    private static func item(_ bundle: String, _ title: String, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: windowID, ownerPID: 100, sourcePID: 200,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24), title: title, isOnScreen: true
        )
    }

    private let visibleControl = item(thaw, ControlItemIdentifier.visible.rawValue, windowID: 1)
    private let hiddenDivider = item(thaw, ControlItemIdentifier.hidden.rawValue, windowID: 2)
    private let alwaysHiddenDivider = item(thaw, ControlItemIdentifier.alwaysHidden.rawValue, windowID: 3)
    private let app = item("com.example.app", "Item-0", windowID: 10)
    private let other = item("com.example.other", "Item-0", windowID: 11)

    private var pair: ControlItemPair {
        ControlItemPair(hidden: hiddenDivider, alwaysHidden: alwaysHiddenDivider)
    }

    private static func key(_ item: MenuBarItem) -> String {
        guard case let .string(bundle) = item.tag.namespace else { return item.tag.title }
        return "status:\(bundle)::\(item.tag.title)"
    }

    private func table(app appWeight: Int?, other otherWeight: Int? = 500, available: Bool = true) -> StoredWeights.Table {
        var positions = [
            Self.key(visibleControl): 113,
            Self.key(hiddenDivider): 247,
            Self.key(alwaysHiddenDivider): 1368,
        ]
        positions[Self.key(app)] = appWeight
        positions[Self.key(other)] = otherWeight
        return StoredWeights.Table(isAvailable: available, positions: positions)
    }

    private func observed(app weight: Int?, available: Bool = true) -> MenuBarSectionName? {
        MoveLanding.observedSection(
            of: app,
            liveItems: [visibleControl, app, other],
            dividers: pair,
            table: table(app: weight, available: available)
        )
    }

    @Test("The stored weight decides, over the assignment, when it can be read")
    func weightDecides() {
        #expect(MoveLanding.landed(in: .hidden, assigned: .hidden, observed: .hidden))
        #expect(!MoveLanding.landed(in: .hidden, assigned: .hidden, observed: .visible))
        #expect(MoveLanding.landed(in: .visible, assigned: .hidden, observed: .visible))
    }

    @Test("Without a reading the assignment decides")
    func assignmentDecidesWithoutReading() {
        #expect(MoveLanding.landed(in: .hidden, assigned: .hidden, observed: nil))
        #expect(!MoveLanding.landed(in: .hidden, assigned: .visible, observed: nil))
    }

    @Test("An item's weight reads as the section it sits in", arguments: [
        (100, MenuBarSectionName.visible), (400, .hidden), (2000, .alwaysHidden),
    ])
    func weightReadsAsSection(weight: Int, section: MenuBarSectionName) {
        #expect(observed(app: weight) == section)
    }

    @Test("No reading without a weight, a readable table or dividers")
    func noReading() {
        #expect(observed(app: nil) == nil)
        #expect(observed(app: 400, available: false) == nil)
        #expect(MoveLanding.observedSection(
            of: app, liveItems: [visibleControl, app], dividers: nil, table: table(app: 400)
        ) == nil)
    }

    @Test("Dividers out of order give no reading")
    func outOfOrderDividers() {
        var positions = [
            Self.key(visibleControl): 113,
            Self.key(hiddenDivider): 247,
            Self.key(alwaysHiddenDivider): 200,
        ]
        positions[Self.key(app)] = 400
        #expect(MoveLanding.observedSection(
            of: app, liveItems: [visibleControl, app], dividers: pair,
            table: StoredWeights.Table(isAvailable: true, positions: positions)
        ) == nil)
    }

    @Test("A stored section order is recognised from the table, and an unsettled one is not")
    func settledSectionOrder() {
        let positions = { (appWeight: Int, otherWeight: Int) in
            table(app: appWeight, other: otherWeight)
        }
        let order = [app.uniqueIdentifier, other.uniqueIdentifier]
        let live = [visibleControl, app, other]
        #expect(SettledSectionOrder.isStored(
            section: .hidden, desiredOrder: order, liveItems: live, dividers: pair, table: positions(600, 500)
        ))
        #expect(!SettledSectionOrder.isStored(
            section: .hidden, desiredOrder: order, liveItems: live, dividers: pair, table: positions(500, 600)
        ))
        #expect(!SettledSectionOrder.isStored(
            section: .visible, desiredOrder: order, liveItems: live, dividers: pair, table: positions(100, 90)
        ))
        #expect(!SettledSectionOrder.isStored(
            section: .hidden, desiredOrder: order, liveItems: live, dividers: nil, table: positions(600, 500)
        ))
    }

    @Test("The divider weights describe themselves for the log")
    func dividerWeightsLogString() {
        let weights = StoredWeights(among: [visibleControl, hiddenDivider, alwaysHiddenDivider], table: table(app: nil))
        let found = ObservedMembership.DividerWeights(
            among: [visibleControl], dividers: pair, weight: weights.weight(of:)
        )
        #expect(found.logString == "visible 113, hidden 247, always hidden 1368")
        #expect(found.reading(alwaysHiddenEnabled: true) == .ordered(
            ObservedMembership.Dividers(hidden: 247, alwaysHidden: 1368, visibleControl: 113)!
        ))
        let missing = ObservedMembership.DividerWeights(among: [], dividers: nil, weight: weights.weight(of:))
        #expect(missing.logString == "visible 0, hidden 0, always hidden none")
        #expect(missing.reading(alwaysHiddenEnabled: false) == .unavailable)
    }
}
