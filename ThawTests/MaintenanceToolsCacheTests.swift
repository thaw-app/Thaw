//
//  MaintenanceToolsCacheTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Maintenance cache paths")
struct MaintenanceToolsCacheTests {
    @Test("Debug builds clear their own and the legacy cache directories")
    func debugCacheDirectoryNames() {
        #expect(
            MaintenanceTools.appCacheDirectoryNames(bundleIdentifier: "com.stonerl.Thaw.debug") == [
                "com.stonerl.Thaw.debug",
                "com.stonerl.thaw",
            ]
        )
    }

    @Test("Legacy bundle spelling is not duplicated")
    func legacyCacheDirectoryNameIsUnique() {
        #expect(
            MaintenanceTools.appCacheDirectoryNames(bundleIdentifier: "com.stonerl.thaw") == [
                "com.stonerl.thaw",
            ]
        )
    }

    @Test("Image cache uses the running bundle identifier")
    func imageCacheUsesRunningBundleIdentifier() {
        let cachesDirectory = URL(fileURLWithPath: "/tmp/cache-root", isDirectory: true)

        let url = MenuBarItemImageCache.cacheFileURL(
            cachesDirectory: cachesDirectory,
            bundleIdentifier: "com.stonerl.Thaw.debug"
        )

        #expect(url.path == "/tmp/cache-root/com.stonerl.Thaw.debug/imageCache.json")
    }

    @Test("Cache reset suspends future disk persistence")
    @MainActor
    func cacheResetSuspendsDiskPersistence() async {
        let cache = MenuBarItemImageCache()

        #expect(cache.isDiskPersistenceEnabled)

        await cache.suspendDiskPersistenceForReset()

        #expect(!cache.isDiskPersistenceEnabled)
    }

    @Test("Failed cache reset resumes disk persistence")
    @MainActor
    func failedCacheResetResumesDiskPersistence() async {
        let cache = MenuBarItemImageCache()
        await cache.suspendDiskPersistenceForReset()

        cache.resumeDiskPersistenceAfterFailedReset()

        #expect(cache.isDiskPersistenceEnabled)
    }

    @Test("Cache deletion removes current and legacy folders only")
    func cacheDeletionScope() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "ThawMaintenanceToolsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: root) }

        let current = root.appending(path: "com.stonerl.Thaw.debug", directoryHint: .isDirectory)
        let legacy = root.appending(path: "com.stonerl.thaw", directoryHint: .isDirectory)
        let unrelated = root.appending(path: "com.example.Unrelated", directoryHint: .isDirectory)
        for directory in [current, legacy, unrelated] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("sentinel".utf8).write(to: directory.appending(path: "cache.dat"))
        }

        try MaintenanceTools.clearAppCache(
            cachesDirectory: root,
            bundleIdentifier: "com.stonerl.Thaw.debug",
            fileManager: fileManager
        )

        #expect(!fileManager.fileExists(atPath: current.path))
        #expect(!fileManager.fileExists(atPath: legacy.path))
        #expect(fileManager.fileExists(atPath: unrelated.appending(path: "cache.dat").path))
    }

    @Test("Missing cache directories are idempotent")
    func missingCacheDirectoriesAreIdempotent() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "ThawMaintenanceToolsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        try MaintenanceTools.clearAppCache(
            cachesDirectory: root,
            bundleIdentifier: "com.stonerl.Thaw.debug",
            fileManager: fileManager
        )
        try MaintenanceTools.clearAppCache(
            cachesDirectory: root,
            bundleIdentifier: "com.stonerl.Thaw.debug",
            fileManager: fileManager
        )

        #expect(fileManager.fileExists(atPath: root.path))
    }
}
