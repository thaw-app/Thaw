//
//  ThawUIWords+Pages.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - Updates

nonisolated extension UpdateChannel {
    var localized: LocalizedStringResource {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        case .alpha: "Alpha"
        }
    }
}

nonisolated extension AutomaticUpdates {
    var localized: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .check: "Check only"
        case .download: "Check and download"
        }
    }

    /// The name in a pill, where the full one doesn't fit; the full one is its help.
    var shortLocalized: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .check: "Check"
        case .download: "Download"
        }
    }
}

extension UpdateConsentStrings {
    static let thaw = UpdateConsentStrings(
        title: "Keep \(Constants.displayName) up to date?",
        message: "\(Constants.displayName) can check for updates automatically. You can also check manually from the menu bar or Settings \(Constants.menuArrow) About.",
        downloadAutomatically: "Download and install updates automatically",
        checkManually: "Check Manually",
        checkAutomatically: "Check Automatically",
        checkboxOn: "On",
        checkboxOff: "Off"
    )
}

// MARK: - What's New

nonisolated extension ChangelogDocument.Callout.Kind {
    var localized: LocalizedStringResource {
        switch self {
        case .note: "Note"
        case .tip: "Tip"
        case .important: "Important"
        case .warning: "Warning"
        case .caution: "Caution"
        }
    }
}

extension WhatsNewStrings {
    static let thaw = WhatsNewStrings(
        title: "What’s New",
        releaseTitle: { "What’s new in \($0)" },
        releaseSubtitle: { date, facts in Text("\(date) · \(facts)") },
        noRelease: { channel, appName in Text("There is no \(channel) release of \(appName) 3 yet.") },
        loadFailed: { "\($0) couldn’t load the release notes." },
        fetchingOff: "Fetching release notes is off in Privacy. Turn on “What’s New notes” there to load them.",
        fetchingOffCached: "Fetching release notes is off in Privacy, so this is the last copy fetched.",
        updateReady: "This update is ready to install. Use the update window to install it now or later.",
        cachedCopy: "The repository could not be reached, so this is the last copy fetched.",
        fullChangelog: "Full changelog",
        older: "Older",
        channelName: { $0.localized },
        calloutName: { $0.localized }
    )
}

// MARK: - About

extension AboutStrings {
    static let thaw = AboutStrings(
        tagline: "The open source menu bar manager for macOS",
        versionLabel: { version, build, commit in "Version \(version), build \(build), commit \(commit)" },
        copied: "Copied",
        copyHelp: "Copy the version, build and commit for a bug report",
        copyLabel: "Copy version information",
        whatsNew: "What’s New",
        reportBug: "Report a Bug",
        more: "More about \(Constants.displayName)",
        sourceCode: "Source Code",
        credits: "Credits",
        support: "Support Thaw"
    )
}

extension AboutUpdateStrings {
    static let thaw = AboutUpdateStrings(
        updateChannel: "Update channel",
        automaticUpdates: "Automatic updates",
        checkNow: "Check Now",
        notChecked: "Not checked yet",
        lastChecked: { "Last checked \($0)" },
        channelName: { $0.localized },
        automaticUpdatesName: { $0.localized },
        automaticUpdatesShortName: { $0.shortLocalized }
    )
}

// MARK: - Acknowledgements

extension AcknowledgementsStrings {
    static let thaw = AcknowledgementsStrings(
        credits: "Credits",
        origins: "Origins",
        licenses: "Licenses",
        older: "Older",
        thanks: "Thank you to everyone who contributes code, documentation, and translations to Thaw.",
        contributors: "Contributors",
        translators: "Translators",
        contribute: "Contribute",
        helpTranslate: "Help translate"
    )
}

extension AcknowledgementsContent {
    /// Parsing the RTF is not free, so the result is kept for the process's life.
    private static let notices = AcknowledgementsDocument.load(
        from: Bundle.main.url(forResource: "Acknowledgements", withExtension: "rtf")
    )

    static var thaw: AcknowledgementsContent {
        AcknowledgementsContent(
            contributeURL: Constants.repositoryURL,
            translateURL: Constants.translateURL,
            contributorsURL: Constants.contributorsURL,
            translatorsURL: Constants.translatorsURL,
            origins: [
                AcknowledgementEntry(
                    detail: Text("\(Constants.displayName) has its origins in Ice by Jordan Baird. Thank you for where it started."),
                    url: URL(string: "https://github.com/jordanbaird/Ice")
                ),
                AcknowledgementEntry(
                    detail: Text("Live system readings (CPU, Wi-Fi, battery) and the multi-item status bar publishing pattern are adapted from Barometer by mackid1993, licensed under the GNU GPLv3. Used with permission."),
                    url: URL(string: "https://github.com/mackid1993/Barometer")
                ),
            ],
            licenses: .document(notices, unavailable: "\(Constants.displayName) couldn’t load the bundled acknowledgements document.")
        )
    }
}
