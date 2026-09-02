//
//  HookProcessTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Exercises ``HookRunner.HookProcess`` with real child processes.
///
/// The suite launches short-lived system binaries only: `/bin/echo`,
/// `/usr/bin/false`, and `/bin/sleep`. No app state is touched.
@Suite("Hook process")
struct HookProcessTests {
    // MARK: - Launch & exit status

    @Test("A successful launch captures stdout and exits 0")
    func echoExitsZero() async throws {
        let pipe = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/bin/echo",
            arguments: ["hello from the hook"],
            environment: [:],
            combinedOutput: pipe
        )
        // The child inherited the writer; closing ours makes EOF meaningful.
        pipe.fileHandleForWriting.closeFile()

        while process.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(process.terminationStatus == 0)
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == "hello from the hook\n")
    }

    @Test("A failing command reports its exit status")
    func falseExitsOne() async throws {
        let pipe = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/usr/bin/false",
            arguments: [],
            environment: [:],
            combinedOutput: pipe
        )
        pipe.fileHandleForWriting.closeFile()

        while process.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(process.terminationStatus == 1)
    }

    @Test("Environment entries reach the child")
    func environmentReachesChild() async throws {
        let pipe = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf %s \"$HOOK_PROCESS_TEST_VALUE\""],
            environment: ["HOOK_PROCESS_TEST_VALUE": "propagated", "PATH": "/usr/bin:/bin"],
            combinedOutput: pipe
        )
        pipe.fileHandleForWriting.closeFile()

        while process.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(process.terminationStatus == 0)
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == "propagated")
    }

    @Test("A nonexistent executable throws instead of crashing")
    func missingExecutableThrows() {
        let pipe = Pipe()
        #expect(throws: (any Error).self) {
            _ = try HookRunner.HookProcess.launch(
                executablePath: "/nonexistent/hook-process-helper",
                arguments: [],
                environment: [:],
                combinedOutput: pipe
            )
        }
    }

    // MARK: - Lifetime & signals

    @Test("terminate escalates the same way the app's timeout ladder does")
    func terminateStopsTheChild() async throws {
        let pipe = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/bin/sleep",
            arguments: ["30"],
            environment: [:],
            combinedOutput: pipe
        )
        pipe.fileHandleForWriting.closeFile()
        #expect(process.isRunning)

        // The app's timeout ladder: TERM, then INT, then KILL. A courteous
        // first signal cannot be relied on to end the child — the spawning
        // process's signal mask is inherited, which is exactly why the
        // ladder ends in SIGKILL — and the group must drain afterwards.
        //
        // The courtesy rungs get a short wait rather than the full deadline:
        // under a test host that inherited SIGTERM ignored they can never
        // succeed, and spending the whole budget waiting for them leaves the
        // uncancellable rung nothing left to run in.
        process.terminate()
        try await Self.waitUntilTerminated(process, timeout: .milliseconds(500))
        if process.isRunning {
            process.interrupt()
            try await Self.waitUntilTerminated(process, timeout: .milliseconds(500))
        }
        if process.isRunning {
            process.kill()
        }

        // Reap first, then confirm the group drained. `hasLiveProcessGroup`
        // can go false while an unreaped exit status is still outstanding, so
        // asserting on a sample taken before the reap is a race.
        try await Self.waitUntilTerminated(process)
        try await Self.waitUntilGroupDrained(process)

        #expect(!process.isRunning)
        #expect(!process.hasLiveProcessGroup)
    }

    @Test("kill stops a running child with SIGKILL")
    func killStopsTheChild() async throws {
        let pipe = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/bin/sleep",
            arguments: ["30"],
            environment: [:],
            combinedOutput: pipe
        )
        pipe.fileHandleForWriting.closeFile()

        process.kill()
        try await Self.waitUntilTerminated(process)

        #expect(process.terminationStatus == 128 + 9)
    }

    @Test("The process group drains after the child exits")
    func processGroupDrains() async throws {
        let pipe = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/bin/sleep",
            arguments: ["30"],
            environment: [:],
            combinedOutput: pipe
        )
        pipe.fileHandleForWriting.closeFile()
        #expect(process.hasLiveProcessGroup)

        process.kill()
        try await Self.waitUntilGroupDrained(process)

        #expect(!process.hasLiveProcessGroup)
    }

    // MARK: - Separate output streams

    @Test("Separate pipes keep stdout and stderr apart")
    func separatePipesStaySeparate() async throws {
        let standardOutput = Pipe()
        let standardError = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2"],
            environment: ["PATH": "/usr/bin:/bin"],
            standardOutput: standardOutput,
            standardError: standardError
        )
        standardOutput.fileHandleForWriting.closeFile()
        standardError.fileHandleForWriting.closeFile()

        try await Self.waitUntilTerminated(process)

        #expect(process.terminationStatus == 0)
        let out = try #require(String(
            bytes: standardOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ))
        let err = try #require(String(
            bytes: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ))
        #expect(out == "out")
        #expect(err == "err")
    }

    @Test("A separate-pipe launch reports a failing exit status")
    func separatePipesReportFailure() async throws {
        let standardOutput = Pipe()
        let standardError = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/usr/bin/false",
            arguments: [],
            environment: [:],
            standardOutput: standardOutput,
            standardError: standardError
        )
        standardOutput.fileHandleForWriting.closeFile()
        standardError.fileHandleForWriting.closeFile()

        try await Self.waitUntilTerminated(process)

        #expect(process.terminationStatus == 1)
    }

    @Test("A separate-pipe launch also runs in its own process group")
    func separatePipesGetTheirOwnProcessGroup() async throws {
        let standardOutput = Pipe()
        let standardError = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/bin/sleep",
            arguments: ["30"],
            environment: [:],
            standardOutput: standardOutput,
            standardError: standardError
        )
        standardOutput.fileHandleForWriting.closeFile()
        standardError.fileHandleForWriting.closeFile()

        // The group is what lets a timeout reap descendants a shell hook
        // leaves behind, so both launchers must establish one.
        #expect(process.hasLiveProcessGroup)
        process.kill()
        try await Self.waitUntilTerminated(process)
        try await Self.waitUntilGroupDrained(process)

        #expect(!process.hasLiveProcessGroup)
    }

    @Test("A missing executable throws on the separate-pipe launcher too")
    func separatePipesMissingExecutableThrows() {
        #expect(throws: (any Error).self) {
            _ = try HookRunner.HookProcess.launch(
                executablePath: "/nonexistent/hook-process-helper",
                arguments: [],
                environment: [:],
                standardOutput: Pipe(),
                standardError: Pipe()
            )
        }
    }

    // MARK: - Status caching

    @Test("A reaped process keeps reporting the same status")
    func statusIsCachedAfterReaping() async throws {
        let pipe = Pipe()
        let process = try HookRunner.HookProcess.launch(
            executablePath: "/usr/bin/false",
            arguments: [],
            environment: [:],
            combinedOutput: pipe
        )
        pipe.fileHandleForWriting.closeFile()

        try await Self.waitUntilTerminated(process)

        // The second read cannot call waitpid again and get ECHILD; the first
        // one recorded the status, and every later caller sees it.
        #expect(process.terminationStatus == 1)
        #expect(process.terminationStatus == 1)
        #expect(!process.isRunning)
    }

    // MARK: - Helpers

    /// How long the polling helpers wait before giving up and letting the
    /// caller's expectation report the failure.
    ///
    /// A wall-clock deadline rather than a fixed iteration count: each pass
    /// costs a 10 ms sleep *plus* scheduling, so on a loaded CI runner a
    /// 500-iteration loop is worth well over the five seconds it reads as,
    /// and the ladder above then overruns the budget it was sized for.
    private static let pollTimeout = Duration.seconds(10)

    /// Polls until the direct child has been reaped, with a generous
    /// timeout so a wedged runner fails on the expectation, not on a hang.
    private static func waitUntilTerminated(
        _ process: HookRunner.HookProcess,
        timeout: Duration = pollTimeout
    ) async throws {
        try await poll(until: timeout) { !process.isRunning }
    }

    /// Polls until no member of the child's process group is alive.
    private static func waitUntilGroupDrained(
        _ process: HookRunner.HookProcess,
        timeout: Duration = pollTimeout
    ) async throws {
        try await poll(until: timeout) {
            // Reaping on every pass keeps `isRunning` from reporting a child
            // that has already exited, which is what the callers assert next.
            _ = process.isRunning
            return !process.hasLiveProcessGroup
        }
    }

    /// Polls `condition` every 10 ms until it holds or `timeout` elapses.
    private static func poll(
        until timeout: Duration,
        condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = condition()
    }
}
