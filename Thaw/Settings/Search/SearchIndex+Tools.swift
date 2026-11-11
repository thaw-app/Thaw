//
//  SearchIndex+Tools.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Tools

    /// Rows in the Troubleshooting pane, in the pane's own order. Mostly one-shot
    /// maintenance actions with no persisted settings property; the diagnostic
    /// logging toggle is the exception and keeps its property link so the
    /// drift guard covers it.
    static let toolsEntries: [SearchEntry] = [
        SearchEntry(
            id: "advanced.enableDiagnosticLogging",
            title: "Enable diagnostic logging",
            descriptionText: String(localized: "Writes detailed debug logs to a file for troubleshooting. Log files are saved to ~/Library/Logs/Thaw/."),
            pane: .tools,
            section: "Diagnostics",
            keywords: ["diagnostic", "logging", "debug", "logs", "troubleshoot", "tools"],
            property: .tools("enableDiagnosticLogging")
        ),
        SearchEntry(
            id: "tools.diagnosticLogMaxSizeMB",
            title: "Maximum file size",
            descriptionText: String(localized: "A new log file starts once the current one reaches this size."),
            pane: .tools,
            section: "Diagnostics",
            keywords: ["log", "size", "megabytes", "rotate", "rotation", "diagnostics"],
            property: .tools("diagnosticLogMaxSizeMB")
        ),
        SearchEntry(
            id: "tools.diagnosticLogRetentionDays",
            title: "Delete logs after",
            descriptionText: String(localized: "Older log files are deleted after this many days."),
            pane: .tools,
            section: "Diagnostics",
            keywords: ["log", "retention", "days", "keep", "delete", "diagnostics"],
            property: .tools("diagnosticLogRetentionDays")
        ),
        SearchEntry(
            id: "tools.diagnosticLogRotationInterval",
            title: "Start a new file",
            descriptionText: String(localized: "Start a new log file every hour or day, on top of the size limit."),
            pane: .tools,
            section: "Diagnostics",
            keywords: ["log", "rotate", "rotation", "hourly", "daily", "diagnostics"],
            property: .tools("diagnosticLogRotationInterval")
        ),
        SearchEntry(
            id: "tools.exportLogs",
            title: "Export logs",
            descriptionText: String(localized: "Zip the logs and any capture samples into one file to attach to a bug report."),
            pane: .tools,
            section: "Files for a bug report",
            keywords: ["export", "logs", "zip", "bug report", "attach", "capture samples", "diagnostics"],
            property: nil
        ),
        SearchEntry(
            id: "tools.saveItemList",
            title: "Save item list",
            descriptionText: String(localized: "Save a list of every menu bar item Thaw can see."),
            pane: .tools,
            section: "Files for a bug report",
            keywords: ["item list", "dump", "items", "menu bar items", "bug report", "diagnostics"],
            property: nil
        ),
        SearchEntry(
            id: "tools.resetAllSettings",
            title: "Reset all settings",
            descriptionText: String(localized: "Restore every \(Constants.displayName) setting to its default value."),
            pane: .tools,
            section: "Reset",
            keywords: ["reset", "defaults", "settings", "tools"],
            property: nil
        ),
        SearchEntry(
            id: "tools.restoreMissingMenuBarItems",
            title: "Restore missing menu bar items",
            descriptionText: String(localized: "Restore app visibility without resetting saved positions or section assignments."),
            pane: .tools,
            section: "Repair",
            keywords: ["missing", "icons", "visibility", "recovery", "native", "hidden", "control center"],
            property: nil
        ),
        SearchEntry(
            id: "tools.restartMenuBar",
            title: "Restart the menu bar",
            descriptionText: String(localized: "Restarts the system's menu bar service when it gets stuck, for example on top of full-screen apps. Your layout is kept."),
            pane: .tools,
            section: "Repair",
            keywords: ["restart", "menu bar", "stuck", "full screen", "fullscreen", "killall", "MenuBarAgent", "tools"],
            property: nil
        ),
        SearchEntry(
            id: "tools.resetMenuBarLayoutPositions",
            title: "Rebuild macOS's saved menu bar layout",
            descriptionText: String(localized: "Deletes every saved item position and restarts the system's menu bar service, so the layout rebuilds from scratch. Thaw saves a backup first. Use this when items won't return to the menu bar after you rearrange."),
            pane: .tools,
            section: "Repair",
            keywords: ["layout", "positions", "reset", "backup", "restore", "rebuild", "menu bar host", "tools"],
            property: nil
        ),
        SearchEntry(
            id: "tools.resetPermissions",
            title: "Reset permissions",
            descriptionText: String(localized: "Clear Accessibility and Screen Recording decisions for \(Constants.displayName)."),
            pane: .tools,
            section: "Repair",
            keywords: ["permissions", "accessibility", "screen recording", "tccutil", "tools"],
            property: nil
        ),
    ]
}
