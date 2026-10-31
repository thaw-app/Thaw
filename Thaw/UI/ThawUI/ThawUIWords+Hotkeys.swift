//
//  ThawUIWords+Hotkeys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - Hotkeys

extension HotkeyRecorderStrings {
    static let thaw = HotkeyRecorderStrings(
        typeShortcut: "Type Shortcut",
        recordShortcut: "Record Shortcut",
        cancel: "Cancel",
        clear: "Clear",
        record: "Record",
        spaceKey: "Space",
        reservedTitle: "macOS already uses this shortcut",
        reservedMessage: "Record a different one, or turn this one off in System Settings \(Constants.menuArrow) Keyboard \(Constants.menuArrow) Keyboard Shortcuts.",
        chooseAnother: "Choose Another"
    )
}

extension HotkeyRecorder {
    /// A recorder for one of Thaw's hotkeys. The hotkey stands down while a
    /// recording runs, so the combination being replaced can't fire.
    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        self.init(
            keyCombination: Binding {
                hotkey.isEnabled ? hotkey.keyCombination : nil
            } set: {
                hotkey.keyCombination = $0
            },
            strings: .thaw,
            onRecordingChange: { isRecording in
                if isRecording {
                    hotkey.disable()
                } else {
                    hotkey.enable()
                }
            },
            label: label
        )
    }
}
