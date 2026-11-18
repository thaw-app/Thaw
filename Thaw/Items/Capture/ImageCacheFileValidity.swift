//
//  ImageCacheFileValidity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Whether a saved image cache file may be read, so an update never shows images from the old build
/// without asking for them again.
nonisolated enum ImageCacheFileValidity {
    /// What a read may take from a saved file.
    enum Verdict: Equatable {
        /// Written by this build: every picture may be used.
        case current
        /// Written by another build in this format: only hidden items' pictures may be used, and only
        /// until they are taken again. Only a reveal can take those, so dropping them on every
        /// update left the hidden items as app icons until the user asked for new pictures.
        case otherBuild
        /// Written in another format: nothing may be used.
        case otherFormat
    }

    /// The build that writes and reads the file, from the app bundle.
    static var appBuild: String? {
        Bundle.main.buildString
    }

    static func verdict(fileVersion: Int?, fileBuild: String?, cacheVersion: Int, appBuild: String?) -> Verdict {
        guard fileVersion == cacheVersion else { return .otherFormat }
        guard let appBuild, fileBuild != appBuild else { return .current }
        return .otherBuild
    }

    static func isCurrent(fileVersion: Int?, fileBuild: String?, cacheVersion: Int, appBuild: String?) -> Bool {
        verdict(fileVersion: fileVersion, fileBuild: fileBuild, cacheVersion: cacheVersion, appBuild: appBuild) == .current
    }
}
