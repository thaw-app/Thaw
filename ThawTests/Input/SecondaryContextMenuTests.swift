//
//  SecondaryContextMenuTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Secondary context menu ownership")
struct SecondaryContextMenuTests {
    @Test("Option claims the click from MenuBarAgent's own menu", arguments: [
        NSEvent.ModifierFlags.option,
        [.option, .control],
    ])
    func optionClaimsTheClick(flags: NSEvent.ModifierFlags) {
        #expect(SecondaryMenuOwnership.overridesMenuBarAgent(modifierFlags: flags))
        #expect(SecondaryMenuOwnership.ignoredMenuOwners(modifierFlags: flags, menuBarAgentPIDs: { [41, 42] }) == [41, 42])
    }

    @Test("Without Option, Apple's menu keeps the click", arguments: [
        NSEvent.ModifierFlags(),
        .control,
        .command,
        .shift,
    ])
    func withoutOptionAppleKeepsTheClick(flags: NSEvent.ModifierFlags) {
        #expect(!SecondaryMenuOwnership.overridesMenuBarAgent(modifierFlags: flags))
        #expect(SecondaryMenuOwnership.ignoredMenuOwners(modifierFlags: flags, menuBarAgentPIDs: { [41] }).isEmpty)
    }

    @Test("The live lookup returns only real process IDs")
    func liveLookupReturnsRealProcesses() {
        #expect(SecondaryMenuOwnership.liveMenuBarAgentPIDs().allSatisfy { $0 > 0 })
    }
}
