//
//  BundleExtensions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Info.plist metadata accessors, shared by the app and this package.
public extension Bundle {
    /// The bundle's copyright string.
    var copyrightString: String? {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    /// The bundle's display name.
    var displayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Thaw"
    }

    /// The bundle's version string.
    var versionString: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The bundle's build string.
    var buildString: String? {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
