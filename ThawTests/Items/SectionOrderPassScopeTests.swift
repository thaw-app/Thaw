//
//  SectionOrderPassScopeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// What one section-order pass is for: the reveal it belongs to and the items it puts in order.
struct SectionOrderPassScopeTests {
    private static func wanted(
        cancelled: Bool = false,
        startedWhileRevealing: MenuBarSection.Name?,
        revealedNow: MenuBarSection.Name?
    ) -> Bool {
        SectionOrderPassScope.isStillWanted(
            isCancelled: cancelled,
            startedWhileRevealing: startedWhileRevealing,
            revealedNow: revealedNow
        )
    }

    @Test("A cancelled pass is no longer wanted, whatever the reveal")
    func cancelledIsNotWanted() {
        #expect(Self.wanted(cancelled: true, startedWhileRevealing: nil, revealedNow: nil) == false)
        #expect(Self.wanted(cancelled: true, startedWhileRevealing: .hidden, revealedNow: .hidden) == false)
    }

    @Test("A pass with no reveal is wanted until it is cancelled, whatever is revealed")
    func passWithoutRevealIsWanted() {
        #expect(Self.wanted(startedWhileRevealing: nil, revealedNow: nil) == true)
        #expect(Self.wanted(startedWhileRevealing: nil, revealedNow: .hidden) == true)
    }

    @Test("A pass started for a reveal is wanted only while that section is the one revealed")
    func passForRevealNeedsThatReveal() {
        #expect(Self.wanted(startedWhileRevealing: .hidden, revealedNow: .hidden) == true)
        #expect(Self.wanted(startedWhileRevealing: .hidden, revealedNow: nil) == false)
        #expect(Self.wanted(startedWhileRevealing: .hidden, revealedNow: .alwaysHidden) == false)
    }

    @Test("The desired order is the recorded order narrowed to the section's own items")
    func desiredOrderIsNarrowedToTheSection() {
        let sections: [String: MenuBarSection.Name] = ["a": .hidden, "b": .visible, "c": .hidden]
        let order = SectionOrderPassScope.desiredOrder(
            for: .hidden,
            recorded: ["c", "b", "a"],
            visibleOverride: nil,
            sectionOf: { sections[$0] }
        )
        #expect(order == ["c", "a"])
    }

    @Test("Only Visible takes the replacement order")
    func onlyVisibleTakesTheOverride() {
        let sections: [String: MenuBarSection.Name] = ["a": .hidden, "b": .visible, "c": .visible]
        let visible = SectionOrderPassScope.desiredOrder(
            for: .visible,
            recorded: ["b", "c"],
            visibleOverride: ["c", "b"],
            sectionOf: { sections[$0] }
        )
        #expect(visible == ["c", "b"])
        let hidden = SectionOrderPassScope.desiredOrder(
            for: .hidden,
            recorded: ["a"],
            visibleOverride: ["c", "b"],
            sectionOf: { sections[$0] }
        )
        #expect(hidden == ["a"])
    }

    @Test("The replacement order is narrowed to Visible too")
    func overrideIsNarrowed() {
        let sections: [String: MenuBarSection.Name] = ["b": .visible, "x": .hidden]
        let visible = SectionOrderPassScope.desiredOrder(
            for: .visible,
            recorded: nil,
            visibleOverride: ["x", "b"],
            sectionOf: { sections[$0] }
        )
        #expect(visible == ["b"])
    }

    @Test("A section with no recorded order has nothing to put in order")
    func missingRecordedOrderIsEmpty() {
        #expect(
            SectionOrderPassScope.desiredOrder(for: .hidden, recorded: nil, visibleOverride: nil, sectionOf: { _ in .hidden })
                .isEmpty
        )
    }

    @Test("An identifier the controller does not place is dropped")
    func unplacedIdentifierIsDropped() {
        let order = SectionOrderPassScope.desiredOrder(
            for: .hidden,
            recorded: ["a", "unknown"],
            visibleOverride: nil,
            sectionOf: { $0 == "a" ? .hidden : nil }
        )
        #expect(order == ["a"])
    }
}
