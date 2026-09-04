//
//  DiagnosticLoggerFileTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the on-disk half of ``DiagnosticLogger``: attaching to a file,
/// appending instead of truncating, closing, and the retention pass that keeps
/// a user's `~/Library/Logs/Thaw` directory from growing without bound.
///
/// This is the mechanism behind user-submitted diagnostics and it is shared
/// verbatim with the MenuBarItemService XPC target, so the rotation and
/// append-vs-truncate behaviour is worth pinning down.
///
/// `attachToFile(at:)` is the only entry point that accepts a caller-supplied
/// URL, so every case here drives the shared singleton at a per-test temporary
/// directory. Nothing in this file writes to the real log directory: the
/// fresh-mint `openLogFile()` path and everything reached through
/// `isEnabled = true` are deliberately left uncovered because they would mint a
/// file in the developer's own `~/Library/Logs/Thaw`. `logDirectory`,
/// `latestLogFile` and `hasLogFiles` are likewise hard-wired to that path and
/// are only read here, never written through.
///
/// The suite is `.serialized` because it mutates process-wide singleton state.
/// Other suites may still run in parallel and emit `DiagLog` lines into the
/// file we attached, so assertions check for containment rather than for exact
/// file contents.
@Suite("Diagnostic logger file handling", .serialized)
struct DiagnosticLoggerFileTests {
    // MARK: Attaching

    @Test("Attaching creates any missing directories and opens the file")
    func attachingCreatesTheDirectoryTree() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("deeper", isDirectory: true)
                .appendingPathComponent("thaw.log")

