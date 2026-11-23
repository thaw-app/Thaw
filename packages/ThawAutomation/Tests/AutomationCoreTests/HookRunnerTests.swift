//
//  HookRunnerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import AutomationCore
import Foundation
import Testing
import ThawModuleKit

@Suite("Hook runner")
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

    /// Long enough that a busy CI runner can't time out a script that returns at once.
    /// The default five seconds once ran out before an echo did.
    private static let roomyTimeout: Double = 60

    @Test("A script that finishes in time reports its output and the profile it ran for")
    func finishesInTime() async throws {
        let url = try script("echo \"$THAW_PROFILE_NAME $THAW_HOOK_PHASE\"")
        defer { try? FileManager.default.removeItem(at: url) }

        let outcome = try await HookRunner.run(HookScript(path: url.path, timeoutSeconds: Self.roomyTimeout), context: Self.context)

        #expect(outcome.exitStatus == 0)
        #expect(outcome.stdout == "Work Pre")
    }

    /// A fresh temporary path for a script to write to.
    private func scratchPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("thaw-hook-\(name)-\(UUID().uuidString)").path
    }

    /// The hook's timeout is the OS stopping a real child, so it keeps real time. The script sleeps far past
    /// the test's time limit, so a child that were waited for instead of stopped fails the test.
    @Test(.timeLimit(.minutes(5)))
    func `a script that outlives its timeout is reported as timed out, not as failed to run`() async throws {
        let pidFile = scratchPath("pid")
        let url = try script("echo $$ > '\(pidFile)'\nexec sleep 900")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: pidFile)
        }

        do {
            _ = try await HookRunner.run(HookScript(path: url.path, timeoutSeconds: 1), context: Self.context)
            Issue.record("The script should have timed out")
        } catch let HookRunner.HookError.timedOut(after: seconds) {
            #expect(seconds == 1)
        }
        // Under load the child can be stopped before its shell writes the pid; the timeout is what this checks.
        guard let written = try? String(contentsOfFile: pidFile, encoding: .utf8) else { return }
        let pid = try #require(pid_t(written.trimmingCharacters(in: .whitespacesAndNewlines)))
        let isGone = kill(pid, 0) == -1 && errno == ESRCH
        #expect(isGone, "The child must be stopped, not waited for")
    }

    @Test("A script that exits with an error reports its status")
    func reportsExitStatus() async throws {
        let url = try script("exit 3")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await HookRunner.run(HookScript(path: url.path, timeoutSeconds: Self.roomyTimeout), context: Self.context)
            Issue.record("The script should have failed")
        } catch let HookRunner.HookError.nonZeroExit(status) {
            #expect(status == 3)
        }
    }

    @Test("A missing file and a file that cannot be run are told apart")
    func missingAndNotExecutable() async throws {
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

    @Test(.timeLimit(.minutes(1)))
    func `cancelling the caller is reported as cancellation`() async throws {
        let fifo = scratchPath("started")
        try #require(mkfifo(fifo, 0o600) == 0)
        let url = try script("echo started > '\(fifo)'\nexec sleep 30")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: fifo)
        }
        let path = url.path
        let context = Self.context

        let task = Task {
            try await HookRunner.run(HookScript(path: path, timeoutSeconds: 20), context: context)
        }
        // Opening the pipe blocks until the script writes to it, so the caller is cancelled while the hook runs.
        await withCheckedContinuation { (running: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                _ = FileHandle(forReadingAtPath: fifo)?.readDataToEndOfFile()
                running.resume()
            }
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}

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
