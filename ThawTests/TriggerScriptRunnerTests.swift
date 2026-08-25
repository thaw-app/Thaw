//
//  TriggerScriptRunnerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation
@testable import Thaw
import XCTest

@MainActor
final class TriggerScriptRunnerTests: XCTestCase {
    /// Waits for `condition` to hold, up to `timeout`.
    ///
    /// The runner's own teardown is not instantaneous -- SIGTERM, a 500 ms
    /// pause, SIGINT, 100 ms, SIGKILL, then up to a second of group drain --
    /// and `run` can return before the kernel has finished reaping. Asserting
    /// the post-state immediately therefore races that budget and flakes on a
    /// loaded machine. Polling keeps the assertion meaningful without pinning
    /// it to a wall-clock guess.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func testRunCapturesCombinedOutputWhenHostStdoutWasClosed() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-trigger-script-closed-stdout-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = "#!/bin/sh\nprintf out\nprintf err >&2\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        // Descriptor 1 has to be genuinely closed for the duration of the
        // launch: the behaviour under test is that `Pipe()` may then reuse it,
        // which is what HookProcess's close-before-dup2 ordering guards
        // against. That window is process-wide and spans a suspension point,
        // so anything else in this process that opens a descriptor while it is
        // open can land on 1 and be clobbered by the restore below. XCTest
        // runs cases in a process serially, which bounds the exposure to
        // background work rather than to other tests -- but it does not
        // eliminate it, and this test should stay in its own file for that
        // reason. Restoring eagerly rather than only in the `defer` keeps the
        // window to the runner call itself.
        let savedStdout = Darwin.dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(savedStdout, 0)
        var restored = false
        defer {
            if !restored {
                _ = Darwin.dup2(savedStdout, STDOUT_FILENO)
            }
            _ = Darwin.close(savedStdout)
        }

        XCTAssertEqual(Darwin.close(STDOUT_FILENO), 0)
        let outcome = await TriggerScriptRunner.run(path: scriptURL.path, timeout: 2)
        XCTAssertGreaterThanOrEqual(Darwin.dup2(savedStdout, STDOUT_FILENO), 0)
        restored = true

        XCTAssertEqual(outcome?.exitCode, 0)
        XCTAssertTrue(outcome?.output.contains("out") == true)
        XCTAssertTrue(outcome?.output.contains("err") == true)
    }

    func testTimedOutScriptTerminatesDetachedDescendant() async throws {
        let directory = FileManager.default.temporaryDirectory
        let markerURL = directory.appendingPathComponent("thaw-trigger-script-child-\(UUID().uuidString)")
        let scriptURL = directory.appendingPathComponent("thaw-trigger-script-timeout-\(UUID().uuidString).sh")
        defer {
            try? FileManager.default.removeItem(at: markerURL)
            try? FileManager.default.removeItem(at: scriptURL)
        }

        let script = "#!/bin/sh\n(sleep 2; touch \(markerURL.path)) &\nwait\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let outcome = await TriggerScriptRunner.run(path: scriptURL.path, timeout: 1)

        XCTAssertEqual(outcome?.exitCode, -1)
        let markerGone = await waitUntil {
            !FileManager.default.fileExists(atPath: markerURL.path)
        }
        XCTAssertTrue(markerGone, "detached descendant outlived the timeout")
    }

    func testTimeoutEscalatesAfterDirectShellExitsToKillTermIgnoringDescendant() async throws {
        let directory = FileManager.default.temporaryDirectory
        let pidURL = directory.appendingPathComponent("thaw-trigger-script-child-pid-\(UUID().uuidString)")
        let scriptURL = directory.appendingPathComponent("thaw-trigger-script-term-ignore-\(UUID().uuidString).sh")
        defer {
            if let text = try? String(contentsOf: pidURL, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                _ = Darwin.kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: scriptURL)
        }

        let script = "#!/bin/sh\n(trap '' TERM INT; while :; do sleep 1; done) &\necho $! > \(pidURL.path)\nwait\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let outcome = await TriggerScriptRunner.run(path: scriptURL.path, timeout: 1)

        XCTAssertEqual(outcome?.exitCode, -1)
        let childPID = try XCTUnwrap(
            (try? String(contentsOf: pidURL, encoding: .utf8))
                .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
        let childGone = await waitUntil { Darwin.kill(childPID, 0) != 0 }
        XCTAssertTrue(childGone, "TERM-ignoring descendant outlived the escalation")
    }

    func testDetachedChildDoesNotHoldScriptResultOpen() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-trigger-script-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = "#!/bin/sh\n(sleep 2) &\nprintf done\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let startedAt = Date()
        let outcome = await TriggerScriptRunner.run(path: scriptURL.path, timeout: 1)

        XCTAssertEqual(outcome?.exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    func testExpectedOutputAfterDiagnosticCapIsStreamMatched() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-trigger-script-large-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = "#!/bin/sh\nhead -c 1100000 /dev/zero | tr '\\000' x\nprintf READY\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let outcome = await TriggerScriptRunner.run(
            path: scriptURL.path,
            timeout: 3,
            expectedOutputs: ["READY"]
        )

        XCTAssertEqual(outcome?.exitCode, 0)
        XCTAssertTrue(outcome?.matchedExpectedOutputs.contains("READY") == true)
    }

    func testUnicodeExpectedOutputSplitAcrossPipeReadsIsStreamMatched() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-trigger-script-unicode-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = "#!/bin/sh\nhead -c 1100000 /dev/zero | tr '\\000' x\nprintf '\\303'; sleep 0.2; printf '\\251'\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let outcome = await TriggerScriptRunner.run(
            path: scriptURL.path,
            timeout: 3,
            expectedOutputs: ["é"]
        )

        XCTAssertEqual(outcome?.exitCode, 0)
        XCTAssertTrue(outcome?.matchedExpectedOutputs.contains("é") == true)
    }

    func testMalformedByteBeforeUnicodeExpectedOutputIsStreamMatched() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-trigger-script-malformed-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = "#!/bin/sh\nhead -c 1100000 /dev/zero | tr '\\000' x\nprintf '\\377\\303\\251'\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let outcome = await TriggerScriptRunner.run(
            path: scriptURL.path,
            timeout: 3,
            expectedOutputs: ["é"]
        )

        XCTAssertEqual(outcome?.exitCode, 0)
        XCTAssertTrue(outcome?.matchedExpectedOutputs.contains("é") == true)
    }
}
