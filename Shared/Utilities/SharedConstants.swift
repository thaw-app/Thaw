//
//  SharedConstants.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Constants shared across all targets (main app and XPC services).
/// Only values that are needed in every target belong here; app-only
/// constants live in `Constants` (Thaw target).
nonisolated enum SharedConstants {
    // MARK: - System Framework Paths

    /// Info.plist key used to configure the SkyLight private framework path.
    static let skyLightFrameworkPathInfoPlistKey = "ThawSkyLightFrameworkPath"

    /// Path to the SkyLight private framework for window capture APIs.
    static let skyLightFrameworkPath: String = requiredInfoPlistString(skyLightFrameworkPathInfoPlistKey)

    // MARK: - Accessibility

    /// Ceiling, in seconds, on a single accessibility message.
    ///
    /// AX calls are synchronous IPC, so a stalled app blocks us for the
    /// six-second system default (#767). Healthy calls take well under 100 ms.
    /// The app applies it in `applicationWillFinishLaunching` (overridable via
    /// `axMessagingTimeout`); `MenuBarItemService` uses it directly.
    static let axMessagingTimeout = 1.0

    // MARK: - Menu Bar Host

    /// Bundle identifier of the process that hosts the menu bar's status
    /// items on this OS. Maintenance tools use it to locate (and reset) the
    /// preference domain holding every saved status-item position.
    static let menuBarHostingBundleID = "com.apple.controlcenter"

    // MARK: - Helpers

    /// Returns a required string from the bundle's Info.plist.
    private static func requiredInfoPlistString(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            fatalError("Missing or invalid Info.plist string for key: \(key)")
        }
        return value
    }
}
