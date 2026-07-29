//
//  HookRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

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

    enum HookError: Error, CustomStringConvertible {
        case fileMissing(path: String)
        case notExecutable(path: String)
        case launchFailed(path: String, error: Error)
        case timedOut(after: Double)
        case nonZeroExit(Int32)

        var description: String {
            switch self {
            case let .fileMissing(p): return "hook file missing: \(p)"
            case let .notExecutable(p): return "hook file not executable (run chmod +x): \(p)"
            case let .launchFailed(p, e): return "hook launch failed for \(p): \(e)"
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

        let process = Process()
        if useOSAScript {
            process.executableURL = URL(fileURLWithPath: osascriptPath)
            process.arguments = [url.path]
        } else {
            process.executableURL = url
            process.arguments = []
        }

        // Merge our env vars on top of the process's inherited environment.
        var env = ProcessInfo.processInfo.environment
        env["THAW_HOOK_PHASE"] = context.phase.rawValue.capitalized
        env["THAW_HOOK_SCOPE"] = context.scope.rawValue.capitalized
        env["THAW_PROFILE_ID"] = context.profileID.uuidString
        env["THAW_PROFILE_NAME"] = context.profileName
        env["THAW_PREVIOUS_PROFILE_ID"] = context.previousProfileID?.uuidString ?? ""
        env["THAW_PREVIOUS_PROFILE_NAME"] = context.previousProfileName ?? ""
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let clamped = max(1.0, min(hook.timeoutSeconds, 300.0))

        do {
            try process.run()
        } catch {
            throw HookError.launchFailed(path: hook.path, error: error)
        }

        // Race process termination against a sleep timeout. Whichever wins
        // tears down the other. The whole race is wrapped in a
        // withTaskCancellationHandler so external cancellation (typically
        // a newer profile apply replacing the layoutTask) also reaps the
        // subprocess instead of leaving it running orphaned. The task
        // group is factored into raceProcessAgainstTimeout so the
        // closure nesting at this call site stays within two levels.
        let exitStatus: Int32
        do {
            exitStatus = try await withTaskCancellationHandler {
                try await raceProcessAgainstTimeout(process: process, timeout: clamped)
            } onCancel: {
                // Synchronous: send SIGTERM so the polling task in the
                // helper sees isRunning flip immediately and the group
                // can unwind without waiting out the remainder of the
                // timeout. Child tasks observe cancellation through the
                // parent's propagated state, so an explicit
                // group.cancelAll here is unnecessary. The matching
                // async wait and SIGINT escalation run in the catch
                // branch below, mirroring the timeout cleanup sequence
                // inside the helper.
                process.terminate()
            }
        } catch is CancellationError {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning {
                process.interrupt()
            }
            throw CancellationError()
        }

        let stdout = readAvailable(stdoutPipe)
        let stderr = readAvailable(stderrPipe)

        if exitStatus != 0 {
            throw HookError.nonZeroExit(exitStatus)
        }
        return RunOutcome(exitStatus: exitStatus, stdout: stdout, stderr: stderr)
    }

    private static func readAvailable(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return "" }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Awaits whichever wins first: the process exiting, or the timeout
    /// elapsing. On exit, returns the terminationStatus. On timeout,
    /// sends SIGTERM, waits a second, escalates to SIGINT if needed, and
    /// throws HookError.timedOut.
    private static func raceProcessAgainstTimeout(
        process: Process,
        timeout: Double
    ) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32?.self) { group in
            group.addTask { try await pollProcessExit(process) }
            group.addTask { try await timeoutTick(seconds: timeout) }

            guard let first = try await group.next() else {
                group.cancelAll()
                return -1
            }
            group.cancelAll()

            if let status = first {
                return status
            }

            // Timeout fired before the process exited.
            process.terminate()
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning {
                process.interrupt()
            }
            throw HookError.timedOut(after: timeout)
        }
    }

    /// Polls isRunning instead of registering a terminationHandler after
    /// process.run(). Foundation only invokes the handler on the
    /// running-to-exited transition, so a hook that exits in the window
    /// between process.run() returning and the handler being assigned
    /// would never fire it; the continuation would dangle and the
    /// timeout would race in as a false positive. Polling reads live
    /// state, so a process that already terminated returns its status
    /// on the first probe.
    private static func pollProcessExit(_ process: Process) async throws -> Int32 {
        while process.isRunning {
            try await Task.sleep(for: .milliseconds(50))
        }
        return process.terminationStatus
    }

    /// Sleeps for the given duration then returns nil to signal "timeout
    /// won the race" inside the task group.
    private static func timeoutTick(seconds: Double) async throws -> Int32? {
        try await Task.sleep(for: .seconds(seconds))
        return nil
    }
}
