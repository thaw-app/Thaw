//
//  WallpaperChangeMonitorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Exercises the file-watch mechanism against a temporary file rather than
/// the real wallpaper index, which cannot be changed from a test.
@Suite("Wallpaper change monitor")
@MainActor
struct WallpaperChangeMonitorTests {
    private func withWatchedFile(
        _ body: @MainActor (URL, WallpaperChangeMonitor) async throws -> Void
    ) async throws {
        let directory = URL.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Index.plist")
        try Data("seed".utf8).write(to: url)

        let monitor = WallpaperChangeMonitor(url: url, debounce: .milliseconds(50))
        defer { monitor.stop() }

        try await body(url, monitor)
    }

    /// Polls rather than sleeping a fixed interval, so a slow machine adds
    /// latency instead of a spurious failure.
    private func waitForChange(_ counter: @MainActor () -> Int, from start: Int) async -> Bool {
        for _ in 0 ..< 100 {
            if counter() > start { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test("A write to the watched file reports a change")
    func writeReportsChange() async throws {
        try await withWatchedFile { url, monitor in
            var changes = 0
            monitor.onChange = { changes += 1 }
            monitor.start()

            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data("changed".utf8))
            try handle.close()

            #expect(await waitForChange({ changes }, from: 0))
        }
    }

    @Test("An atomic replacement keeps reporting later changes")
    func atomicReplacementRearms() async throws {
        try await withWatchedFile { url, monitor in
            var changes = 0
            monitor.onChange = { changes += 1 }
            monitor.start()

            // How the system actually rewrites the index: the watched inode
            // is unlinked rather than written in place. Without a re-open,
            // the monitor would go deaf after this first replacement.
            try Data("first".utf8).write(to: url, options: .atomic)
            #expect(await waitForChange({ changes }, from: 0))

            let afterFirst = changes
            try Data("second".utf8).write(to: url, options: .atomic)
            #expect(await waitForChange({ changes }, from: afterFirst))
        }
    }

    @Test("A burst of writes is coalesced into one change")
    func burstIsDebounced() async throws {
        try await withWatchedFile { url, monitor in
            var changes = 0
            monitor.onChange = { changes += 1 }
            monitor.start()

            let handle = try FileHandle(forWritingTo: url)
            for index in 0 ..< 10 {
                try handle.write(contentsOf: Data("burst\(index)".utf8))
            }
            try handle.close()

            #expect(await waitForChange({ changes }, from: 0))
            // Let the debounce window close before reading the total.
            try? await Task.sleep(for: .milliseconds(300))
            #expect(changes == 1)
        }
    }

    @Test("A missing file is tolerated rather than fatal")
    func missingFileIsTolerated() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/Index.plist")
        let monitor = WallpaperChangeMonitor(url: url)
        defer { monitor.stop() }

        var changes = 0
        monitor.onChange = { changes += 1 }
        monitor.start()

        try? await Task.sleep(for: .milliseconds(100))
        #expect(changes == 0)
    }

    @Test("The watched index path matches the location macOS 26 uses")
    func indexPathIsTheWallpaperStore() {
        let path = WallpaperChangeMonitor.indexURL.path
        #expect(path.hasSuffix("Library/Application Support/com.apple.wallpaper/Store/Index.plist"))
    }
}
