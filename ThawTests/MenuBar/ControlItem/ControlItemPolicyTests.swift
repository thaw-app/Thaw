//
//  ControlItemPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@Suite("What a click on a control item asks for")
struct ControlItemPolicyTests {
    private typealias Intent = ControlItem.PrimaryActionIntent

    private func appKitIntent(
        _ identifier: ControlItem.Identifier = .hidden,
        flags: NSEvent.ModifierFlags = [],
        clicks: Int = 1,
        doubleClick: Bool = false,
        optionClick: Bool = false
    ) -> Intent {
        ControlItem.primaryActionIntent(
            identifier: identifier,
            modifierFlags: flags,
            clickCount: clicks,
            usesDoubleClick: doubleClick,
            usesOptionClick: optionClick
        )
    }

    @Test("A plain click toggles the section")
    func plainClickToggles() {
        #expect(appKitIntent() == .toggleSection)
        #expect(appKitIntent(.visible, clicks: 2) == .toggleSection)
    }

    @Test("A double click on the visible control shows the always-hidden section, even with control held")
    func doubleClickWinsOverModifiers() {
        #expect(appKitIntent(.visible, flags: .control, clicks: 2, doubleClick: true) == .showAlwaysHidden)
        // Only the visible control has that shortcut.
        #expect(appKitIntent(.hidden, clicks: 2, doubleClick: true) == .toggleSection)
        #expect(appKitIntent(.visible, clicks: 1, doubleClick: true) == .toggleSection)
    }

    @Test("Control opens the menu before option is considered")
    func controlOpensTheMenu() {
        #expect(appKitIntent(flags: .control) == .contextMenu)
        #expect(appKitIntent(flags: [.control, .option], optionClick: true) == .contextMenu)
    }

    @Test("Option toggles always-hidden only when enabled, and is otherwise swallowed")
    func optionClick() {
        #expect(appKitIntent(flags: .option, optionClick: true) == .toggleAlwaysHidden)
        #expect(appKitIntent(flags: .option, optionClick: false) == Intent.none)
    }

    @Test("A forwarded activation ignores a stale control bit")
    func forwardedActivationIgnoresControl() {
        func intent(_ flags: NSEvent.ModifierFlags, _ identifier: ControlItem.Identifier = .hidden, clicks: Int = 1) -> Intent {
            ControlItem.menuBarAgentPrimaryActionIntent(
                identifier: identifier,
                modifierFlags: flags,
                clickCount: clicks,
                usesDoubleClick: true,
                usesOptionClick: true,
                diagLog: DiagLog(category: "ControlItemPolicyTests")
            )
        }
        #expect(intent(.control) == .toggleSection)
        #expect(intent(.option) == .toggleAlwaysHidden)
        #expect(intent([], .visible, clicks: 2) == .showAlwaysHidden)
        #expect(ControlItem.menuBarAgentPrimaryActionIntent(
            identifier: .hidden, modifierFlags: .option, clickCount: 1,
            usesDoubleClick: false, usesOptionClick: false
        ) == Intent.none)
    }

    @Test("Forwarded modifiers come from the press, then the event, then the keyboard")
    func modifierPrecedence() {
        #expect(ControlItem.resolvedPrimaryModifierFlags(
            pressModifiers: .option, eventModifiers: .control, liveModifiers: .shift
        ) == .option)
        #expect(ControlItem.resolvedPrimaryModifierFlags(
            pressModifiers: [], eventModifiers: .control, liveModifiers: .shift
        ) == .control)
        #expect(ControlItem.resolvedPrimaryModifierFlags(
            pressModifiers: nil, eventModifiers: [], liveModifiers: .shift
        ) == .shift)
    }

    @Test("Both shipped spellings of addTarget:action:forControlEvents: are recognised, and nothing else")
    func addTargetEncodings() {
        #expect(ControlItem.isSupportedAddTargetTypeEncoding("v@:@:Q"))
        #expect(ControlItem.isSupportedAddTargetTypeEncoding("v40@0:8@16:24Q32"))
        #expect(!ControlItem.isSupportedAddTargetTypeEncoding("v@:@:q"))
        #expect(!ControlItem.isSupportedAddTargetTypeEncoding("v40@0:8@16:24q32"))
        #expect(!ControlItem.isSupportedAddTargetTypeEncoding("@@:Q"))
    }

    @Test("The layout nudge pins an unlaid item to its width and adds half a point when already pinned")
    func layoutNudge() {
        #expect(ControlItem.menuBarAgentLayoutNudgeLength(currentLength: 30, renderedWidth: 0) == nil)
        #expect(ControlItem.menuBarAgentLayoutNudgeLength(currentLength: NSStatusItem.variableLength, renderedWidth: 24) == 24)
        #expect(ControlItem.menuBarAgentLayoutNudgeLength(currentLength: 30, renderedWidth: 24) == 24)
        #expect(ControlItem.menuBarAgentLayoutNudgeLength(currentLength: 24.2, renderedWidth: 24) == 24.5)
        #expect(ControlItem.menuBarAgentLayoutNudgeLength(currentLength: 24.3, renderedWidth: 24) == 24)
    }
}

@MainActor
@Suite("The republish budget remembers each control's last attempt")
struct ControlItemRepublishBudgetTests {
    @Test("A recorded attempt is counted and timed until restored")
    func recordAndRestore() {
        let identifier = ControlItem.Identifier.alwaysHidden
        ControlItemRepublishBudget.restore(for: identifier)
        defer { ControlItemRepublishBudget.restore(for: identifier) }
        let start = ContinuousClock.now

        #expect(ControlItemRepublishBudget.elapsedSinceLastAttempt(by: identifier, now: start) == nil)
        ControlItemRepublishBudget.record(attempt: 2, by: identifier, at: start)

        #expect(ControlItemRepublishBudget.attempts(by: identifier) == 2)
        #expect(ControlItemRepublishBudget.elapsedSinceLastAttempt(by: identifier, now: start + .seconds(3)) == .seconds(3))
        #expect(ControlItemRepublishBudget.restore(for: identifier))
        #expect(ControlItemRepublishBudget.elapsedSinceLastAttempt(by: identifier, now: start) == nil)
        #expect(!ControlItemRepublishBudget.restore(for: identifier))
    }
}
