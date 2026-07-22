//
//  HookRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
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

    /// Outcome of racing the subprocess against the timeout.
    private enum RaceOutcome {
        case completed(ExecutionRecord<StringOutput<UTF8>, StringOutput<UTF8>>)
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

        // On timeout or outer-task cancellation, Subprocess runs this
        // teardown sequence against the child before this call returns,
        // so there is no need to poll isRunning or manually escalate
        // signals here.
        let platformOptions: PlatformOptions = {
            var options = PlatformOptions()
            options.teardownSequence = [
                .send(signal: .interrupt, allowedDurationToNextStep: .seconds(1)),
            ]
            return options
        }()

        // Race the subprocess against a timeout task. Whichever finishes
        // first wins; cancelAll() then cancels the other, which for the
        // subprocess task triggers the teardown sequence above.
        let outcome: RaceOutcome
        do {
            outcome = try await withThrowingTaskGroup(of: RaceOutcome.self) { group in
                group.addTask {
                    let result = try await Subprocess.run(
                        .path(executablePath),
                        arguments: Arguments(arguments),
                        environment: environment,
                        platformOptions: platformOptions,
                        output: .string(limit: outputByteLimit),
                        error: .string(limit: outputByteLimit)
                    )
                    return .completed(result)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(clamped))
                    return .timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw CancellationError()
                }
                return first
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HookError.runFailed(path: hook.path, error: error)
        }

        switch outcome {
        case .timedOut:
            throw HookError.timedOut(after: clamped)
        case let .completed(result):
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
}
