//
//  ConflictingAppDetector.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Detects other running menu bar management apps that may conflict with Thaw.
enum ConflictingAppDetector {
    private static let knownConflictingApps: [String: String] = [
        "com.jordanbaird.Ice": "Ice",
        "com.surteesstudios.Bartender": "Bartender",
        "com.dwarvesv.minimalbar": "Hidden Bar",
        "com.macpaw.CleanMyMac-setapp": "CleanMyMac Menu",
        "com.gaosun.BarTender": "iBar",
        "com.HyperartFlow.Barbee": "Barbee",
        "com.sanebar.app": "SaneBar",
        "com.mrmango1.Glow": "Glow",
    ]

    /// Returns display names rather than bundle IDs for the conflict warning.
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

    /// Returns true with no conflicts or if the user continues; choosing Quit requests termination.
    @MainActor
    @discardableResult
    static func showWarningIfNeeded() -> Bool {
        let conflicts = detectConflictingApps()
        guard !conflicts.isEmpty else { return true }

        let appList = conflicts.formatted(.list(type: .and))
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "Conflicting Menu Bar Manager Detected"
        )
        alert.informativeText = String(
            localized: """
            \(appList) is currently running. Running multiple menu bar \
            managers at the same time can cause display issues and unexpected \
            behavior. Consider quitting \(appList) before using \(Constants.displayName).
            """
        )
        alert.addButton(withTitle: String(localized: "Continue Anyway"))
        alert.addButton(withTitle: String(localized: "Quit \(Constants.displayName)"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            ApplicationTermination.request()
            return false
        }
        return true
    }
}
