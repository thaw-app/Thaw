//
//  ControlCenterReplacementsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Layout shows the replacement settings as one switch with a list of
/// items under it. These pin how both read the settings and what they
/// write back.
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

    @Test("Each listed item reads as replaced only while it is")
    func listReadsEachItem() {
        let replacements = ControlCenterReplacements(modules: true, timeMachine: false, textInput: true, skipped: [.airDrop])
        #expect(replacements.isReplaced(.focus))
        #expect(!replacements.isReplaced(.airDrop))
        #expect(!replacements.isReplaced(.timeMachine))
        #expect(replacements.isReplaced(.textInput))
    }

    @Test("Leaving one module out keeps the others replaced")
    func leavingOneModuleOut() {
        var replacements = ControlCenterReplacements(modules: true, timeMachine: false, textInput: false)
        replacements.setReplaced(.nowPlaying, false)
        #expect(replacements.modules)
        #expect(replacements.skipped == [.nowPlaying])
        #expect(replacements.isOn)
    }

    @Test("Leaving every module out turns the modules off and forgets the list")
    func leavingAllModulesOut() {
        var replacements = ControlCenterReplacements(modules: true, timeMachine: true, textInput: false)
        for module in ControlCenterReplacements.moduleItems {
            replacements.setReplaced(module, false)
        }
        #expect(replacements == ControlCenterReplacements(modules: false, timeMachine: true, textInput: false))
    }

    @Test("Picking one module while none are replaced replaces only that one")
    func pickingOneModule() {
        var replacements = ControlCenterReplacements(modules: false, timeMachine: true, textInput: false)
        replacements.setReplaced(.focus, true)
        #expect(replacements.isReplaced(.focus))
        #expect(!replacements.isReplaced(.airDrop))
        #expect(!replacements.isReplaced(.nowPlaying))
        #expect(!replacements.isReplaced(.userSwitcher))
    }

    @Test("Turning the switch on again starts from every item")
    func turningOnClearsTheList() {
        var replacements = ControlCenterReplacements(modules: true, timeMachine: false, textInput: false, skipped: [.focus])
        replacements.isOn = true
        #expect(ControlCenterReplacements.listed.allSatisfy { replacements.isReplaced($0) })
    }

    @Test("The module choice round-trips through the settings", .scratchDefaults)
    func storesTheChoice() {
        let settings = AdvancedSettings()
        settings.controlCenterReplacements = ControlCenterReplacements(
            modules: true, timeMachine: false, textInput: false, skipped: [.userSwitcher]
        )
        #expect(settings.skippedModuleStandIns == ["user"])
        #expect(settings.controlCenterReplacements.skipped == [.userSwitcher])
        #expect(Defaults.store.stringArray(forKey: "SkippedModuleStandIns") == ["user"])
    }
}
