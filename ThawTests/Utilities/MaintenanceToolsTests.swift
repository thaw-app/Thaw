//
//  MaintenanceToolsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the parts of ``MaintenanceTools`` that can be pointed somewhere
/// harmless: the cache clear, which takes its directory and file manager as
/// arguments, and the error a failed command reports.
///
/// The Control Center, menu bar layout and TCC resets are not exercised here.
/// They kill live processes and delete the running user's real preference
/// plists, so a unit test that ran them would wreck the machine it ran on.
@Suite("Maintenance tools")
struct MaintenanceToolsTests {
    // MARK: - Cache directory names

    @Test("The current and legacy cache directories are both cleared")
    func cacheDirectoryNamesIncludeTheLegacyName() {
        let names = MaintenanceTools.appCacheDirectoryNames(bundleIdentifier: "com.example.app")
        #expect(names == ["com.example.app", "com.stonerl.thaw"])
    }

    @Test("A bundle id equal to the legacy name is not listed twice")
    func cacheDirectoryNamesDeduplicate() {
        let names = MaintenanceTools.appCacheDirectoryNames(bundleIdentifier: "com.stonerl.thaw")
        #expect(names == ["com.stonerl.thaw"])
    }

    // MARK: - Cache clearing

    @Test("Clearing removes both cache directories and nothing else")
    func clearAppCacheRemovesBothDirectories() throws {
        let fileManager = FileManager.default
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let current = root.appending(path: "com.example.app", directoryHint: .isDirectory)
        let legacy = root.appending(path: "com.stonerl.thaw", directoryHint: .isDirectory)
        let unrelated = root.appending(path: "com.apple.Safari", directoryHint: .isDirectory)
        for directory in [current, legacy, unrelated] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("cached".utf8).write(to: directory.appending(path: "entry"))
        }

        try MaintenanceTools.clearAppCache(
            cachesDirectory: root,
            bundleIdentifier: "com.example.app",
            fileManager: fileManager
        )

        #expect(!fileManager.fileExists(atPath: current.path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: legacy.path(percentEncoded: false)))
        #expect(fileManager.fileExists(atPath: unrelated.path(percentEncoded: false)))
    }

    @Test("Clearing a cache that was never created succeeds")
    func clearAppCacheToleratesMissingDirectories() throws {
        let fileManager = FileManager.default
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // A first run on a machine that has never written a cache must not be
        // an error the Tools pane surfaces to the user.
        try MaintenanceTools.clearAppCache(
            cachesDirectory: root,
            bundleIdentifier: "com.example.app",
            fileManager: fileManager
        )
        #expect(fileManager.fileExists(atPath: root.path(percentEncoded: false)))
    }

    @Test("Clearing removes a populated cache tree, not just the top directory")
    func clearAppCacheRemovesNestedContent() throws {
        let fileManager = FileManager.default
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cache = root.appending(path: "com.example.app", directoryHint: .isDirectory)
        let nested = cache.appending(path: "images/icons", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: nested.appending(path: "icon.png"))
        defer { try? fileManager.removeItem(at: root) }

        try MaintenanceTools.clearAppCache(
            cachesDirectory: root,
            bundleIdentifier: "com.example.app",
            fileManager: fileManager
        )

        #expect(!fileManager.fileExists(atPath: cache.path(percentEncoded: false)))
    }

    // MARK: - Errors

    @Test("A failed command names the command and its exit status")
    func commandFailureDescribesItself() throws {
        let error = MaintenanceTools.ToolError.commandFailed("killall", 1, "No matching processes")
        let description = try #require(error.errorDescription)

        #expect(description.contains("killall"))
        #expect(description.contains("1"))
        #expect(description.contains("No matching processes"))
    }

    @Test("A failure with no output leaves the detail off rather than dangling")
    func commandFailureWithoutDetail() throws {
        let blank = MaintenanceTools.ToolError.commandFailed("tccutil", 64, "   \n  ")
        let description = try #require(blank.errorDescription)

        #expect(description.contains("tccutil"))
        #expect(description.contains("64"))
        // Whitespace-only output is treated as no output at all, so the
        // sentence ends after the status instead of trailing a colon.
        #expect(!description.contains(":"))
    }
}
