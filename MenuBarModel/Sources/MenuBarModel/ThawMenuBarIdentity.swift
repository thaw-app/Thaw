//
//  ThawMenuBarIdentity.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Identifies menu bar items owned by Thaw across the app and host processes.
public enum ThawMenuBarIdentity {
    public static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw"
    public static let displayName = Bundle.main.displayName

    public static var ownedBundleIdentifiers: Set<String> {
        [
            bundleIdentifier,
            "\(bundleIdentifier).MenuBarHost",
        ]
    }

    public static func owns(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return ownedBundleIdentifiers.contains(bundleIdentifier)
    }
}
