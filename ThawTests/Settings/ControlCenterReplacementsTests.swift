//
//  ControlCenterReplacementsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Layout shows the three replacement settings as one switch. These pin
/// how that switch reads them and what it writes back.
@MainActor
@Suite("Control Center replacements switch")
struct ControlCenterReplacementsTests {
    @Test("Off only when nothing is replaced")
    func offWhenNothingIsReplaced() {
        #expect(!ControlCenterReplacements(modules: false, timeMachine: false, textInput: false).isOn)
    }

    @Test("On when any one replacement was already on", arguments: [
        ControlCenterReplacements(modules: true, timeMachine: false, textInput: false),
        ControlCenterReplacements(modules: false, timeMachine: true, textInput: false),
        ControlCenterReplacements(modules: false, timeMachine: false, textInput: true),
    ])
    func onWhenAnyIsReplaced(replacements: ControlCenterReplacements) {
        #expect(replacements.isOn)
    }

    @Test("Turning it on replaces all three")
    func turningOnSetsAll() {
        var replacements = ControlCenterReplacements(modules: false, timeMachine: true, textInput: false)
        replacements.isOn = true
        #expect(replacements == ControlCenterReplacements(modules: true, timeMachine: true, textInput: true))
    }

    @Test("Turning it off brings all three originals back")
    func turningOffClearsAll() {
        var replacements = ControlCenterReplacements(modules: true, timeMachine: false, textInput: true)
        replacements.isOn = false
        #expect(replacements == ControlCenterReplacements(modules: false, timeMachine: false, textInput: false))
    }
}
