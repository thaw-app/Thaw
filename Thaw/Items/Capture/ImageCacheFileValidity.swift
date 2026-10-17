//
//  ImageCacheFileValidity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Whether a saved image cache file may be read, so an update never shows images from the old build.
nonisolated enum ImageCacheFileValidity {
    /// The build that writes and reads the file, from the app bundle.
    static var appBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static func isCurrent(fileVersion: Int?, fileBuild: String?, cacheVersion: Int, appBuild: String?) -> Bool {
        guard fileVersion == cacheVersion else { return false }
        guard let appBuild else { return true }
        return fileBuild == appBuild
    }
}
