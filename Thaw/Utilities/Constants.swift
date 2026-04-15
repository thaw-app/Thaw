//
//  Constants.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

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

    /// Info.plist key used to configure the repository URL.
    static let repositoryURLInfoPlistKey = "ThawRepositoryURL"

    /// Info.plist key used to configure the donation URL.
    static let donateURLInfoPlistKey = "ThawDonateURL"

    /// The project's GitHub repository URL.
    static let repositoryURL = requiredInfoPlistURL(repositoryURLInfoPlistKey)

    /// The URL for filing issues.
    static let issuesURL = repositoryURL.appendingPathComponent("issues")

    /// The URL for sponsoring/donating.
    static let donateURL = requiredInfoPlistURL(donateURLInfoPlistKey)

    /// Info.plist key used to configure the executable URI for
    /// `MenuBarItemSpacingManager` shell commands.
    static let menuBarItemSpacingExecutableURIInfoPlistKey =
        "ThawMenuBarItemSpacingExecutableURI"

    /// The executable URL used by `MenuBarItemSpacingManager`.
    static let menuBarItemSpacingExecutableURL = requiredInfoPlistURL(
        menuBarItemSpacingExecutableURIInfoPlistKey
    )

    /// Returns a required URL from Info.plist.
    private static func requiredInfoPlistURL(
        _ key: String,
    ) -> URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            let url = URL(string: value),
            url.scheme != nil
        else {
            fatalError("Missing or invalid Info.plist URL for key: \(key)")
        }

        return url
    }

    // swiftlint:enable force_unwrapping
}
