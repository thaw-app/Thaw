//
//  MaintenanceTools+Commands.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What the maintenance tools run and how a failure reads, apart from running them.
nonisolated extension MaintenanceTools {
    nonisolated enum ToolError: LocalizedError {
        case commandFailed(String, Int32, String)

        var errorDescription: String? {
            switch self {
            case let .commandFailed(command, status, detail):
                let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return String(localized: "\(command) failed with exit status \(status).")
                }
                return String(localized: "\(command) failed with exit status \(status): \(trimmed)")
            }
        }
    }

    /// The tccutil arguments that reset Thaw's Accessibility and Screen Recording decisions.
    static func permissionResetArguments(bundleID: String) -> [[String]] {
        [["reset", "Accessibility", bundleID], ["reset", "ScreenCapture", bundleID]]
    }

    /// The files the user picked in an open panel to give Thaw access: the
    /// menu bar layout table and Control Center's app list.
    static let pickedFileBookmarkKeys = [
        Defaults.Key.menuBarLayoutTableBookmark.rawValue,
        "NativeAppHidingAppListBookmark",
        "NativeVisibilityRecoveryFileBookmark",
    ]

    /// Forgets every picked-file grant, so each file has to be picked again.
    static func removePickedFileGrants(from defaults: UserDefaults) {
        for key in pickedFileBookmarkKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
