//
//  NotificationCenterInputState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Balances only the physical events claimed by the Notification Center bridge.
nonisolated struct NotificationCenterInputState {
    enum KeyDisposition: Equatable {
        case passThrough
        case consume
        case activate
    }

    private var heldKeys = Set<CGKeyCode>()
    private var clockPress: (point: CGPoint, bounds: CGRect, cancelled: Bool)?

    var hasClockPress: Bool {
        clockPress != nil
    }

    var hasHeldKeys: Bool {
        !heldKeys.isEmpty
    }

    mutating func key(
        type: CGEventType,
        code: CGKeyCode,
        isRepeat: Bool,
        matches: Bool,
        shouldBridge: Bool
    ) -> KeyDisposition {
        switch type {
        case .keyUp:
            return heldKeys.remove(code) != nil ? .consume : .passThrough
        case .keyDown:
            if isRepeat {
                return heldKeys.contains(code) ? .consume : .passThrough
            }
            // A fresh press supersedes a release lost when macOS disabled a tap.
            heldKeys.remove(code)
            guard matches, shouldBridge else { return .passThrough }
            heldKeys.insert(code)
            return .activate
        default:
            return .passThrough
        }
    }

    mutating func beginClockPress(at point: CGPoint, bounds: CGRect) {
        clockPress = (point, bounds, false)
    }

    mutating func dragClockPress(to point: CGPoint) {
        guard let press = clockPress else { return }
        if !press.bounds.insetBy(dx: -4, dy: -4).contains(point) {
            clockPress?.cancelled = true
        }
    }

    mutating func endClockPress(at point: CGPoint) -> CGPoint? {
        dragClockPress(to: point)
        defer { clockPress = nil }
        guard let press = clockPress, !press.cancelled else { return nil }
        return press.point
    }

    mutating func discardClockPress() {
        clockPress = nil
    }
}
