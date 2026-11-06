//
//  SystemNotificationCenterHotkey.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// The system's "Show Notification Center" keyboard shortcut.
///
/// On macOS 27 the concealment assertion Thaw holds also suppresses this
/// shortcut, so the input layer has to recognise it and bridge it the way the
/// Clock click is bridged. The system stores the binding in
/// com.apple.symbolichotkeys as a parameters array of
/// [ascii, keyCode, modifiers]. A stock system never materializes it.
nonisolated struct SystemNotificationCenterHotkey: Equatable {
    /// The symbolic-hotkey identifiers for "Show Notification Center"; the
    /// ID moved across releases, so both are read, first enabled entry wins.
    static let symbolicHotKeyIDs = ["162", "163"]

    let keyCode: CGKeyCode
    /// The shortcut's device-independent modifiers, including Fn.
    let flags: CGEventFlags

    private static let trackedModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
    ]

    /// macOS uses Fn-N when no symbolic-hotkey override is stored. A bare
    /// Globe press belongs to the user's keyboard setting, not this bridge.
    static let systemDefault = SystemNotificationCenterHotkey(keyCode: 45, flags: [.maskSecondaryFn])

    /// Reads the user's binding, respecting disabled and unassigned entries.
    /// A missing entry uses the system default.
    static func shortcuts() -> [SystemNotificationCenterHotkey] {
        let applicationID = "com.apple.symbolichotkeys" as CFString
        let key = "AppleSymbolicHotKeys" as CFString
        CFPreferencesAppSynchronize(applicationID)
        let table = CFPreferencesCopyAppValue(key, applicationID) as? [String: Any] ?? [:]
        return shortcuts(from: table)
    }

    static func shortcuts(from table: [String: Any]) -> [SystemNotificationCenterHotkey] {
        guard let configured = configured(from: table) else { return [] }
        return configured == systemDefault ? [configured] : [configured, systemDefault]
    }

    static func configured(from table: [String: Any]) -> SystemNotificationCenterHotkey? {
        guard symbolicHotKeyIDs.contains(where: { table[$0] != nil }) else {
            return systemDefault
        }
        for id in symbolicHotKeyIDs {
            guard
                let entry = table[id] as? [String: Any],
                isEnabled(entry),
                let value = entry["value"] as? [String: Any],
                let parameters = value["parameters"] as? [NSNumber],
                parameters.count >= 3,
                let keyCode = CGKeyCode(exactly: parameters[1].int64Value),
                keyCode != UInt16.max
            else {
                continue
            }
            return SystemNotificationCenterHotkey(
                keyCode: keyCode,
                flags: CGEventFlags(rawValue: parameters[2].uint64Value)
                    .intersection(trackedModifiers)
            )
        }
        return nil
    }

    private static func isEnabled(_ entry: [String: Any]) -> Bool {
        if let enabled = entry["enabled"] as? Bool {
            return enabled
        }
        return (entry["enabled"] as? NSNumber)?.boolValue == true
    }

    /// Whether a press with keyCode and flags is this shortcut, ignoring
    /// modifiers the app does not track (Caps Lock and the numeric keypad).
    func matches(keyCode otherKeyCode: CGKeyCode, flags otherFlags: CGEventFlags) -> Bool {
        keyCode == otherKeyCode
            && flags == otherFlags.intersection(Self.trackedModifiers)
    }

    func matches(_ event: CGEvent) -> Bool {
        matches(
            keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags
        )
    }
}
