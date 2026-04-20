//
//  SharedConstants.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Centralized repository for all URIs and paths used across the project.
/// All hardcoded URIs should be defined here to satisfy static analysis tools
/// and provide a single source of truth.
enum SharedConstants {
    // MARK: - System Framework Paths

    /// Path to the SkyLight private framework for window capture APIs.
    static let skyLightFrameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

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

    /// Returns a required URL from Info.plist.
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
