//
//  TriggerScriptRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Runs a user-supplied script for a script-result trigger condition and
/// returns its exit code and combined output, with a wall-clock timeout.
///
/// AppleScript files (.scpt / .applescript / .scptd) are routed through
/// `osascript`; everything else is launched directly and must carry the
/// executable bit.
enum TriggerScriptRunner {
    private static let diagLog = DiagLog(category: "TriggerScriptRunner")

    private static let appleScriptExtensions: Set<String> = ["scpt", "applescript", "scptd"]

    /// Runs the script at `path`, returning its outcome, or `nil` on launch
    /// failure. Times out after `timeout` seconds (the process is terminated
    /// and a non-zero exit code is reported).
    static func run(path: String, timeout: Double = 10) async -> ScriptOutcome? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let ext = (trimmed as NSString).pathExtension.lowercased()
        if appleScriptExtensions.contains(ext) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [trimmed]
        } else {
            process.executableURL = URL(fileURLWithPath: trimmed)
        }

        do {
            try process.run()
        } catch {
            diagLog.warning("Failed to launch trigger script \(trimmed): \(error.localizedDescription)")
            return nil
        }

        // Race the process against the timeout.
        let timedOut = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                while process.isRunning {
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return false }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return true
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if timedOut, process.isRunning {
            process.terminate()
            diagLog.warning("Trigger script timed out after \(timeout)s: \(trimmed)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        let exitCode = timedOut ? -1 : process.terminationStatus
        return ScriptOutcome(exitCode: exitCode, output: output)
    }
}
