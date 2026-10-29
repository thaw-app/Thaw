//
//  BackdropRefreshCadence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// How often MenuBarBackdrop re-reads what is behind the bar on its own, so
/// the strip a cover paints is never far behind the real bar. Fast while a
/// cover is likely soon, slow otherwise, and not at all while nobody can
/// see the bar.
nonisolated enum BackdropRefreshCadence {
    static let fast = Duration.seconds(3)
    static let slow = Duration.seconds(20)
    /// Input-free this long, the bar is left alone until someone is back.
    static let idleThreshold: TimeInterval = 120

    /// The wait before the next refresh, or nil to skip one. coverLikely: Thaw
    /// is frontmost or the Thaw Bar is open, when icon captures happen.
    /// barVisible: some display shows its bar; a full-screen app hides it, and
    /// reading the windows below it then captures the app's own content.
    static func nextInterval(coverLikely: Bool, barVisible: Bool, screenLocked: Bool, idleSeconds: TimeInterval) -> Duration? {
        guard barVisible, !screenLocked, idleSeconds < idleThreshold else { return nil }
        return coverLikely ? fast : slow
    }

    /// Whether a timed refresh re-composites even when the windows under the
    /// bar are unchanged, to catch a window repainting in place. Only while a
    /// cover is likely; otherwise a tick captures only after a window moved.
    static func forcesRecomposite(coverLikely: Bool) -> Bool {
        coverLikely
    }
}
