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

    /// Path used for the AppleScript runner.
    private static let osascriptPath = "/usr/bin/osascript"

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
            case .fileMissing(let p): return "hook file missing: \(p)"
            case .notExecutable(let p): return "hook file not executable (run chmod +x): \(p)"
            case .launchFailed(let p, let e): return "hook launch failed for \(p): \(e)"
            case .timedOut(let s): return "hook timed out after \(s)s"
            case .nonZeroExit(let s): return "hook exited with status \(s)"
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
    static func runIfEnabled(_ hook: HookScript?, context: Context) async {
        guard let hook else { return }
        guard hook.isEnabled else {
            diagLog.debug("\(context.scope.rawValue) \(context.phase.rawValue)-hook disabled, skipping: \(hook.path)")
            return
        }
        do {
            let outcome = try await run(hook, context: context)
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
    static func run(_ hook: HookScript, context: Context) async throws -> RunOutcome {
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
        // tears down the other.
        let exitStatus: Int32 = try await withThrowingTaskGroup(of: Int32?.self) { group in
            group.addTask {
                // Wait for the process to exit.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in continuation.resume() }
                }
                return process.terminationStatus
            }
            group.addTask {
                try await Task.sleep(for: .seconds(clamped))
                return nil
            }

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
            throw HookError.timedOut(after: clamped)
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
}
