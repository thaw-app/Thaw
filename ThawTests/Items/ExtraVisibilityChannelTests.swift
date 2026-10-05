//
//  ExtraVisibilityChannelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// The file and signal that tell Thaw's extra helpers which of them to hide.
/// Every write here goes to a scratch folder and nothing is posted.
@MainActor
@Suite("Extra visibility channel", .serialized)
struct ExtraVisibilityChannelTests {
    private func withScratchFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtraVisibilityChannelTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    /// Bundle identifiers no earlier test hid, so the unchanged-set check starts clean.
    private func freshBundles(_ names: String...) -> Set<String> {
        let run = UUID().uuidString
        return Set(names.map { "\(ThawMenuBarIdentity.bundleIdentifier).extra.\($0).\(run)" })
    }

    private func hiddenExtras(in folder: URL) throws -> String {
        try String(contentsOf: ExtraVisibilityChannel.file(in: folder), encoding: .utf8)
    }

    @Test("Only Thaw's own extra bundles belong to the channel")
    func ownsOnlyExtraBundles() {
        let own = ThawMenuBarIdentity.bundleIdentifier
        #expect(ExtraVisibilityChannel.ownsBundle("\(own).extra.wifi"))
        #expect(!ExtraVisibilityChannel.ownsBundle(own))
        #expect(!ExtraVisibilityChannel.ownsBundle("\(own).extras"))
        #expect(!ExtraVisibilityChannel.ownsBundle("com.example.app.extra.wifi"))
    }

    @Test("The helper finds the list and the signal under the names it derives from its parent")
    func fileAndSignalNamesMatchTheHelper() {
        let own = ThawMenuBarIdentity.bundleIdentifier
        #expect(ExtraVisibilityChannel.file == ItemStandInSlot.folder.appending(path: "hidden-extras.txt"))
        #expect(ExtraVisibilityChannel.notification.rawValue == "\(own).extra.visibility")
    }

    @Test("Hiding writes the bundles one per line, sorted, then announces once")
    func hideWritesSortedListAndAnnounces() throws {
        try withScratchFolder { folder in
            let bundles = freshBundles("wifi", "battery", "clock")
            var announcements = 0

            ExtraVisibilityChannel.hide(bundles, folder: folder) { announcements += 1 }

            let written = try hiddenExtras(in: folder)
            #expect(written == bundles.sorted().joined(separator: "\n"))
            #expect(announcements == 1)
        }
    }

    @Test("Hiding the same set again neither rewrites the list nor announces")
    func unchangedSetIsNotRepublished() throws {
        try withScratchFolder { folder in
            let bundles = freshBundles("wifi")
            var announcements = 0
            ExtraVisibilityChannel.hide(bundles, folder: folder) { announcements += 1 }
            try FileManager.default.removeItem(at: ExtraVisibilityChannel.file(in: folder))

            ExtraVisibilityChannel.hide(bundles, folder: folder) { announcements += 1 }

            #expect(announcements == 1)
            #expect(!FileManager.default.fileExists(atPath: ExtraVisibilityChannel.file(in: folder).path))
        }
    }

    @Test("Showing everything again replaces the list with an empty one")
    func emptySetClearsTheList() throws {
        try withScratchFolder { folder in
            var announcements = 0
            ExtraVisibilityChannel.hide(freshBundles("wifi"), folder: folder) { announcements += 1 }

            ExtraVisibilityChannel.hide([], folder: folder) { announcements += 1 }

            let written = try hiddenExtras(in: folder)
            #expect(written.isEmpty)
            #expect(announcements == 2)
        }
    }

    @Test("A list that could not be written is not announced, and is retried next time")
    func failedWriteIsRetried() throws {
        try withScratchFolder { folder in
            let blocked = folder.appendingPathComponent("not-a-folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: blocked)
            let bundles = freshBundles("wifi")
            var announcements = 0

            ExtraVisibilityChannel.hide(bundles, folder: blocked) { announcements += 1 }
            #expect(announcements == 0)

            ExtraVisibilityChannel.hide(bundles, folder: folder) { announcements += 1 }
            #expect(announcements == 1, "A failed write must not be remembered as published")
            let written = try hiddenExtras(in: folder)
            #expect(written == bundles.sorted().joined(separator: "\n"))
        }
    }
}
