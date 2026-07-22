//
//  LegacyConstants.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Compatibility symbols retained for published PlatformRuntimeKit binaries.
@available(*, deprecated, message: "Use ThawMenuBarIdentity")
public enum Constants {
    public static var thawOwnedBundleIdentifiers: Set<String> {
        ThawMenuBarIdentity.ownedBundleIdentifiers
    }

    public static func isThawOwnedBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        ThawMenuBarIdentity.owns(bundleIdentifier: bundleIdentifier)
    }
}
