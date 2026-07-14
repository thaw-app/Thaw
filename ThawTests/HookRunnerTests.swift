//
//  HookRunnerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation
@testable import Thaw
import XCTest

final class HookRunnerTests: XCTestCase {
    func testRunCapturesOutputWhenHostStdoutWasClosed() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-hook-runner-closed-stdout-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = "#!/bin/sh\nprintf out\nprintf err >&2\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let savedStdout = Darwin.dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(savedStdout, 0)
        defer {
            _ = Darwin.dup2(savedStdout, STDOUT_FILENO)
            _ = Darwin.close(savedStdout)
        }

        XCTAssertEqual(Darwin.close(STDOUT_FILENO), 0)
        let result: Result<HookRunner.RunOutcome, Error>
        do {
            result = .success(try await HookRunner.run(
                HookScript(path: scriptURL.path, timeoutSeconds: 2),
                context: HookRunner.Context(
                    phase: .pre,
                    scope: .profile,
                    profileID: UUID(),
                    profileName: "Test",
                    previousProfileID: nil,
                    previousProfileName: nil
                )
            ))
        } catch {
            result = .failure(error)
        }
        XCTAssertGreaterThanOrEqual(Darwin.dup2(savedStdout, STDOUT_FILENO), 0)

        switch result {
        case let .success(outcome):
            XCTAssertEqual(outcome.exitStatus, 0)
            XCTAssertEqual(outcome.stdout, "out")
            XCTAssertEqual(outcome.stderr, "err")
        case let .failure(error):
            XCTFail("Hook launch with inherited closed stdout failed: \(error)")
        }
    }

    func testRunDrainsLargeStdoutBeforeWaitingForExit() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-hook-runner-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        // Exceeds a standard pipe buffer. Reading only after the child exits
        // would leave `yes` blocked in its write and make the hook time out.
        let script = "#!/bin/sh\nyes x | head -c 131072\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let outcome = try await HookRunner.run(
            HookScript(path: scriptURL.path, timeoutSeconds: 2),
            context: HookRunner.Context(
                phase: .pre,
                scope: .profile,
                profileID: UUID(),
                profileName: "Test",
                previousProfileID: nil,
                previousProfileName: nil
            )
        )

        XCTAssertEqual(outcome.exitStatus, 0)
        // HookRunner trims the final newline before returning text; the
        // assertion only needs to prove that output exceeded a pipe buffer.
        XCTAssertGreaterThan(outcome.stdout.utf8.count, 100_000)
        XCTAssertTrue(outcome.stderr.isEmpty)
    }

    func testRunDoesNotWaitForDetachedChildHoldingOutputPipeOpen() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-hook-runner-detached-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = "#!/bin/sh\n(sleep 2) &\nprintf done\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let startedAt = Date()
        let outcome = try await HookRunner.run(
            HookScript(path: scriptURL.path, timeoutSeconds: 1),
            context: HookRunner.Context(
                phase: .post,
                scope: .profile,
                profileID: UUID(),
                profileName: "Test",
                previousProfileID: nil,
                previousProfileName: nil
            )
        )

        XCTAssertEqual(outcome.exitStatus, 0)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    func testTimedOutHookTerminatesDetachedDescendant() async throws {
        let directory = FileManager.default.temporaryDirectory
        let markerURL = directory.appendingPathComponent("thaw-hook-child-\(UUID().uuidString)")
        let scriptURL = directory.appendingPathComponent("thaw-hook-runner-timeout-\(UUID().uuidString).sh")
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

        do {
            _ = try await HookRunner.run(
                HookScript(path: scriptURL.path, timeoutSeconds: 1),
                context: HookRunner.Context(
                    phase: .pre,
                    scope: .global,
                    profileID: UUID(),
                    profileName: "Test",
                    previousProfileID: nil,
                    previousProfileName: nil
                )
            )
            XCTFail("Timed-out hook unexpectedly completed")
        } catch is HookRunner.HookError {
            // Expected: the direct script and its background child are killed.
        }

        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testTimeoutEscalatesAfterDirectShellExitsToKillTermIgnoringDescendant() async throws {
        let directory = FileManager.default.temporaryDirectory
        let pidURL = directory.appendingPathComponent("thaw-hook-child-pid-\(UUID().uuidString)")
        let scriptURL = directory.appendingPathComponent("thaw-hook-runner-term-ignore-\(UUID().uuidString).sh")
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

        do {
            _ = try await HookRunner.run(
                HookScript(path: scriptURL.path, timeoutSeconds: 1),
                context: HookRunner.Context(
                    phase: .pre,
                    scope: .global,
                    profileID: UUID(),
                    profileName: "Test",
                    previousProfileID: nil,
                    previousProfileName: nil
                )
            )
            XCTFail("Timed-out hook unexpectedly completed")
        } catch is HookRunner.HookError {
            // Expected: escalation reaches the TERM-ignoring child too.
        }

        let childPID = try XCTUnwrap(
            (try? String(contentsOf: pidURL, encoding: .utf8))
                .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
        XCTAssertNotEqual(Darwin.kill(childPID, 0), 0)
    }
}
