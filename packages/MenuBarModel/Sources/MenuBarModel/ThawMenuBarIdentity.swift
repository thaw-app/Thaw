//
//  ThawMenuBarIdentity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Identifies menu bar items owned by Thaw across the app and the runtime kit.
public enum ThawMenuBarIdentity {
    public static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw"
    public static let displayName = Bundle.main.displayName

    public static var ownedBundleIdentifiers: Set<String> {
        [bundleIdentifier]
    }

    public static func owns(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return ownedBundleIdentifiers.contains(bundleIdentifier)
    }
}
