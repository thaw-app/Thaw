//
//  Constants.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// App-specific constants for the main Thaw target.
/// System-framework paths shared with XPC targets live in `SharedConstants`.
nonisolated enum Constants {
    // swiftlint:disable force_unwrapping

    static let versionString = Bundle.main.versionString!

    static let buildString = Bundle.main.buildString!

    static let copyrightString = Bundle.main.copyrightString!

    static let bundleIdentifier = Bundle.main.bundleIdentifier!

    static let displayName = Bundle.main.displayName

    // swiftlint:enable force_unwrapping

    /// Menu bar brightness above which items use dark colors, on non-notched displays.
    static let menuBarBrightnessThreshold: CGFloat = 0.67

    /// The brightness threshold for notched displays.
    /// Matches the non-notched threshold to avoid biasing toward dark text on
    /// notched displays where the black notch area lowers the sampled average.
    static let notchedDisplayBrightnessThreshold: CGFloat = 0.67

    // MARK: - App URLs (from Info.plist)

    /// Info.plist key used to configure the repository URL.
    static let repositoryURLInfoPlistKey = "ThawRepositoryURL"

    /// Info.plist key used to configure the donation URL.
    static let donateURLInfoPlistKey = "ThawDonateURL"

    /// Info.plist key used to configure the executable URI for
    /// `MenuBarItemSpacingManager` shell commands.
    static let menuBarItemSpacingExecutableURIInfoPlistKey = "ThawMenuBarItemSpacingExecutableURI"

    /// Info.plist key used to configure the executable URI for `launchctl`,
    /// which restarts LaunchAgent-owned menu bar items.
    static let launchctlExecutableURIInfoPlistKey = "ThawLaunchctlExecutableURI"

    static let repositoryURL: URL = requiredInfoPlistURL(repositoryURLInfoPlistKey)

    static let issuesURL = repositoryURL.appendingPathComponent("issues")

    /// The URL for downloading preview builds.
    static let releasesURL = repositoryURL.appendingPathComponent("releases")

    /// The URL for sponsoring/donating.
    static let donateURL: URL = requiredInfoPlistURL(donateURLInfoPlistKey)

    /// The Crowdin project URL for community translations.
    static let translateURL = URL(string: "https://crowdin.com/project/thaw")!

    /// The executable URL used by `MenuBarItemSpacingManager`.
    static let menuBarItemSpacingExecutableURL: URL = requiredInfoPlistURL(menuBarItemSpacingExecutableURIInfoPlistKey)

    /// The `launchctl` executable used by `MenuBarItemSpacingManager`.
    static let launchctlExecutableURL: URL = requiredInfoPlistURL(launchctlExecutableURIInfoPlistKey)

    // MARK: - Helpers

    /// Returns a required URL from the bundle's Info.plist.
    private static func requiredInfoPlistURL(_ key: String) -> URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            let url = URL(string: value),
            url.scheme != nil
        else {
            fatalError("Missing or invalid Info.plist URL for key: \(key)")
        }
        return url
    }

    /// The arrow character used in menu path descriptions (→).
    /// Extracted so translators see %@ instead of a unicode arrow.
    static let menuArrow = "\u{2192}"
}
