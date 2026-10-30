//
//  HookRunnerRoutingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Which hooks run and through what, with scripts that only write inside their own temporary folder.
@MainActor
@Suite("Hook runner routing")
struct HookRunnerRoutingTests {
    private static let context = HookRunner.Context(
        phase: .post,
        scope: .profile,
        profileID: UUID(),
        profileName: "Home",
        previousProfileID: nil,
        previousProfileName: nil
    )

    /// Long enough that a busy runner can't time out a script that returns at once.
    private static let roomyTimeout: Double = 60

    /// Runs body with a fresh temporary folder, removed afterwards.
    private func withFolder(_ body: (URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("thaw-hook-routing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await body(folder)
    }

    private func write(_ contents: String, to url: URL, executable: Bool) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }

    @Test("AppleScript files go to the interpreter with their path, and need no executable bit", arguments: ["scpt", "applescript", "SCPTD"])
    func appleScriptGoesThroughTheInterpreter(fileExtension: String) async throws {
        try await withFolder { folder in
            let interpreter = folder.appendingPathComponent("osascript")
            let marker = folder.appendingPathComponent("argument")
            try write("#!/bin/sh\nprintf '%s' \"$1\" > '\(marker.path)'\necho ran\n", to: interpreter, executable: true)
            let script = folder.appendingPathComponent("hook.\(fileExtension)")
            try write("display dialog \"never shown\"", to: script, executable: false)

            let outcome = try await HookRunner.run(
                HookScript(path: script.path, timeoutSeconds: Self.roomyTimeout),
                context: Self.context,
                osascriptPath: interpreter.path
            )

            #expect(outcome.stdout == "ran")
            #expect(try String(contentsOf: marker, encoding: .utf8) == script.path)
        }
    }

    @Test("An executable that can't be launched is reported as failing to run")
    func unlaunchableExecutableFailsToRun() async throws {
        try await withFolder { folder in
            let script = folder.appendingPathComponent("garbage")
            try write("no interpreter line, not a binary", to: script, executable: true)

            do {
                _ = try await HookRunner.run(HookScript(path: script.path, timeoutSeconds: Self.roomyTimeout), context: Self.context)
                Issue.record("The file should not have launched")
            } catch let HookRunner.HookError.runFailed(path, _) {
                #expect(path == script.path)
            }
        }
    }

    @Test("A disabled hook does not run")
    func disabledHookIsSkipped() async throws {
        try await withFolder { folder in
            let marker = folder.appendingPathComponent("ran")
            let script = folder.appendingPathComponent("hook.sh")
            try write("#!/bin/sh\ntouch '\(marker.path)'\n", to: script, executable: true)

            await HookRunner.runIfEnabled(
                HookScript(path: script.path, timeoutSeconds: Self.roomyTimeout, isEnabled: false),
                context: Self.context
            )
            await HookRunner.runIfEnabled(nil, context: Self.context)

            #expect(!FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test("An enabled hook runs with the profile in its environment")
    func enabledHookRuns() async throws {
        try await withFolder { folder in
            let marker = folder.appendingPathComponent("ran")
            let script = folder.appendingPathComponent("hook.sh")
            try write(
                "#!/bin/sh\nprintf '%s %s' \"$THAW_PROFILE_NAME\" \"$THAW_HOOK_PHASE\" > '\(marker.path)'\necho out\necho err >&2\n",
                to: script,
                executable: true
            )

            await HookRunner.runIfEnabled(HookScript(path: script.path, timeoutSeconds: Self.roomyTimeout), context: Self.context)

            #expect(try String(contentsOf: marker, encoding: .utf8) == "Home Post")
        }
    }
}
