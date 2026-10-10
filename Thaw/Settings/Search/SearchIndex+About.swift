//
//  SearchIndex+About.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: About Settings

    static let aboutEntries: [SearchEntry] = [
        SearchEntry(
            id: "about.automaticallyCheckForUpdates",
            title: "Automatically check for updates",
            descriptionText: nil,
            pane: .about,
            section: "Updates",
            keywords: ["update", "automatic", "check", "sparkle"],
            property: nil
        ),
        SearchEntry(
            id: "about.automaticallyDownloadUpdates",
            title: "Automatically download updates",
            descriptionText: nil,
            pane: .about,
            section: "Updates",
            keywords: ["update", "automatic", "download", "sparkle"],
            property: nil
        ),
        SearchEntry(
            id: "about.updateChannel",
            title: "Update channel",
            descriptionText: String(localized: "Choose Beta or Nightly updates. Automatic updates can be Off, Check only, or Check and download."),
            pane: .about,
            section: "Updates",
            keywords: ["update", "channel", "beta", "nightly", "automatic", "check", "download"],
            property: nil
        ),
    ]
}
