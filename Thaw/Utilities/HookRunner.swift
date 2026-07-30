//
//  HookRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Subprocess
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

        // The subprocess races a sleeping arm that throws at the budget, and
        // whichever finishes first wins. This can be structured now: leaving
        // the group cancels the subprocess, and cancellation tears down the
        // hook's process group, so the child the group waits for is one that
        // has just been killed rather than one running on its own schedule.
        let result: ExecutionResult<Void, StringOutput<UTF8>, StringOutput<UTF8>>
        do {
            result = try await withThrowingTaskGroup(
                of: ExecutionResult<Void, StringOutput<UTF8>, StringOutput<UTF8>>.self
            ) { group in
                group.addTask {
                    try await Subprocess.run(
                        .path(executablePath),
                        arguments: Arguments(arguments),
                        environment: environment,
                        platformOptions: platformOptions,
                        output: .string(limit: outputByteLimit),
                        error: .string(limit: outputByteLimit)
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(clamped))
                    throw HookError.timedOut(after: clamped)
                }
                defer { group.cancelAll() }
                // Both arms are always added, so there is a first result to
                // take; an empty group would mean the caller went away.
                guard let first = try await group.next() else {
                    throw CancellationError()
                }
                return first
            }
        } catch let error as HookError {
            if case .timedOut = error {
                diagLog.warning("hook exceeded its \(clamped)s budget; terminating it: \(hook.path)")
            }
            throw error
        } catch is CancellationError {
            // The caller went away rather than the hook overrunning.
            throw CancellationError()
        } catch {
            throw HookError.runFailed(path: hook.path, error: error)
        }

        let stdout = (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = (result.standardError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
