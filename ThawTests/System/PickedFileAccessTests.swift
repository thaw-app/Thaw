//
//  PickedFileAccessTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The access checks that need no open panel: what counts as readable, and
/// that recovery's read/write grant is its own bookmark, not an inherited one.
@MainActor
@Suite("Picked file access")
struct PickedFileAccessTests {
    private let bookmarkKey = "PickedFileAccessTests.bookmark"

    /// Runs body with a property list in a scratch folder and an empty scratch defaults suite.
    private func withFixture(_ body: (URL, UserDefaults) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickedFileAccessTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suiteName = "PickedFileAccessTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: folder)
        }
        let file = folder.appendingPathComponent("list.plist")
        try #require(NSDictionary(dictionary: ["apps": ["com.example.app"]]).write(to: file, atomically: true))
        try body(file, defaults)
    }

    /// The same bookmark the app stores after the panel: security-scoped where the system allows it.
    private func bookmark(for file: URL) throws -> Data {
        if let scoped = try? file.bookmarkData(options: [.withSecurityScope]) {
            return scoped
        }
        return try file.bookmarkData()
    }

    private func access(to file: URL, defaults: UserDefaults) -> PickedFileAccess {
        PickedFileAccess(fileURL: file, bookmarkKey: bookmarkKey, title: "Title", message: "Message", defaults: defaults)
    }

    @Test("A readable property list is accessible; a missing or malformed one is not")
    func readAccessNeedsAReadablePropertyList() throws {
        try withFixture { file, defaults in
            #expect(access(to: file, defaults: defaults).hasAccess)

            let missing = file.deletingLastPathComponent().appendingPathComponent("missing.plist")
            #expect(!access(to: missing, defaults: defaults).hasAccess)

            let garbage = file.deletingLastPathComponent().appendingPathComponent("garbage.plist")
            try Data("not a property list".utf8).write(to: garbage)
            #expect(!access(to: garbage, defaults: defaults).hasAccess)
        }
    }

    @Test("Read/write access needs this access's own bookmark, not just a readable file")
    func readWriteAccessNeedsItsOwnGrant() throws {
        try withFixture { file, defaults in
            let ungranted = access(to: file, defaults: defaults)
            #expect(ungranted.hasAccess)
            #expect(!ungranted.hasReadWriteAccess, "A file readable without a grant was not granted for writing")

            defaults.set(try bookmark(for: file), forKey: bookmarkKey)
            #expect(access(to: file, defaults: defaults).hasReadWriteAccess)
        }
    }

    @Test("A bookmark for a file that cannot be written is not read/write access")
    func readOnlyFileIsNotReadWriteAccess() throws {
        try withFixture { file, defaults in
            defaults.set(try bookmark(for: file), forKey: bookmarkKey)
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

            let readOnly = access(to: file, defaults: defaults)
            #expect(readOnly.hasAccess)
            #expect(!readOnly.hasReadWriteAccess)
        }
    }

    @Test("A stored bookmark that no longer resolves is forgotten")
    func unresolvableBookmarkIsRemoved() throws {
        try withFixture { file, defaults in
            defaults.set(Data("not a bookmark".utf8), forKey: bookmarkKey)
            let stale = access(to: file, defaults: defaults)

            stale.activateIfNeeded()

            #expect(defaults.data(forKey: bookmarkKey) == nil)
            #expect(!stale.hasReadWriteAccess)
        }
    }

    @Test("The bookmark is kept in the store the access was given, under its own key")
    func bookmarkStoreIsInjected() throws {
        try withFixture { file, defaults in
            let other = "PickedFileAccessTests.other"
            defaults.set(try bookmark(for: file), forKey: other)
            #expect(!access(to: file, defaults: defaults).hasReadWriteAccess)
            #expect(PickedFileAccess(
                fileURL: file, bookmarkKey: other, title: "Title", message: "Message", defaults: defaults
            ).hasReadWriteAccess)
            #expect(UserDefaults.standard.data(forKey: other) == nil)
        }
    }
}
