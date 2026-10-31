//
//  ThawAppInfo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// What a shared page needs to know about the app showing it.
public nonisolated struct ThawAppInfo: Sendable {
    public var displayName: String
    public var version: String
    /// The raw changelog the release notes are read from.
    public var changelogURL: URL
    /// Where "Full changelog" goes.
    public var releasesURL: URL
    /// A folder of the app's own under Caches, for an app that isn't sandboxed and so shares Caches with others.
    public var cacheFolderName: String?
    /// Only this version line's notes show. Nil shows every release.
    public var shownMajorVersion: Int?
    /// Whether What's New lists one update channel at a time.
    public var showsChannels: Bool

    public init(
        displayName: String,
        version: String,
        changelogURL: URL,
        releasesURL: URL,
        cacheFolderName: String? = nil,
        shownMajorVersion: Int? = nil,
        showsChannels: Bool = false
    ) {
        self.displayName = displayName
        self.version = version
        self.changelogURL = changelogURL
        self.releasesURL = releasesURL
        self.cacheFolderName = cacheFolderName
        self.shownMajorVersion = shownMajorVersion
        self.showsChannels = showsChannels
    }
}

/// Sparkle appcast channels.
public nonisolated enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    /// Default channel (no sparkle:channel in the appcast).
    case stable
    /// Development / RC builds (sparkle:channel = beta).
    case beta
    /// Alpha builds for macOS 27 (sparkle:channel = alpha).
    case alpha

    /// Stable carries incompatible builds, so offering it would stop updates.
    public static let selectable: [UpdateChannel] = [.beta, .alpha]

    /// Preserve the persisted key so existing channel choices carry over.
    public static let defaultsKey = "UpdateChannel"

    public var id: String {
        rawValue
    }

    /// Sparkle channel names to allow in addition to the default channel. Alpha also takes betas:
    /// a beta is a later build than the alphas before it, and releases are tagged with one channel each.
    public var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable:
            []
        case .beta:
            ["beta"]
        case .alpha:
            ["alpha", "beta"]
        }
    }
}
