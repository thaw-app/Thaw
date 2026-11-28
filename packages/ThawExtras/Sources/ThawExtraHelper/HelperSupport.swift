//
//  HelperSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Objects whose menu items call back into them.
@MainActor
protocol MenuActionTarget: AnyObject {}

extension MenuActionTarget {
    func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

extension NSMenuItem {
    /// A line the menu shows dimmed, with nothing to click.
    static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

enum SystemSettings {
    /// Opens the System Settings pane with this extension identifier.
    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

nonisolated enum CommandOutput {
    /// The command's standard output, or "" when it can't start or is ended for running past timeout.
    /// A command that ignores SIGTERM is killed a second later. Output that a child of the command still
    /// holds open at the timeout reads as "" too.
    static func output(of executable: URL, arguments: [String], timeout: Duration) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let (seconds, attoseconds) = timeout.components
                let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
                let deadline = DispatchTime.now() + .nanoseconds(nanoseconds)
                let output = ReadOutput()
                DispatchQueue.global(qos: .utility).async {
                    output.data = pipe.fileHandleForReading.readDataToEndOfFile()
                    output.done.signal()
                }
                let stop = DispatchWorkItem { end(process) }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline, execute: stop)
                process.waitUntilExit()
                stop.cancel()
                guard process.terminationReason == .exit, output.done.wait(timeout: deadline) == .success else {
                    continuation.resume(returning: "")
                    return
                }
                continuation.resume(returning: String(bytes: output.data, encoding: .utf8) ?? "")
            }
        }
    }

    private static func end(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(1)) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// Written once by the reader before `done` is signaled.
    private final class ReadOutput: @unchecked Sendable {
        var data = Data()
        let done = DispatchSemaphore(value: 0)
    }
}
