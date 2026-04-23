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
enum Constants {
    // swiftlint:disable force_unwrapping

    /// The version string in the app's bundle.
    static let versionString = Bundle.main.versionString!

    /// The build string in the app's bundle.
    static let buildString = Bundle.main.buildString!

    /// The user-readable copyright string in the app's bundle.
    static let copyrightString = Bundle.main.copyrightString!

    /// The app's bundle identifier.
    static let bundleIdentifier = Bundle.main.bundleIdentifier!

    /// The app's display name.
    static let displayName = Bundle.main.displayName

    // swiftlint:enable force_unwrapping

    /// The brightness threshold above which the menu bar is considered "bright".
    /// When the menu bar brightness exceeds this value, items should use dark colors.
    /// Used for non-notched displays.
    static let menuBarBrightnessThreshold: CGFloat = 0.67

    /// The brightness threshold for notched displays.
    /// Lower value means items turn black earlier (more aggressive dark text).
    static let notchedDisplayBrightnessThreshold: CGFloat = 0.5

    // MARK: - App URLs (from Info.plist)

    /// Info.plist key used to configure the repository URL.
    static let repositoryURLInfoPlistKey = "ThawRepositoryURL"

    /// Info.plist key used to configure the donation URL.
    static let donateURLInfoPlistKey = "ThawDonateURL"

    /// Info.plist key used to configure the executable URI for
    /// `MenuBarItemSpacingManager` shell commands.
    static let menuBarItemSpacingExecutableURIInfoPlistKey = "ThawMenuBarItemSpacingExecutableURI"

    /// The project's GitHub repository URL.
    static let repositoryURL: URL = requiredInfoPlistURL(repositoryURLInfoPlistKey)

    /// The URL for filing issues.
    static let issuesURL = repositoryURL.appendingPathComponent("issues")

    /// The URL for sponsoring/donating.
    static let donateURL: URL = requiredInfoPlistURL(donateURLInfoPlistKey)

    /// The executable URL used by `MenuBarItemSpacingManager`.
    static let menuBarItemSpacingExecutableURL: URL = requiredInfoPlistURL(menuBarItemSpacingExecutableURIInfoPlistKey)

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
}