            DiagnosticLogger.shared.attachToFile(at: file)

            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(DiagnosticLogger.shared.isEnabled)
            #expect(DiagnosticLogger.shared.currentLogFile == file)
        }
    }

    @Test("Attaching writes a header naming the process that opened the file")
    func attachingWritesAHeader() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp.appendingPathComponent("thaw.log")

            DiagnosticLogger.shared.attachToFile(at: file)

            // The header is written on the calling thread, not the write
            // queue, so it is observable without waiting.
            let text = contents(of: file)
            #expect(text.contains("Thaw Diagnostic Log"))
            #expect(text.contains("Process: \(ProcessInfo.processInfo.processName)"))
            #expect(text.contains("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"))
        }
    }

    @Test("Attaching to a file that already holds lines appends instead of truncating")
    func attachingAppendsToAnExistingFile() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp.appendingPathComponent("thaw.log")
            // Stands in for the other process having written first: two
            // processes share one file, so opening it must not lose what is
            // already there.
            try Data("written by the other process\n".utf8).write(to: file)

            DiagnosticLogger.shared.attachToFile(at: file)

            let text = contents(of: file)
            #expect(text.contains("written by the other process"))
            #expect(text.contains("Thaw Diagnostic Log"))
        }
    }

    @Test("Re-attaching to the file already open changes nothing")
    func reattachingToTheSameFileIsANoOp() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp.appendingPathComponent("thaw.log")

            DiagnosticLogger.shared.attachToFile(at: file)
            DiagnosticLogger.shared.attachToFile(at: file)

            // The app re-sends the current path on every rotation and on retry,
            // so the same path arrives repeatedly. Reopening it would stamp a
            // second header and a stop footer into the file being written, which
            // reads as if logging had restarted mid-capture.
            let text = contents(of: file)
            #expect(occurrences(of: "Thaw Diagnostic Log", in: text) == 1)
            #expect(occurrences(of: "Diagnostic logging stopped", in: text) == 0)
            #expect(DiagnosticLogger.shared.currentLogFile == file)
        }
    }

    @Test("Attaching to a second file closes the first and switches the current file")
    func attachingToAnotherFileSwitchesOver() async throws {
        try await withTemporaryLogDirectory { tmp in
            let first = tmp.appendingPathComponent("first.log")
            let second = tmp.appendingPathComponent("second.log")

            DiagnosticLogger.shared.attachToFile(at: first)
            DiagnosticLogger.shared.attachToFile(at: second)

            #expect(DiagnosticLogger.shared.currentLogFile == second)
            #expect(contents(of: first).contains("Diagnostic logging stopped"))
            #expect(contents(of: second).contains("Thaw Diagnostic Log"))
            #expect(!contents(of: second).contains("Diagnostic logging stopped"))
        }
    }

    // MARK: Closing

    @Test("Disabling writes a stop footer and forgets the current file")
    func disablingClosesTheFile() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp.appendingPathComponent("thaw.log")
            DiagnosticLogger.shared.attachToFile(at: file)

            DiagnosticLogger.shared.isEnabled = false

            #expect(DiagnosticLogger.shared.currentLogFile == nil)
            #expect(contents(of: file).contains("Diagnostic logging stopped"))
        }
    }

    @Test("Disabling twice is harmless and writes only one footer")
    func disablingIsIdempotent() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp.appendingPathComponent("thaw.log")
            DiagnosticLogger.shared.attachToFile(at: file)

            DiagnosticLogger.shared.isEnabled = false
            DiagnosticLogger.shared.isEnabled = false

            #expect(DiagnosticLogger.shared.currentLogFile == nil)
            #expect(occurrences(of: "Diagnostic logging stopped", in: contents(of: file)) == 1)
        }
    }

    // MARK: Writing

    @Test("A logged message lands in the attached file with its level and category")
    func messagesReachTheFile() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp.appendingPathComponent("thaw.log")
            DiagnosticLogger.shared.attachToFile(at: file)
            let message = "payload-\(UUID().uuidString)"

            DiagnosticLogger.shared.log(level: .warning, category: "FileTests", message: message)

            let landed = await waitUntil {
                contents(of: file).contains("[WARNING] [FileTests] \(message)")
            }
            #expect(landed, "the message never reached the log file")
        }
    }

    @Test("A message logged while disabled is dropped rather than buffered")
    func messagesLoggedWhileDisabledAreDropped() async throws {
        try await withTemporaryLogDirectory { tmp in
            let file = tmp.appendingPathComponent("thaw.log")
            DiagnosticLogger.shared.attachToFile(at: file)
            DiagnosticLogger.shared.isEnabled = false
            let dropped = "dropped-\(UUID().uuidString)"

            DiagnosticLogger.shared.log(level: .info, category: "FileTests", message: dropped)

            // Re-attach and push a marker through the same serial write queue.
            // The queue is FIFO, so once the marker has landed anything
            // enqueued before it would already be in the file — that turns the
            // absence check below into an ordering guarantee rather than a race
            // against a fixed sleep.
            DiagnosticLogger.shared.attachToFile(at: file)
            let marker = "marker-\(UUID().uuidString)"
            DiagnosticLogger.shared.log(level: .info, category: "FileTests", message: marker)

            let landed = await waitUntil { contents(of: file).contains(marker) }
            #expect(landed, "the marker never reached the log file")
            #expect(!contents(of: file).contains(dropped))
        }
    }

    // MARK: Retention

    /// Pins the retention policy for one test.
    ///
    /// The policy lives on the shared logger, so a value left behind by another
    /// suite would otherwise decide the outcome here. `withTemporaryLogDirectory`
    /// puts the previous one back, so this test does not decide anyone else's.
    private func useRetentionPolicy(retentionDays: Int, maxFileCount: Int = 50) {
        var policy = DiagnosticLogger.RotationPolicy()
        policy.retentionDays = retentionDays
        policy.maxFileCount = maxFileCount
        DiagnosticLogger.shared.setRotationPolicy(policy)
    }

    @Test("Opening a log file prunes the logs that fell out of the retention window")
    func retentionDropsLogsPastTheWindow() async throws {
        try await withTemporaryLogDirectory { tmp in
            useRetentionPolicy(retentionDays: 2)
            // Seeds are aged one day apart, oldest first: seed-0 is 7 days old,
            // seed-6 is one day old.
            let seeded = try seedAgedLogFiles(count: 7, in: tmp)
            let file = tmp.appendingPathComponent("current.log")

            DiagnosticLogger.shared.attachToFile(at: file)

            // Only the one-day-old seed is still inside a two-day window, and
            // the file just opened is never a candidate.
            let pruned = await waitUntil { logFileNames(in: tmp).count == 2 }
            #expect(pruned, "retention left \(logFileNames(in: tmp).count) log files")

            let survivors = Set(logFileNames(in: tmp))
            #expect(survivors.contains("current.log"))
            #expect(survivors.contains(seeded[6]))
            #expect(survivors.isDisjoint(with: seeded.prefix(6)))
        }
    }

    @Test("Retention only prunes log files and leaves other files alone")
    func retentionIgnoresNonLogFiles() async throws {
        try await withTemporaryLogDirectory { tmp in
            useRetentionPolicy(retentionDays: 2)
            try seedAgedLogFiles(count: 7, in: tmp)
            let keepsake = tmp.appendingPathComponent("notes.txt")
            try Data("keep me".utf8).write(to: keepsake)

            DiagnosticLogger.shared.attachToFile(at: tmp.appendingPathComponent("current.log"))

            let pruned = await waitUntil { logFileNames(in: tmp).count == 2 }
            #expect(pruned, "retention left \(logFileNames(in: tmp).count) log files")
            #expect(FileManager.default.fileExists(atPath: keepsake.path))
        }
    }

    @Test("A directory whose logs are all inside the window is left untouched")
    func retentionLeavesRecentLogsAlone() async throws {
        try await withTemporaryLogDirectory { tmp in
            // Every seed is days old, but the window is a month wide.
            useRetentionPolicy(retentionDays: 30)
            let seeded = try seedAgedLogFiles(count: 4, in: tmp)

            DiagnosticLogger.shared.attachToFile(at: tmp.appendingPathComponent("current.log"))

            // Give the write queue a chance to misbehave before asserting.
            let overPruned = await waitUntil(timeout: .milliseconds(500)) {
                logFileNames(in: tmp).count < 5
            }
            #expect(!overPruned)
            #expect(Set(logFileNames(in: tmp)).isSuperset(of: seeded))
        }
    }

    @Test("One undeletable log does not stop retention from pruning the rest")
    func retentionContinuesPastAnUndeletableLog() async throws {
        try await withTemporaryLogDirectory { tmp in
            useRetentionPolicy(retentionDays: 2)
            // Ages run 8 days (seed-0) down to one day (seed-7).
            let seeded = try seedAgedLogFiles(count: 8, in: tmp)

            // Retention walks the doomed files newest-first, so making the
            // *first* casualty undeletable is what proves the loop carries on:
            // the older ones are only reached after the failure.
            let stubborn = tmp.appendingPathComponent("seed-6.log")
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: stubborn.path)
            defer {
                // The flag has to go before the enclosing helper deletes `tmp`,
                // or the temporary directory outlives the test.
                try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: stubborn.path)
            }

            DiagnosticLogger.shared.attachToFile(at: tmp.appendingPathComponent("current.log"))

            // The one-day-old seed, the file just opened, and the one that
            // refused to go. Without the per-file error handling this settles at
            // nine: the failure aborts the loop and every later deletion is
            // skipped.
            let pruned = await waitUntil { logFileNames(in: tmp).count == 3 }
            #expect(pruned, "retention left \(logFileNames(in: tmp).count) log files")

            let survivors = Set(logFileNames(in: tmp))
            #expect(survivors.contains("seed-6.log"))
            #expect(survivors.contains(seeded[7]))
            #expect(survivors.contains("current.log"))
            #expect(survivors.isDisjoint(with: seeded.prefix(6)))
        }
    }

    // MARK: Failure paths

    @Test("Attaching below a path that is a regular file leaves logging disabled")
    func attachingUnderAFileFails() async throws {
        try await withTemporaryLogDirectory { tmp in
            let blocker = tmp.appendingPathComponent("blocker")
            try Data().write(to: blocker)
            let file = blocker
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("thaw.log")

            let attached = DiagnosticLogger.shared.attachToFile(at: file)

            // With no earlier segment to fall back on there is nothing to write
            // to, so logging has to stay off rather than look enabled.
            #expect(!attached)
            #expect(!DiagnosticLogger.shared.isEnabled)
            #expect(DiagnosticLogger.shared.currentLogFile == nil)
        }
    }

    @Test("A failed attach keeps writing to the segment already open")
    func failedAttachKeepsThePreviousFile() async throws {
        try await withTemporaryLogDirectory { tmp in
            let good = tmp.appendingPathComponent("good.log")
            DiagnosticLogger.shared.attachToFile(at: good)

            let blocker = tmp.appendingPathComponent("blocker")
            try Data().write(to: blocker)
            let unopenable = blocker
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("thaw.log")

            let attached = DiagnosticLogger.shared.attachToFile(at: unopenable)

            // Losing the open must not cost the lines still being written: the
            // previous file stays, and the caller is told so it can retry.
            #expect(!attached)
            #expect(DiagnosticLogger.shared.isEnabled)
            #expect(DiagnosticLogger.shared.currentLogFile == good)

            let marker = "still writing after a failed attach"
            DiagnosticLogger.shared.log(level: .info, category: "Test", message: marker)
            let landed = await waitUntil { contents(of: good).contains(marker) }
            #expect(landed, "the marker never reached the surviving log file")
        }
    }

    @Test(
        "Attaching inside an unwritable directory leaves logging disabled",
        .enabled(if: getuid() != 0, "root bypasses directory permissions")
    )
    func attachingIntoAnUnwritableDirectoryFails() async throws {
        try await withTemporaryLogDirectory { tmp in
            let locked = tmp.appendingPathComponent("locked", isDirectory: true)
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

            // The directory already exists, so `createDirectory` succeeds and
            // it is `open(2)` itself that fails with EACCES.
            DiagnosticLogger.shared.attachToFile(at: locked.appendingPathComponent("thaw.log"))

            #expect(!DiagnosticLogger.shared.isEnabled)
            #expect(DiagnosticLogger.shared.currentLogFile == nil)
        }
    }

    // MARK: Log directory

    @Test("The log directory is Library/Logs/Thaw inside the user's home")
    func logDirectoryIsUnderTheUserLibrary() {
        let directory = DiagnosticLogger.shared.logDirectory

        #expect(directory.lastPathComponent == "Thaw")
        #expect(directory.deletingLastPathComponent().lastPathComponent == "Logs")
        #expect(directory.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    @Test("hasLogFiles agrees with latestLogFile, which always names a log in the log directory")
    func latestLogFileIsSelfConsistent() {
        // Read-only against the real log directory: whether the developer has
        // logs there is not something a test may assume, but the two accessors
        // must agree either way.
        let logger = DiagnosticLogger.shared
        let latest = logger.latestLogFile

        #expect(logger.hasLogFiles == (latest != nil))
        if let latest {
            #expect(latest.pathExtension == "log")
            #expect(latest.deletingLastPathComponent().path == logger.logDirectory.path)
        }
    }

    // MARK: - Helpers

    /// Runs `body` against a fresh temporary directory, then detaches the
    /// shared logger and removes the directory.
    ///
    /// Detaching first matters: leaving the singleton holding a file handle on
    /// a deleted temporary file would follow every later test in this process.
    /// Teardown always lands on "disabled", never on the flag's previous value,
    /// because re-enabling would run the fresh-mint path and drop a file in the
    /// developer's real log directory.
    ///
    /// The rotation policy is process-wide too, so it is captured here and put
    /// back on every exit path: a window pinned by one test would otherwise
    /// follow whichever test runs next, in this suite or in a parallel one.
    private func withTemporaryLogDirectory(_ body: (URL) async throws -> Void) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let previousPolicy = DiagnosticLogger.shared.rotationPolicy
        defer {
            DiagnosticLogger.shared.isEnabled = false
            DiagnosticLogger.shared.setRotationPolicy(previousPolicy)
            try? FileManager.default.removeItem(at: tmp)
        }

        try await body(tmp)
    }

    /// Creates `count` empty `.log` files dated one day apart, oldest first, and
    /// returns their names in that order.
    ///
    /// Rotation orders by creation date, and files written back to back in a
    /// loop can share a timestamp closely enough to make the survivor set
    /// arbitrary — explicit dates keep it deterministic. All of them are dated
    /// in the past so that a file opened during the test is unambiguously the
    /// newest.
    @discardableResult
    private func seedAgedLogFiles(count: Int, in directory: URL) throws -> [String] {
        var names: [String] = []
        for index in 0 ..< count {
            let name = "seed-\(index).log"
            let url = directory.appendingPathComponent(name)
            try Data().write(to: url)
            let age = TimeInterval(count - index) * 86400
            try FileManager.default.setAttributes(
                [.creationDate: Date(timeIntervalSinceNow: -age)],
                ofItemAtPath: url.path
            )
            names.append(name)
        }
        return names
    }

    /// The names of every `.log` file directly inside `directory`.
    private func logFileNames(in directory: URL) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return urls.filter { $0.pathExtension == "log" }.map(\.lastPathComponent)
    }

    /// The file's text, or an empty string if it cannot be read.
    private func contents(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    /// Polls `condition` until it holds or `timeout` elapses, reporting whether
    /// it ever held.
    ///
    /// Rotation and message writes are dispatched onto the logger's private
    /// serial queue, which the test cannot join, so a bounded poll is the only
    /// way to observe them without betting on a fixed sleep.
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
