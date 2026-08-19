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

        let savedStdout = Darwin.dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(savedStdout, 0)
        defer {
            _ = Darwin.dup2(savedStdout, STDOUT_FILENO)
            _ = Darwin.close(savedStdout)
        }

        XCTAssertEqual(Darwin.close(STDOUT_FILENO), 0)
        let outcome = await TriggerScriptRunner.run(path: scriptURL.path, timeout: 2)
        XCTAssertGreaterThanOrEqual(Darwin.dup2(savedStdout, STDOUT_FILENO), 0)

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
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
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
        XCTAssertNotEqual(Darwin.kill(childPID, 0), 0)
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
