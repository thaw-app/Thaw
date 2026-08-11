//
//  AXActivationEscalationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers ``AXItemActivator/performFirstEffectiveAction(_:perform:didReact:)``,
/// the rule that decides when activating an item is allowed to try harder.
///
/// Every escalation is another activation of the same item, so escalating past
/// an action that already worked is how a menu gets opened and immediately shut:
/// `AXPress` toggles it, and the synthetic click the caller falls back to after
/// that toggles it again. The reading that makes this happen is a thrown
/// `AXShowMenu` — the action opens the menu and then blocks, because the menu
/// runs a modal tracking loop and the app cannot answer while it does, so the
/// messaging timeout expires on exactly the calls that succeeded (#924).
@Suite("AX activation escalation")
struct AXActivationEscalationTests {
    /// Records what was tried, so a test can assert on what was *not*.
    private final class Recorder {
        var attempted = [String]()
        var reacted = false

        func perform(_ action: String, accepting: Set<String>) -> Bool {
            attempted.append(action)
            return accepting.contains(action)
        }
    }

    private func run(
        _ actions: [String],
        accepting: Set<String> = [],
        reactsAfter: String? = nil,
        recorder: Recorder = Recorder()
    ) -> (worked: Bool, attempted: [String]) {
        let worked = AXItemActivator.performFirstEffectiveAction(
            actions,
            perform: { action in
                let accepted = recorder.perform(action, accepting: accepting)
                if action == reactsAfter {
                    recorder.reacted = true
                }
                return accepted
            },
            didReact: { recorder.reacted }
        )
        return (worked, recorder.attempted)
    }

    /// The ordinary case: the element takes the action and says so.
    @Test("An accepted action stops the sequence")
    func acceptedActionStops() {
        let result = run(["AXShowMenu", "AXPress"], accepting: ["AXShowMenu"])
        #expect(result.worked)
        #expect(result.attempted == ["AXShowMenu"])
    }

    /// The regression. The action threw, the menu opened anyway, and pressing
    /// again would close it.
    @Test("An action that threw but was seen working stops the sequence")
    func observedEffectStopsDespiteThrow() {
        let result = run(["AXShowMenu", "AXPress"], reactsAfter: "AXShowMenu")
        #expect(result.worked)
        #expect(result.attempted == ["AXShowMenu"], "AXPress would have toggled the open menu shut")
    }

    /// The reason the sequence exists at all: an element that genuinely refuses
    /// AXShowMenu and does nothing must still get its press.
    @Test("An action with no effect escalates to the next one")
    func inertActionEscalates() {
        let result = run(["AXShowMenu", "AXPress"], accepting: ["AXPress"])
        #expect(result.worked)
        #expect(result.attempted == ["AXShowMenu", "AXPress"])
    }

    /// A reaction from the last action counts too — nothing follows it here,
    /// but the caller reads the return value to decide whether to click, and a
    /// click would land on the open menu.
    @Test("A reaction to the last action still counts as working")
    func reactionToLastActionCounts() {
        let result = run(["AXShowMenu", "AXPress"], reactsAfter: "AXPress")
        #expect(result.worked)
        #expect(result.attempted == ["AXShowMenu", "AXPress"])
    }

    /// The one case where the caller may safely click: nothing was accepted and
    /// nothing was seen happening, so the item was left alone.
    @Test("Nothing accepted and nothing observed reports failure")
    func inertThroughoutFails() {
        let result = run(["AXShowMenu", "AXPress"])
        #expect(!result.worked)
        #expect(result.attempted == ["AXShowMenu", "AXPress"])
    }

    @Test("No actions reports failure without claiming anything happened")
    func noActionsFails() {
        let result = run([])
        #expect(!result.worked)
        #expect(result.attempted.isEmpty)
    }
}
