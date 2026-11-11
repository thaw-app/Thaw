//
//  ReorderDropOutcomeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// A failed single-item drop was only logged, so the item drifted back with no explanation.
@MainActor
@Suite("Reorder drop outcome", .serialized, .scratchDefaults)
struct ReorderDropOutcomeTests {
    private func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: CGWindowID(x), ownerPID: 42, sourcePID: 42,
            bounds: CGRect(x: x, y: 0, width: 20, height: 22), title: title, isOnScreen: true
        )
    }

    @Test("An item beside its target on the drop's side landed; anywhere else it didn't")
    func landedFollowsTheDropSide() {
        let first = item("A", x: 100), second = item("B", x: 130), third = item("C", x: 160)
        #expect(ReorderDropOutcome.landed(second, at: .rightOfItem(first), in: [third, second, first]) == true)
        #expect(ReorderDropOutcome.landed(second, at: .leftOfItem(third), in: [first, second, third]) == true)
        #expect(ReorderDropOutcome.landed(first, at: .rightOfItem(third), in: [first, second, third]) == false)
    }

    @Test("A read that misses the item or its target can't tell, so it raises nothing")
    func unknownWhenMissing() {
        let first = item("A", x: 100), second = item("B", x: 130)
        #expect(ReorderDropOutcome.landed(second, at: .rightOfItem(first), in: [first]) == nil)
        #expect(ReorderDropOutcome.landed(second, at: .rightOfItem(first), in: [second]) == nil)
    }

    @Test("The notice names the item and says macOS put it back")
    func messageNamesTheItem() {
        let refusal = ReorderDropOutcome.missedDrop(itemName: "Clock")
        #expect(refusal.title.contains("Clock"))
        #expect(refusal.message == "macOS put it back.")
    }

    @Test("A failed move posts the notice only when a fresh read shows the item elsewhere")
    func reportsOnlyAMiss() async {
        let appState = AppState()
        let first = item("A", x: 100), second = item("B", x: 130), third = item("C", x: 160)
        let log = DiagLog(category: "ReorderDropOutcomeTests")

        await ReorderDropOutcome.reportFailure(of: second, to: .rightOfItem(first), appState: appState, log: log) { _ in
            [first, second, third]
        }
        #expect(appState.layoutFeedback.refusal == nil, "it landed after all")

        await ReorderDropOutcome.reportFailure(of: second, to: .rightOfItem(first), appState: appState, log: log) { _ in nil }
        #expect(appState.layoutFeedback.refusal == nil, "no read, no claim")

        await ReorderDropOutcome.reportFailure(of: first, to: .rightOfItem(third), appState: appState, log: log) { _ in
            [first, second, third]
        }
        #expect(appState.layoutFeedback.refusal?.message == "macOS put it back.")
        appState.layoutFeedback.clear()
    }
}
