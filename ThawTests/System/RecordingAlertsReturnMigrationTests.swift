//
//  RecordingAlertsReturnMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Returning recording alerts migration")
struct RecordingAlertsReturnMigrationTests {
    @Test("A switch saved while the alerts were hidden is cleared once, and a later choice is kept")
    func clearsOnce() throws {
        let suiteName = ScratchDefaults.name("RecordingAlertsReturnMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        let key = Defaults.Key.enableRecordingWatch.rawValue
        defaults.set(true, forKey: key)

        MigrationManager().resetRecordingAlertsOnReturn(in: defaults)
        #expect(defaults.persistentDomain(forName: suiteName)?[key] == nil)

        defaults.set(true, forKey: key)
        MigrationManager().resetRecordingAlertsOnReturn(in: defaults)
        #expect(defaults.bool(forKey: key), "a choice made after the reset stays")
    }
}
