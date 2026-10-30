//
//  LeftmostMoveTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
import ThawLayout

@Suite("Leftmost new-item planning")
struct LeftmostMoveTests {
    private static func item(_ app: String, x: CGFloat, sourcePID: pid_t?) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(app), title: "Item-0", instanceIndex: 0),
            windowID: CGWindowID(x), ownerPID: 1, sourcePID: sourcePID,
            bounds: CGRect(x: x, y: 3, width: 24, height: 24), title: "Item-0", isOnScreen: true
        )
    }

    private static func plan(_ items: [MenuBarItem], lateOwners: Set<pid_t> = []) -> LayoutSolver.LeftmostMove {
        LayoutSolver.planLeftmostMove(
            items: items,
            observation: LayoutSolver.LeftmostObservation(hiddenBounds: CGRect(x: 500, y: 0, width: 0, height: 24)),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden,
            lateOwners: lateOwners
        )
    }

    @Test("An item whose owner isn't resolved yet doesn't hold up a new item that is")
    func unresolvedItemWaitsAlone() {
        let unresolved = Self.item("com.example.pending", x: 100, sourcePID: nil)
        let arrival = Self.item("dev.orca", x: 200, sourcePID: 42)
        guard case let .newHideableItem(item, _) = Self.plan([unresolved, arrival]) else {
            Issue.record("the resolved arrival should be placed")
            return
        }
        #expect(item.tag == arrival.tag)
    }

    @Test("A pass where no owner is resolved yet waits")
    func onlyUnresolvedWaits() {
        #expect(Self.plan([Self.item("com.example.pending", x: 100, sourcePID: nil)]) == .noop(reason: .unresolvedSourcePID))
    }

    @Test("A new item from an owner still answering Accessibility is held")
    func lateOwnerArrivalWaits() {
        let arrival = Self.item("com.microsoft.OneDrive-mac", x: 100, sourcePID: 77)
        #expect(Self.plan([arrival], lateOwners: [77]) == .noop(reason: .ownerStillAnswering))
    }

    @Test("A held owner doesn't hold up a new item from an owner that answered")
    func lateOwnerWaitsAlone() {
        let late = Self.item("com.microsoft.OneDrive-mac", x: 100, sourcePID: 77)
        let arrival = Self.item("dev.orca", x: 200, sourcePID: 42)
        guard case let .newHideableItem(item, _) = Self.plan([late, arrival], lateOwners: [77]) else {
            Issue.record("the arrival from the answering owner should be placed")
            return
        }
        #expect(item.tag == arrival.tag)
    }

    @Test("A late owner's item that is already known is not reported as held")
    func knownItemOfLateOwnerIsNotHeld() {
        let known = Self.item("com.microsoft.OneDrive-mac", x: 100, sourcePID: 77)
        let decision = LayoutSolver.planLeftmostMove(
            items: [known],
            observation: LayoutSolver.LeftmostObservation(hiddenBounds: CGRect(x: 500, y: 0, width: 0, height: 24)),
            savedSectionOrder: [:],
            knownItemIdentifiers: [known.uniqueIdentifier],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden,
            lateOwners: [77]
        )
        #expect(decision == .noop(reason: .noNewCandidate))
    }
}
