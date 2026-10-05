//
//  SearchIndex+Tools.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Tools

    /// Rows in the Tools pane, in the pane's own order. Mostly one-shot
    /// maintenance actions with no persisted settings property; the diagnostic
    /// logging toggle is the exception and keeps its property link so the
    /// drift guard covers it.
    static let toolsEntries: [SearchEntry] = [
        SearchEntry(
            id: "tools.replayOnboarding",
            title: "Replay onboarding",
            descriptionText: String(localized: "Review the feature tour and permission setup again."),
            pane: .tools,
            section: "Onboarding",
            keywords: ["onboarding", "replay", "tour", "welcome", "setup", "permissions", "intro", "tools"],
            property: nil
        ),
        SearchEntry(
            id: "advanced.enableDiagnosticLogging",
            title: "Enable diagnostic logging",
            descriptionText: String(localized: "Writes detailed debug logs to a file for troubleshooting. Log files are saved to ~/Library/Logs/Thaw/."),
            pane: .tools,
            section: "Diagnostics",
            keywords: ["diagnostic", "logging", "debug", "logs", "troubleshoot", "tools"],
            property: .advanced("enableDiagnosticLogging")
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
            section: "Troubleshooting",
            keywords: ["missing", "icons", "visibility", "recovery", "native", "hidden", "control center"],
            property: nil
        ),
        SearchEntry(
            id: "tools.resetControlCenter",
            title: "Reset Control Center preferences",
            descriptionText: String(localized: "Quit Control Center and delete its preference files so system menu bar item state can rebuild."),
            pane: .tools,
            section: "Troubleshooting",
            keywords: ["control center", "preferences", "plist", "reset", "menu bar", "tools"],
            property: nil
        ),
        SearchEntry(
            id: "tools.resetMenuBarLayoutPositions",
            title: "Reset menu bar layout positions",
            descriptionText: String(localized: "Deletes every saved item position and restarts the system's menu bar service, so the layout rebuilds from scratch. Thaw saves a backup first. Use this when items won't return to the menu bar after you rearrange."),
            pane: .tools,
            section: "Troubleshooting",
            keywords: ["layout", "positions", "reset", "backup", "restore", "rebuild", "menu bar host", "tools"],
            property: nil
        ),
        SearchEntry(
            id: "tools.quitAndClearCache",
            title: "Quit and clear cache",
            descriptionText: String(localized: "Delete \(Constants.displayName)'s cache folder, then quit the app."),
            pane: .tools,
            section: "Troubleshooting",
            keywords: ["cache", "quit", "clear", "tools"],
            property: nil
        ),
        SearchEntry(
            id: "tools.resetPermissions",
            title: "Reset permissions",
            descriptionText: String(localized: "Clear Accessibility and Screen Recording decisions for \(Constants.displayName)."),
            pane: .tools,
            section: "Troubleshooting",
            keywords: ["permissions", "accessibility", "screen recording", "tccutil", "tools"],
            property: nil
        ),
    ]
}
