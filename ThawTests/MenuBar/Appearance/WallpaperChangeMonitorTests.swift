//
//  WallpaperChangeMonitorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Exercises the file-watch mechanism against a temporary file rather than
/// the real wallpaper index, which cannot be changed from a test.
@Suite("Wallpaper change monitor", .timeLimit(.minutes(1)))
@MainActor
struct WallpaperChangeMonitorTests {
    private func withWatchedFile(
        debounce: Duration = .milliseconds(50),
        restartRetryDelay: Duration = .milliseconds(500),
        _ body: @MainActor (URL, WallpaperChangeMonitor) async throws -> Void
    ) async throws {
        let directory = URL.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Index.plist")
        try Data("seed".utf8).write(to: url)

        let monitor = WallpaperChangeMonitor(url: url, debounce: debounce, restartRetryDelay: restartRetryDelay)
        defer { monitor.stop() }

        try await body(url, monitor)
    }

    /// Counts the monitor's changes and hands back each report as it comes. A file event arrives
    /// when the system delivers it, so a test waits for the report, not a counter against a deadline.
    private func watch(_ monitor: WallpaperChangeMonitor) -> (count: () -> Int, reports: AsyncStream<Void>) {
        let (reports, signal) = AsyncStream<Void>.makeStream()
        var count = 0
        monitor.onChange = {
            count += 1
            signal.yield()
        }
        return ({ count }, reports)
    }

    @Test("A write to the watched file reports a change")
    func writeReportsChange() async throws {
        try await withWatchedFile { url, monitor in
            let (changes, stream) = watch(monitor)
            var reports = stream.makeAsyncIterator()
            monitor.start()

            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data("changed".utf8))
            try handle.close()

            _ = await reports.next()
            #expect(changes() == 1)
        }
    }

    @Test("An atomic replacement keeps reporting later changes")
    func atomicReplacementRearms() async throws {
        try await withWatchedFile { url, monitor in
            let (changes, stream) = watch(monitor)
            var reports = stream.makeAsyncIterator()
            monitor.start()

            // How the system actually rewrites the index: the watched inode
            // is unlinked rather than written in place. Without a re-open,
            // the monitor would go deaf after this first replacement.
            try Data("first".utf8).write(to: url, options: .atomic)
            _ = await reports.next()
            #expect(changes() >= 1)

            let afterFirst = changes()
            try Data("second".utf8).write(to: url, options: .atomic)
            _ = await reports.next()
            #expect(changes() > afterFirst)
        }
    }

    @Test("A burst of writes is coalesced into one change")
    func burstIsDebounced() async throws {
        try await withWatchedFile { url, monitor in
            let (changes, stream) = watch(monitor)
            var reports = stream.makeAsyncIterator()
            monitor.start()

            let handle = try FileHandle(forWritingTo: url)
            for index in 0 ..< 10 {
                try handle.write(contentsOf: Data("burst\(index)".utf8))
            }
            try handle.close()

            _ = await reports.next()
            // Let the debounce window close before reading the total.
            try? await Task.sleep(for: .milliseconds(300))
            #expect(changes() == 1)
        }
    }

    @Test("A replacement that is not there yet when the monitor re-opens is picked up by the retry")
    func lateReplacementIsPickedUpByTheRetry() async throws {
        try await withWatchedFile(debounce: .milliseconds(20), restartRetryDelay: .seconds(1)) { url, monitor in
            let (changes, stream) = watch(monitor)
            var reports = stream.makeAsyncIterator()
            monitor.start()

            // The re-open after the delete finds no file, so only the retry can re-arm the watch.
            // The delete's report comes after 20 ms, well before the retry a second later.
            try FileManager.default.removeItem(at: url)
            _ = await reports.next()
            try Data("replaced".utf8).write(to: url)
            try? await Task.sleep(for: .milliseconds(1500))
            let beforeWrite = changes()

            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data("changed".utf8))
            try handle.close()
            while changes() == beforeWrite, await reports.next() != nil {}
            #expect(changes() > beforeWrite)
        }
    }

    @Test("A missing file is tolerated rather than fatal")
    func missingFileIsTolerated() async {
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
