//
//  HiddenItemsPresentationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Hidden items appear in one of three places")
struct HiddenItemsPresentationTests {
    @Test("There are three choices, in the order the picker shows them")
    func threeChoices() {
        #expect(HiddenItemsPresentation.allCases == [.onClick, .thawBar, .alwaysShown])
    }

    @Test("Each pair of stored switches reads as one choice")
    func readsSwitches() {
        #expect(HiddenItemsPresentation(useThawBar: false, alwaysShowHiddenItems: false) == .onClick)
        #expect(HiddenItemsPresentation(useThawBar: true, alwaysShowHiddenItems: false) == .thawBar)
        #expect(HiddenItemsPresentation(useThawBar: false, alwaysShowHiddenItems: true) == .alwaysShown)
    }

    @Test("Both switches on reads as the Thaw Bar, which is what the user sees today")
    func bothSwitches() {
        #expect(HiddenItemsPresentation(useThawBar: true, alwaysShowHiddenItems: true) == .thawBar)
    }

    @Test("A written choice reads back as itself", arguments: HiddenItemsPresentation.allCases)
    func roundTrips(choice: HiddenItemsPresentation) {
        let switches = choice.switches
        #expect(HiddenItemsPresentation(useThawBar: switches.useThawBar, alwaysShowHiddenItems: switches.alwaysShowHiddenItems) == choice)
    }
}
