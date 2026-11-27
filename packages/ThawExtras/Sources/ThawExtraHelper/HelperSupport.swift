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
                let deadline = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                let (seconds, attoseconds) = timeout.components
                let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(nanoseconds), execute: deadline)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                deadline.cancel()
                guard process.terminationReason == .exit else {
                    continuation.resume(returning: "")
                    return
                }
                continuation.resume(returning: String(bytes: data, encoding: .utf8) ?? "")
            }
        }
    }
}
