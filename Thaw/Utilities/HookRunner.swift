//
//  HookRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Subprocess
// Prefer the `System` module when available: Subprocess's API surface uses
// `System.FilePath`, so both sides must resolve to the same module or the
// types won't unify.
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Executes user-supplied profile-apply hooks with a wall-clock timeout
/// and pipes their output to DiagLog.
///
/// AppleScript files (.scpt / .applescript / .scptd) are routed through
/// /usr/bin/osascript so the user does not need to chmod +x them. All
/// other paths are launched directly and must carry the executable bit.
enum HookRunner {
    private static let diagLog = DiagLog(category: "HookRunner")

    /// Default path to the AppleScript interpreter on macOS. Overridable
    /// per call via the `osascriptPath` parameter on `run` / `runIfEnabled`
    /// (used in tests; production callers take the default).
    static let defaultOSAScriptPath = "/usr/bin/osascript"

    /// File extensions routed through osascript.
    private static let appleScriptExtensions: Set<String> = [
        "scpt",
        "applescript",
        "scptd",
    ]

    /// Maximum bytes collected from either stream before Subprocess aborts
    /// the run. Generous enough that no reasonable hook trips it.
    private static let outputByteLimit = 1 << 20

    enum HookError: Error, CustomStringConvertible {
        case fileMissing(path: String)
        case notExecutable(path: String)
        case runFailed(path: String, error: Error)
        case timedOut(after: Double)
        case nonZeroExit(Int32)

        var description: String {
            switch self {
            case let .fileMissing(p): return "hook file missing: \(p)"
            case let .notExecutable(p): return "hook file not executable (run chmod +x): \(p)"
            case let .runFailed(p, e): return "hook failed to run for \(p): \(e)"
            case let .timedOut(s): return "hook timed out after \(s)s"
            case let .nonZeroExit(s): return "hook exited with status \(s)"
            }
        }
    }

    /// Result of a successful hook run.
    struct RunOutcome {
        let exitStatus: Int32
        let stdout: String
        let stderr: String
    }

    /// Context passed into the hook as environment variables.
    struct Context {
        let phase: HookPhase
        let scope: HookScope
        let profileID: UUID
        let profileName: String
        let previousProfileID: UUID?
        let previousProfileName: String?
    }

    /// Outcome of racing the subprocess against the timeout.
    private enum RaceOutcome {
        case completed(ExecutionResult<Void, StringOutput<UTF8>, StringOutput<UTF8>>)
        case failed(any Error)
        case timedOut
    }

    /// Non-throwing wrapper. Logs every outcome (success, failure, skip)
    /// and never propagates errors so the apply pipeline keeps moving.
    static func runIfEnabled(
        _ hook: HookScript?,
        context: Context,
        osascriptPath: String = defaultOSAScriptPath
    ) async {
        guard let hook else { return }
        guard hook.isEnabled else {
            diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook disabled, skipping: \(hook.path)")
            return
        }
        do {
            let outcome = try await run(hook, context: context, osascriptPath: osascriptPath)
            diagLog.debug(
                "\(context.scope.rawValue) \(context.phase.rawValue)-hook ok (exit=\(outcome.exitStatus)): \(hook.path)"
            )
            if !outcome.stdout.isEmpty {
                diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook stdout: \(outcome.stdout)")
            }
            if !outcome.stderr.isEmpty {
                diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook stderr: \(outcome.stderr)")
            }
        } catch is CancellationError {
            diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook cancelled: \(hook.path)")
        } catch {
            diagLog.error(
                "\(context.scope.rawValue) \(context.phase.rawValue)-hook failed (\(hook.path)): \(error)"
            )
        }
    }

    /// Throws on failure. Used by the wrapper above; exposed for callers
    /// that want the outcome (none today, but keeps the API honest).
    static func run(
        _ hook: HookScript,
        context: Context,
        osascriptPath: String = defaultOSAScriptPath
    ) async throws -> RunOutcome {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: hook.path)
        guard fm.fileExists(atPath: url.path) else {
            throw HookError.fileMissing(path: hook.path)
        }

        let ext = url.pathExtension.lowercased()
        let useOSAScript = appleScriptExtensions.contains(ext)

        // Verify the executable bit for direct-launch scripts. AppleScript
        // files are read by osascript, so they need read but not execute.
        if !useOSAScript, !fm.isExecutableFile(atPath: url.path) {
            throw HookError.notExecutable(path: hook.path)
        }

