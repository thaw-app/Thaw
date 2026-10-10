//
//  ScreenLock.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// While locked, captures show no user items and layout writes are replaced at unlock.
/// Read the public session dictionary without changing MenuBarModel; a dark display without a wake password is not locked.
nonisolated enum ScreenLock {
    /// The session dictionary key, a boolean present only while locked.
    static let sessionKey = "CGSSessionScreenIsLocked"

    /// One WindowServer dictionary copy is cheap enough for every move and capture pass.
    static var isLocked: Bool {
        isLocked(session: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    /// A missing dictionary (no window server session) reads as unlocked.
    static func isLocked(session: [String: Any]?) -> Bool {
        (session?[sessionKey] as? NSNumber)?.boolValue ?? false
    }
}

/// Tracks transitions so timer-driven refusal paths log each lock and unlock only once.
nonisolated struct ScreenLockTransitions {
    private(set) var isLocked = false

    /// Records locked and returns whether it changed, so the caller logs it.
    mutating func update(_ locked: Bool) -> Bool {
        defer { isLocked = locked }
        return locked != isLocked
    }
}
