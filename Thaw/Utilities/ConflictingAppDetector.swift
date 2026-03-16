//
//  ConflictingAppDetector.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Detects other running menu bar management apps that may conflict with Thaw.
enum ConflictingAppDetector {
    /// Known menu bar management app bundle identifiers and their display names.
    private static let knownConflictingApps: [String: String] = [
        "com.jordanbaird.Ice": "Ice",
        "com.surteesstudios.Bartender": "Bartender",
        "com.dwarvesv.minimalbar": "Hidden Bar",
        "com.macpaw.CleanMyMac-setapp": "CleanMyMac Menu",
        "com.gaosun.BarTender": "iBar",
    ]

    /// Returns the display names of any conflicting menu bar managers currently running.
    @MainActor
    static func detectConflictingApps() -> [String] {
        let runningApps = NSWorkspace.shared.runningApplications
        var conflicts: [String] = []

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if let name = knownConflictingApps[bundleID], !app.isTerminated {
                conflicts.append(name)
            }
        }

        return conflicts
    }

    /// Shows a warning alert listing the conflicting apps. Returns `true` if the user chose to continue.
    @MainActor
    @discardableResult
    static func showWarningIfNeeded() -> Bool {
        let conflicts = detectConflictingApps()
        guard !conflicts.isEmpty else { return true }

        let appList = conflicts.joined(separator: ", ")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "Conflicting Menu Bar Manager Detected"
        )
        alert.informativeText = String(
            localized: """
            \(appList) is currently running. Running multiple menu bar \
            managers at the same time can cause display issues and unexpected \
            behavior. Consider quitting \(appList) before using Thaw.
            """
        )
        alert.addButton(withTitle: String(localized: "Continue Anyway"))
        alert.addButton(withTitle: String(localized: "Quit Thaw"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSApp.terminate(nil)
            return false
        }
        return true
    }
}
