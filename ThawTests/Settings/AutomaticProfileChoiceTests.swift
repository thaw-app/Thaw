//
//  AutomaticProfileChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Automatic profile choice")
struct AutomaticProfileChoiceTests {
    @Test("When a Focus ends on a Space with its own profile, that profile wins over the display's")
    func spaceWins() {
        let choice = AutomaticProfileChoice.choose(spaceKey: "space-1", spaceHasProfile: { $0 == "space-1" }, displayUUID: "DISPLAY")
        #expect(choice == .space(key: "space-1"))
    }

    @Test("A Space without a profile, or no Space key yet, falls back to the display")
    func displayFallback() {
        #expect(AutomaticProfileChoice.choose(spaceKey: "space-2", spaceHasProfile: { _ in false }, displayUUID: "DISPLAY") == .display(uuid: "DISPLAY"))
        #expect(AutomaticProfileChoice.choose(spaceKey: nil, spaceHasProfile: { _ in true }, displayUUID: "DISPLAY") == .display(uuid: "DISPLAY"))
    }

    @Test("Without a Space profile or a display, nothing switches")
    func nothing() {
        #expect(AutomaticProfileChoice.choose(spaceKey: nil, spaceHasProfile: { _ in true }, displayUUID: nil) == .none)
        #expect(AutomaticProfileChoice.choose(spaceKey: "space-3", spaceHasProfile: { _ in false }, displayUUID: nil) == .none)
    }
}
