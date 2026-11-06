//
//  NotificationCenterEventReplay.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

nonisolated enum NotificationCenterEventReplay {
    private static let stamp: Int64 = 0x5468_6177_4E43_484B

    static func isReplay(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == stamp
    }

    /// Keep the clicked display: pressing the shared AX Clock instead opens
    /// the panel on whichever display publishes that element.
    static func clockClick(at point: CGPoint) -> [CGEvent] {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return [] }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.eventSourceUserData, value: stamp)
        }
        return [down, up]
    }

    static func shortcut(_ hotkey: SystemNotificationCenterHotkey) -> [CGEvent] {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: hotkey.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: hotkey.keyCode, keyDown: false)
        else { return [] }
        for event in [down, up] {
            event.flags = hotkey.flags
            event.setIntegerValueField(.eventSourceUserData, value: stamp)
        }
        return [down, up]
    }
}
