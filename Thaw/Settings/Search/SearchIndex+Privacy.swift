//
//  SearchIndex+Privacy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Privacy Rows

    /// Rows in the Privacy pane. None have a settings property, so the drift
    /// guard does not cover them.
    static let privacyEntries: [SearchEntry] = [
        SearchEntry(
            id: "privacy.accessibility",
            title: "Accessibility",
            descriptionText: String(localized: "Lets \(Constants.displayName) read and move menu bar items. Required."),
            pane: .privacy,
            section: "Permissions",
            keywords: ["accessibility", "permission", "grant", "access", "privacy", "required"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.screenRecording",
            title: "Screen Recording",
            descriptionText: String(localized: "Lets Thaw capture menu bar item images for search, the layout editor and the Thaw Bar. Optional."),
            pane: .privacy,
            section: "Permissions",
            keywords: ["screen recording", "permission", "grant", "capture", "privacy", "optional", "images"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.notifications",
            title: "Notifications",
            descriptionText: String(localized: "Lets Thaw tell you when an update is ready and when a shortcut changes a setting. Optional."),
            pane: .privacy,
            section: "Permissions",
            keywords: ["notifications", "alerts", "permission", "banner", "update", "optional"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.captureInspector",
            // The row is the section itself: "What Thaw sees" is the pane's
            // section header, so no separate section is attached.
            title: "What Thaw sees",
            descriptionText: String(localized: "Crop regions are the exact pixels \(Constants.displayName) reads for each menu bar item. Frames are shown once and never saved to disk."),
            pane: .privacy,
            keywords: ["capture", "crop", "inspector", "privacy", "screen", "screen recording", "band", "pixels", "sees"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.automaticUpdates",
            title: "Automatic updates",
            descriptionText: String(localized: "Off, Check only, or Check and download. Checking asks the update server whether a newer version exists."),
            pane: .privacy,
            section: "Network access",
            keywords: ["network", "update", "check", "download", "automatic", "internet", "privacy", "sparkle", "server", "offline"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.fetchReleaseNotes",
            title: "What’s New notes",
            descriptionText: String(localized: "Fetches the latest release notes when you open What’s New and keeps a copy for offline use. When this is off, What’s New shows the notes that shipped with this version."),
            pane: .privacy,
            section: "Network access",
            keywords: ["network", "release notes", "whats new", "what's new", "fetch", "changelog", "privacy", "offline"],
            property: .privacy("fetchReleaseNotes")
        ),
        SearchEntry(
            id: "privacy.showReleaseNotesAfterUpdate",
            title: "Show release notes after an update",
            descriptionText: String(localized: "Opens What’s New the first time \(Constants.displayName) starts after an update. You can still open it from \(Constants.displayName)’s menu or About."),
            pane: .privacy,
            section: "Network access",
            keywords: ["release notes", "whats new", "what's new", "update", "changelog", "window", "after update"],
            property: .privacy("showReleaseNotesAfterUpdate")
        ),
    ]
}
