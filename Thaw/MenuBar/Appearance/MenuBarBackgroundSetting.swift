//
//  MenuBarBackgroundSetting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// macOS's "Show menu bar background" in System Settings › Menu Bar. While
/// it's on, macOS draws its own background under the bar, which covers Thaw's look.
nonisolated enum MenuBarBackgroundSetting {
    /// The global preference SkyLight keeps the switch in; unset means off.
    static let key = "SLSMenuBarUseBlurredAppearance"

    static func isOn(read: (String) -> Any? = readGlobal) -> Bool {
        (read(key) as? NSNumber)?.boolValue ?? false
    }

    private static func readGlobal(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication)
    }
}
