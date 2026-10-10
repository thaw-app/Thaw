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
            descriptionText: String(localized: "Lets Thaw read and move menu bar items. Required."),
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
            id: "privacy.captureInspector",
            // The row is the section itself: "What Thaw sees" is the pane's
            // section header, so no separate section is attached.
            title: "What Thaw sees",
            descriptionText: String(localized: "Crop regions are the exact pixels Thaw reads for each menu bar item. Frames are shown once and never saved to disk."),
            pane: .privacy,
            keywords: ["capture", "crop", "inspector", "privacy", "screen", "screen recording", "band", "pixels", "sees"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.updateCheck",
            title: "Update check",
            descriptionText: String(localized: "Asks the update server whether a newer version exists. The only network call Thaw makes on its own."),
            pane: .privacy,
            section: "Network access",
            keywords: ["network", "update", "check", "internet", "privacy", "sparkle", "server", "offline"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.updateDownload",
            title: "Update download",
            descriptionText: String(localized: "Fetches a new version in the background, or only after you accept an update."),
            pane: .privacy,
            section: "Network access",
            keywords: ["network", "update", "download", "automatic", "privacy", "internet"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.fetchReleaseNotes",
            title: "What’s New notes",
            descriptionText: String(localized: "Fetches the latest release notes when you open What’s New and keeps a copy for offline use. When this is off, What’s New shows the notes that shipped with this version."),
            pane: .privacy,
            section: "Network access",
            keywords: ["network", "release notes", "whats new", "what's new", "fetch", "changelog", "privacy", "offline"],
            property: .advanced("fetchReleaseNotes")
        ),
        SearchEntry(
            id: "privacy.turnEverythingOff",
            title: "Turn Everything Off",
            descriptionText: String(localized: "Switches off every network call Thaw makes."),
            pane: .privacy,
            section: "Network access",
            keywords: ["network", "off", "offline", "privacy", "disable", "everything"],
            property: nil
        ),
    ]
}
