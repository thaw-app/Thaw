//
//  MenuBarLiveRefreshPolicy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Pure live-refresh cadence and backend decisions.
nonisolated enum MenuBarLiveRefreshPolicy {
    /// Capture backend for a section's live icons.
    enum Backend: Equatable {
        /// On-screen items: ScreenCaptureKit in the app process.
        case screenCaptureKit
        /// Offscreen items: recyclable SkyLight capture XPC.
        case captureService
    }

    /// Returns the live interval for `section`, or `nil` when refresh is Off.
    static func refreshInterval(
        for section: MenuBarSection.Name,
        target: TimeInterval
    ) -> TimeInterval? {
        guard target > 0 else { return nil }
        switch section {
        case .visible, .hidden:
            return max(target, MenuBarItemImageCache.minIconRefreshInterval)
        case .alwaysHidden:
            return max(target, MenuBarCaptureService.minAlwaysHiddenInterval)
        }
    }

    static func backend(for section: MenuBarSection.Name) -> Backend {
        section == .visible ? .screenCaptureKit : .captureService
    }

    /// One offscreen request in flight. When both are due, Always Hidden goes
    /// first: `isDue` already caps it at 1 fps, so this cannot raise its rate,
    /// and Hidden retries on the next wake instead of starving it.
    static func nextOffscreenSection(hiddenDue: Bool, alwaysHiddenDue: Bool) -> MenuBarSection.Name? {
        if alwaysHiddenDue { return .alwaysHidden }
        if hiddenDue { return .hidden }
        return nil
    }

    /// First frame is due immediately; later frames wait for `interval`.
    static func isDue(
        lastCaptureAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        interval: Duration
    ) -> Bool {
        guard let lastCaptureAt else { return true }
        return now - lastCaptureAt >= interval
    }

    /// Drops missed frames: if capture overran `interval`, wait a full interval
    /// from `now` instead of queuing catch-up work.
    static func nextDeadline(
        capturedAt: ContinuousClock.Instant,
        interval: Duration,
        now: ContinuousClock.Instant
    ) -> ContinuousClock.Instant {
        let due = capturedAt + interval
        return due > now ? due : now + interval
    }
}
