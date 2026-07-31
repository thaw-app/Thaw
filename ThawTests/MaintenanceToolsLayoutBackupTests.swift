//
//  MaintenanceToolsLayoutBackupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Resetting layout positions discards the user's entire menu bar arrangement,
/// so the backup written beforehand is the only way back. These cover the
/// naming and location that make a backup findable and restorable.
@Suite("Maintenance layout backups")
struct MaintenanceToolsLayoutBackupTests {
    /// Parses `"yyyy-MM-dd HH:mm:ss"` in the current time zone, matching the
    /// zone ``MaintenanceTools/menuBarLayoutBackupName(for:)`` formats in.
    private static func date(_ localTime: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: localTime)!
    }

    @Test("Backup names are plists stamped to the second")
    func backupNameShape() {
        let name = MaintenanceTools.menuBarLayoutBackupName(
            for: Self.date("2026-07-30 15:41:05")
        )

        #expect(name == "MenuBarLayout_2026-07-30_15.41.05.plist")
    }

    @Test("Midnight uses a zero-based 24-hour clock, not 12 or 24")
    func backupNameUsesZeroBasedTwentyFourHourClock() {
        let name = MaintenanceTools.menuBarLayoutBackupName(
            for: Self.date("2026-01-02 00:05:09")
        )

        #expect(name == "MenuBarLayout_2026-01-02_00.05.09.plist")
    }

    @Test("Afternoon hours stay in 24-hour form")
    func backupNameUsesAfternoonHours() {
        let name = MaintenanceTools.menuBarLayoutBackupName(
            for: Self.date("2026-12-31 23:59:59")
        )

        #expect(name == "MenuBarLayout_2026-12-31_23.59.59.plist")
    }

    /// Finder sorts the backup folder by name, so lexical order must match
    /// chronological order for "restore the one from before I broke it" to work.
    @Test("Backup names sort lexically in chronological order")
    func backupNamesSortChronologically() {
        let names = [
            Self.date("2026-07-30 15:41:05"),
            Self.date("2026-01-02 00:05:09"),
            Self.date("2026-07-30 09:41:05"),
            Self.date("2026-12-31 23:59:59"),
        ].map(MaintenanceTools.menuBarLayoutBackupName(for:))

        #expect(names.sorted() == [names[1], names[2], names[0], names[3]])
    }

    @Test("Backups live in a dedicated folder under the app's support directory")
    func backupDirectoryIsNamespaced() {
        let directory = MaintenanceTools.menuBarLayoutBackupDirectory()

        #expect(directory.lastPathComponent == "MenuBarLayoutBackups")
        #expect(directory.deletingLastPathComponent().lastPathComponent == Constants.bundleIdentifier)
        #expect(directory.path(percentEncoded: false).contains("Application Support"))
    }
}
