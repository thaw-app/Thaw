//
//  HookRunnerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `HookRunner`, which launches user-supplied profile-apply scripts.
///
/// Every case here runs a real subprocess against a script written into a
/// per-test temporary directory. That is deliberate: the interesting
/// behavior — the executable-bit check, the osascript routing, the context
/// environment, the timeout race — only exists at the process boundary, and
/// a fake would assert nothing about it. `osascriptPath` is injected so the
/// AppleScript route can be exercised without depending on a real
/// interpreter or on `.scpt` compilation.
@MainActor
@Suite("Profile-apply hook execution")
final class HookRunnerTests {
    private let tempDirectory: URL

    init() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HookRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Helpers

    /// Writes `body` into the temp directory, optionally marking it
    /// executable, and returns its path.
    @discardableResult
    private func writeScript(
        _ body: String,
        named name: String = "hook.sh",
        executable: Bool = true
    ) throws -> String {
        let url = tempDirectory.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }
        return url.path
    }

    private func context(
        phase: HookPhase = .pre,
        scope: HookScope = .profile,
        profileID: UUID = UUID(),
        profileName: String = "Work",
        previousProfileID: UUID? = nil,
        previousProfileName: String? = nil
    ) -> HookRunner.Context {
        HookRunner.Context(
            phase: phase,
            scope: scope,
            profileID: profileID,
            profileName: profileName,
            previousProfileID: previousProfileID,
            previousProfileName: previousProfileName
        )
    }

    /// Runs `hook`, expecting it to fail, and returns the `HookError` it
    /// threw. Records an issue and returns `nil` on any other outcome, so
    /// callers can pattern-match the associated values (`HookError` is not
    /// `Equatable`, so `#expect(throws:)` cannot check them).
    private func hookError(
        from hook: HookScript,
        osascriptPath: String = HookRunner.defaultOSAScriptPath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> HookRunner.HookError? {
        do {
            let outcome = try await HookRunner.run(
                hook,
                context: context(),
                osascriptPath: osascriptPath
            )
            Issue.record(
                "expected the hook to fail, but it exited \(outcome.exitStatus)",
                sourceLocation: sourceLocation
            )
            return nil
        } catch let error as HookRunner.HookError {
            return error
        } catch {
            Issue.record("expected a HookError, got \(error)", sourceLocation: sourceLocation)
            return nil
        }
    }

    // MARK: - Preflight

    @Test("A missing file is rejected before launch")
    func missingFileIsRejected() async {
        let path = tempDirectory.appendingPathComponent("does-not-exist.sh").path

        guard case let .fileMissing(reported)? = await hookError(from: HookScript(path: path)) else {
            Issue.record("expected fileMissing")
            return
        }
        #expect(reported == path)
    }

    @Test("A file without the executable bit is rejected")
    func nonExecutableFileIsRejected() async throws {
        // The user picked a script but never ran chmod +x. Launching it
        // would fail deep inside Subprocess with a far less actionable
        // message, so it is caught here instead.
        let path = try writeScript("#!/bin/sh\nexit 0\n", executable: false)

        guard case let .notExecutable(reported)? = await hookError(from: HookScript(path: path)) else {
            Issue.record("expected notExecutable")
            return
        }
        #expect(reported == path)
    }

    // MARK: - Successful runs

    @Test("stdout and stderr are captured and trimmed")
    func outputIsCapturedAndTrimmed() async throws {
        let path = try writeScript(
            """
            #!/bin/sh
            echo "  hello  "
            echo "  problem  " >&2
            exit 0
            """
        )

        let outcome = try await HookRunner.run(HookScript(path: path), context: context())

        #expect(outcome.exitStatus == 0)
        #expect(outcome.stdout == "hello")
        #expect(outcome.stderr == "problem")
    }

    @Test("The context reaches the hook as environment variables")
    func contextIsPassedAsEnvironment() async throws {
        let path = try writeScript(
            """
            #!/bin/sh
            echo "$THAW_HOOK_PHASE|$THAW_HOOK_SCOPE|$THAW_PROFILE_ID|$THAW_PROFILE_NAME|$THAW_PREVIOUS_PROFILE_ID|$THAW_PREVIOUS_PROFILE_NAME"
            """
        )
        let profileID = UUID()
        let previousID = UUID()

        let outcome = try await HookRunner.run(
            HookScript(path: path),
            context: context(
                phase: .post,
                scope: .global,
                profileID: profileID,
                profileName: "Presenting",
                previousProfileID: previousID,
                previousProfileName: "Work"
            )
        )

        #expect(outcome.stdout == [
            "Post",
            "Global",
            profileID.uuidString,
            "Presenting",
            previousID.uuidString,
            "Work",
        ].joined(separator: "|"))
    }

    @Test("An absent previous profile is passed as an empty string")
    func absentPreviousProfileIsEmpty() async throws {
        // The first apply after launch has no previous profile. The
        // variables still have to be defined, or the hook sees whatever
        // the inherited environment happened to hold.
        let path = try writeScript(
            """
            #!/bin/sh
            echo "[$THAW_PREVIOUS_PROFILE_ID][$THAW_PREVIOUS_PROFILE_NAME]"
            """
        )

        let outcome = try await HookRunner.run(HookScript(path: path), context: context())

        #expect(outcome.stdout == "[][]")
    }

    // MARK: - AppleScript routing

    @Test("AppleScript files are routed through osascript")
    func appleScriptIsRoutedThroughOSAScript() async throws {
        // A .scpt file is read by osascript, so it needs read but not
        // execute permission — the executable-bit check must not apply.
        let scriptPath = try writeScript(
            "-- not really compiled AppleScript\n",
            named: "hook.scpt",
            executable: false
        )
        let fakeOSAScript = try writeScript(
            """
            #!/bin/sh
            echo "interpreted:$1"
            """,
            named: "fake-osascript"
        )

        let outcome = try await HookRunner.run(
            HookScript(path: scriptPath),
            context: context(),
            osascriptPath: fakeOSAScript
        )

        #expect(outcome.stdout == "interpreted:\(scriptPath)")
    }

    @Test("AppleScript routing ignores extension case")
    func appleScriptRoutingIsCaseInsensitive() async throws {
        let scriptPath = try writeScript("-- script\n", named: "hook.APPLESCRIPT", executable: false)
        let fakeOSAScript = try writeScript("#!/bin/sh\necho routed\n", named: "fake-osascript")

        let outcome = try await HookRunner.run(
            HookScript(path: scriptPath),
            context: context(),
            osascriptPath: fakeOSAScript
        )

        #expect(outcome.stdout == "routed")
    }

    // MARK: - Failure modes

    @Test("A non-zero exit is reported with its status")
    func nonZeroExitCarriesItsStatus() async throws {
        let path = try writeScript("#!/bin/sh\nexit 3\n")

        guard case let .nonZeroExit(status)? = await hookError(from: HookScript(path: path)) else {
            Issue.record("expected nonZeroExit")
            return
        }
        #expect(status == 3)
    }

    @Test("A hook killed by a signal is a failure")
    func signalledHookIsAFailure() async throws {
        // Termination by signal is reported through a different branch of
        // `terminationStatus` than a plain exit code, and must not be read
        // as success.
        let path = try writeScript("#!/bin/sh\nkill -TERM $$\n")

        guard case .nonZeroExit? = await hookError(from: HookScript(path: path)) else {
            Issue.record("expected nonZeroExit")
            return
        }
    }

    @Test("A hook that outlives its timeout is reported as timed out")
    func timedOutHookIsReported() async throws {
        // The configured 0.1s is below the clamp floor, so the effective
        // budget is 1s. `exec` replaces the shell with sleep, so the
        // teardown signal reaches the sleeping process directly.
        let path = try writeScript("#!/bin/sh\nexec sleep 30\n")
        let hook = HookScript(path: path, timeoutSeconds: 0.1)

        guard case let .timedOut(after)? = await hookError(from: hook) else {
            Issue.record("expected timedOut")
            return
        }
        #expect(after == 1.0)
    }

    @Test("The timeout bounds the caller's wall-clock time", .timeLimit(.minutes(1)))
    func timeoutBoundsTheCallersWallClockTime() async throws {
        // The regression this guards: `sh` does not forward the teardown
        // signal to its own child and then waits for that child, so the
        // signal cannot end the hook. `run` used to stay blocked for the
        // child's full lifetime — 30s against a 1s budget — because the
        // subprocess was a structured child of the race and the group could
        // not return until it finished. It is now an independent task that
        // gets abandoned at the budget, so the caller returns on time while
        // the orphan finishes on its own.
        let path = try writeScript("#!/bin/sh\nsleep 30\n")
        let hook = HookScript(path: path, timeoutSeconds: 0.1)

        let start = ContinuousClock.now
        guard case let .timedOut(after)? = await hookError(from: hook) else {
            Issue.record("expected timedOut")
            return
        }
        let elapsed = ContinuousClock.now - start

        #expect(after == 1.0)
        #expect(
            elapsed < .seconds(5),
            "the caller must return at its budget rather than waiting out the hook's child"
        )
    }

    @Test("A slow hook does not stall the apply pipeline", .timeLimit(.minutes(1)))
    func runIfEnabledReturnsAtTheBudget() async throws {
        // Why the above matters: runIfEnabled is awaited inside the
        // profile-apply path, so a hook that shells out to anything slow
        // used to hold the whole apply for the child's lifetime.
        let hook = HookScript(path: try writeScript("#!/bin/sh\nsleep 30\n"), timeoutSeconds: 0.1)

        let start = ContinuousClock.now
        await HookRunner.runIfEnabled(hook, context: context())
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < .seconds(5))
    }

    @Test("A launch failure is reported as runFailed")
    func unlaunchableExecutableIsRunFailed() async throws {
        // Executable bit set, but there is no interpreter for it, so the
        // failure surfaces from the launch itself rather than preflight.
        let path = try writeScript("#!/nonexistent/interpreter\nnoop\n")

        guard case let .runFailed(reported, _)? = await hookError(from: HookScript(path: path)) else {
            Issue.record("expected runFailed")
            return
        }
        #expect(reported == path)
    }

    // MARK: - Error descriptions

    @Test("Error descriptions name the path or status")
    func errorDescriptionsAreActionable() {
        #expect(
            HookRunner.HookError.fileMissing(path: "/tmp/a.sh").description
                == "hook file missing: /tmp/a.sh"
        )
        #expect(
            HookRunner.HookError.notExecutable(path: "/tmp/a.sh").description
                == "hook file not executable (run chmod +x): /tmp/a.sh"
        )
        #expect(
            HookRunner.HookError.timedOut(after: 5).description == "hook timed out after 5.0s"
        )
        #expect(
            HookRunner.HookError.nonZeroExit(3).description == "hook exited with status 3"
        )
        #expect(
            HookRunner.HookError
                .runFailed(path: "/tmp/a.sh", error: HookRunner.HookError.nonZeroExit(1))
                .description
                .hasPrefix("hook failed to run for /tmp/a.sh: ")
        )
    }

    // MARK: - runIfEnabled

    /// Path a hook can create to prove it actually ran.
    private var markerPath: String {
        tempDirectory.appendingPathComponent("marker").path
    }

    private var markerExists: Bool {
        FileManager.default.fileExists(atPath: markerPath)
    }

    private func markerScript() throws -> String {
        try writeScript("#!/bin/sh\ntouch \"\(markerPath)\"\n")
    }

    @Test("No hook means nothing runs")
    func runIfEnabledIgnoresNilHook() async {
        await HookRunner.runIfEnabled(nil, context: context())

        #expect(!markerExists)
    }

    @Test("A disabled hook is skipped without losing its path")
    func runIfEnabledSkipsDisabledHook() async throws {
        // A parked hook keeps its path so the user does not have to
        // re-pick the file, but it must not run.
        let path = try markerScript()
        let hook = HookScript(path: path, isEnabled: false)

        await HookRunner.runIfEnabled(hook, context: context())

        #expect(!markerExists)
        #expect(hook.path == path)
    }

    @Test("An enabled hook runs")
    func runIfEnabledRunsEnabledHook() async throws {
        let hook = try HookScript(path: markerScript())

        await HookRunner.runIfEnabled(hook, context: context())

        #expect(markerExists)
    }

    @Test("A failing hook does not propagate out of runIfEnabled")
    func runIfEnabledSwallowsFailures() async throws {
        // The whole point of the wrapper: a broken hook is logged, not
        // propagated into the profile-apply path.
        let missing = HookScript(path: tempDirectory.appendingPathComponent("gone.sh").path)
        await HookRunner.runIfEnabled(missing, context: context())

        let failing = try HookScript(path: writeScript("#!/bin/sh\nexit 9\n", named: "fail.sh"))
        await HookRunner.runIfEnabled(failing, context: context(phase: .post, scope: .global))

        // Reaching here without throwing is the assertion; the marker
        // confirms neither run had side effects of its own.
        #expect(!markerExists)
    }

    @Test("Output from a successful hook is logged")
    func runIfEnabledLogsOutput() async throws {
        // Exercises the stdout/stderr logging branches, which only run
        // when the streams are non-empty.
        let hook = try HookScript(
            path: writeScript("#!/bin/sh\necho out\necho err >&2\ntouch \"\(markerPath)\"\n")
        )

        await HookRunner.runIfEnabled(hook, context: context())

        #expect(markerExists)
    }
}
