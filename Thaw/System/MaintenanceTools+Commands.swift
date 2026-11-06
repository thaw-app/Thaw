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
}