        let executablePath: FilePath
        let arguments: [String]
        if useOSAScript {
            executablePath = FilePath(osascriptPath)
            arguments = [url.path]
        } else {
            executablePath = FilePath(url.path)
            arguments = []
        }

        let environment = Environment.inherit.updating([
            "THAW_HOOK_PHASE": context.phase.rawValue.capitalized,
            "THAW_HOOK_SCOPE": context.scope.rawValue.capitalized,
            "THAW_PROFILE_ID": context.profileID.uuidString,
            "THAW_PROFILE_NAME": context.profileName,
            "THAW_PREVIOUS_PROFILE_ID": context.previousProfileID?.uuidString ?? "",
            "THAW_PREVIOUS_PROFILE_NAME": context.previousProfileName ?? "",
        ])

        let clamped = hook.timeoutSeconds.clamped(to: 1.0 ... 300.0)

        // Cancelling the subprocess runs this teardown sequence against the
        // hook's whole process group, which is what bounds the run: a
        // `#!/bin/sh` wrapper does not forward a signal to its own child and
        // then wait for it, so signalling the wrapper alone left the real work
        // running. Targeting the group reaches those descendants, and the
        // implicit final kill that closes every sequence inherits the group
        // from the last explicit step.
        //
        // `createSession` is not optional here. Without it the hook stays in
        // Thaw's own process group, and a group-targeted signal would be
        // delivered to Thaw as well.
        //
        // The signal is SIGTERM rather than SIGINT because a non-interactive
        // `sh` starts background jobs with SIGINT ignored: `sleep 30 &`
        // survived it while `sh` itself died, and Subprocess ends the sequence
        // as soon as the process it launched exits, so the kill that closes
        // the sequence never got the chance to run. A descendant that traps
        // SIGTERM can still outlive the run for the same reason.
        let platformOptions: PlatformOptions = {
            var options = PlatformOptions()
            options.createSession = true
            options.teardownSequence = [
                .send(signal: .terminate, toProcessGroup: true, allowedDurationToNextStep: .seconds(1)),
            ]
            return options
        }()

        // Both arms report into a one-shot channel and the first value wins.
        //
        // The subprocess deliberately runs in an unstructured task: as a
        // structured child of a task group it would have to finish before
        // the group could return, which handed the hook's own child process
        // control over when `run` returns -- a `sleep 30` behind a 1s budget
        // blocked the caller for the full 30s. Awaiting `Task.value` instead
        // does not help either, since that await is not cancellable from the
        // waiting side. The channel is what lets the wait end on time while
        // the process finishes on its own.
        let (outcomes, continuation) = AsyncStream.makeStream(of: RaceOutcome.self)

        let subprocessTask = Task {
            do {
                let result = try await Subprocess.run(
                    .path(executablePath),
                    arguments: Arguments(arguments),
                    environment: environment,
                    platformOptions: platformOptions,
                    output: .string(limit: outputByteLimit),
                    error: .string(limit: outputByteLimit)
                )
                continuation.yield(.completed(result))
            } catch {
                continuation.yield(.failed(error))
            }
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(clamped))
            continuation.yield(.timedOut)
        }
        defer { timeoutTask.cancel() }

        // Yields to a channel nobody is reading are dropped, so whichever
        // arm loses the race simply has no effect.
        var outcome: RaceOutcome?
        for await first in outcomes {
            outcome = first
            break
        }

        switch outcome {
        case .none:
            // Both arms were cancelled, so the caller went away.
            subprocessTask.cancel()
            throw CancellationError()
        case .timedOut:
            // Ask it to stop, but do not wait to find out whether it did.
            // The hook may be a wrapper whose child ignores the signal, or
            // one that deliberately outlives the apply.
            subprocessTask.cancel()
            diagLog.warning(
                "hook exceeded its \(clamped)s budget; abandoning it and continuing: \(hook.path)"
            )
            throw HookError.timedOut(after: clamped)
        case let .failed(error):
            throw HookError.runFailed(path: hook.path, error: error)
        case let .completed(result):
            let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let exitStatus: Int32 = switch result.terminationStatus {
            case let .exited(code): code
            case let .signaled(code): code
            }
            guard result.terminationStatus.isSuccess else {
                throw HookError.nonZeroExit(exitStatus)
            }
            return RunOutcome(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
        }
    }
}
