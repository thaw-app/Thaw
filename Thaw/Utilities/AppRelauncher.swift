//
//  AppRelauncher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Quits Thaw and opens it again.
@MainActor
enum AppRelauncher {
    /// A detached shell waits for this PID to exit before reopening, since an
    /// overlapping launch can leave two copies. Foundation Process because
    /// Subprocess ties the child to a task that dies with the app.
    ///
    /// Throws and keeps the app running if the watcher cannot start.
    static func relaunch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = watcherArguments(
            pid: ProcessInfo.processInfo.processIdentifier,
            bundlePath: Bundle.main.bundlePath
        )
        try process.run()
        NSApp.terminate(nil)
    }

    /// The shell program is fixed and reads the PID and bundle path as positional
    /// parameters, so a path holding quotes or $() is never parsed as shell code.
    static nonisolated func watcherArguments(pid: pid_t, bundlePath: String) -> [String] {
        [
            "-c",
            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$2\"",
            "sh",
            String(pid),
            bundlePath,
        ]
    }
}
