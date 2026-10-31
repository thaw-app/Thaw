//
//  AutomaticUpdatesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw
import ThawUI

/// The words Thaw gives each automatic update choice. ThawUI's tests cover the choice itself.
@MainActor
@Suite("Automatic updates choice")
struct AutomaticUpdatesTests {
    @Test("Each choice has its own label in the picker")
    func choiceHasItsOwnLabel() {
        #expect(AutomaticUpdates.off.localized == "Off")
        #expect(AutomaticUpdates.check.localized == "Check only")
        #expect(AutomaticUpdates.download.localized == "Check and download")
    }

    @Test("The pill names are the short ones")
    func shortNames() {
        #expect(AutomaticUpdates.off.shortLocalized == "Off")
        #expect(AutomaticUpdates.check.shortLocalized == "Check")
        #expect(AutomaticUpdates.download.shortLocalized == "Download")
        #expect(AutomaticUpdates.check.shortLocalized != AutomaticUpdates.check.localized)
    }
}
