//
//  HookRunnerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct HookRunnerTests {
    private static let context = HookRunner.Context(
        phase: .pre,
        scope: .profile,
        profileID: UUID(),
        profileName: "Work",
        previousProfileID: nil,
        previousProfileName: nil
    )

    /// Writes an executable shell script to a fresh temporary file.
    private func script(_ body: String, executable: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-hook-\(UUID().uuidString).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o755 : 0o644],
            ofItemAtPath: url.path
        )
        return url
    }

    @Test
    func `a script that finishes in time reports its output and the profile it ran for`() async throws {
        let url = try script("echo \"$THAW_PROFILE_NAME $THAW_HOOK_PHASE\"")
        defer { try? FileManager.default.removeItem(at: url) }

        let outcome = try await HookRunner.run(HookScript(path: url.path), context: Self.context)

        #expect(outcome.exitStatus == 0)
        #expect(outcome.stdout == "Work Pre")
    }

    @Test
    func `a script that outlives its timeout is reported as timed out, not as failed to run`() async throws {
        let url = try script("sleep 30")
        defer { try? FileManager.default.removeItem(at: url) }
        let started = ContinuousClock.now

        do {
            _ = try await HookRunner.run(HookScript(path: url.path, timeoutSeconds: 1), context: Self.context)
            Issue.record("The script should have timed out")
        } catch let HookRunner.HookError.timedOut(after: seconds) {
            #expect(seconds == 1)
        }
        #expect(ContinuousClock.now - started < .seconds(10), "The child must be stopped, not waited for")
    }

    @Test
    func `a script that exits with an error reports its status`() async throws {
        let url = try script("exit 3")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await HookRunner.run(HookScript(path: url.path), context: Self.context)
            Issue.record("The script should have failed")
        } catch let HookRunner.HookError.nonZeroExit(status) {
            #expect(status == 3)
        }
    }

    @Test
    func `a missing file and a file that cannot be run are told apart`() async throws {
        await #expect(throws: HookRunner.HookError.self) {
            _ = try await HookRunner.run(HookScript(path: "/nonexistent/thaw-hook.sh"), context: Self.context)
        }
        let url = try script("echo hi", executable: false)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await HookRunner.run(HookScript(path: url.path), context: Self.context)
            Issue.record("A file without the executable bit should be refused")
        } catch let HookRunner.HookError.notExecutable(path: path) {
            #expect(path == url.path)
        }
    }

    @Test
    func `cancelling the caller is reported as cancellation`() async throws {
        let url = try script("sleep 30")
        defer { try? FileManager.default.removeItem(at: url) }
        let path = url.path
        let context = Self.context

        let task = Task {
            try await HookRunner.run(HookScript(path: path, timeoutSeconds: 20), context: context)
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
