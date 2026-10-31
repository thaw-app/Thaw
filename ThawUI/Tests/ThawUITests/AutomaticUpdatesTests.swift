//
//  AutomaticUpdatesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawUI

/// The About and Privacy panes show the updater's two switches as one
/// three-way choice. These pin the mapping both panes share.
@MainActor
@Suite("Automatic updates choice")
struct AutomaticUpdatesTests {
    @Test("Not checking reads as off, whatever the download switch says", arguments: [false, true])
    func notCheckingIsOff(downloads: Bool) {
        #expect(AutomaticUpdates(checks: false, downloads: downloads) == .off)
    }

    @Test("Checking without downloading is check only")
    func checkingOnly() {
        #expect(AutomaticUpdates(checks: true, downloads: false) == .check)
    }

    @Test("Checking and downloading is download")
    func checkingAndDownloading() {
        #expect(AutomaticUpdates(checks: true, downloads: true) == .download)
    }

    @Test("Each choice sets both switches", arguments: [
        (AutomaticUpdates.off, false, false),
        (AutomaticUpdates.check, true, false),
        (AutomaticUpdates.download, true, true),
    ])
    func choiceSetsBothSwitches(mode: AutomaticUpdates, checks: Bool, downloads: Bool) {
        #expect(mode.checks == checks)
        #expect(mode.downloads == downloads)
    }

    @Test("Picking a choice writes both switches and reads back", arguments: AutomaticUpdates.allCases)
    func pickingWritesBothSwitches(mode: AutomaticUpdates) {
        let switches = FakeSwitches()
        switches.automaticUpdates = mode
        #expect(switches.automaticallyChecksForUpdates == mode.checks)
        #expect(switches.automaticallyDownloadsUpdates == mode.downloads)
        #expect(switches.automaticUpdates == mode)
    }

    @Test("The picker can tell the choices apart")
    func choicesAreDistinctRows() {
        #expect(Set(AutomaticUpdates.allCases.map(\.id)).count == AutomaticUpdates.allCases.count)
    }
}

@MainActor
private final class FakeSwitches: AutomaticUpdateSwitches {
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = true
}
