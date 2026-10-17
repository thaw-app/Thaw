//
//  SavedOrderMirrorGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Holds back copying the live order into the saved order until the bar has been quiet for a while.
/// After a wake, a display, hiding or item change the bar passes through orders nobody chose.
@MainActor
final class SavedOrderMirrorGate {
    /// MenuBarAgent rewrites its whole table 10 s after a new item appears, so the hold outlasts that.
    static let quietPeriod = Duration.seconds(12)

    private var lastDisturbance: ContinuousClock.Instant?
    private var lastIdentifiers: Set<String>?
    private var systemEventTasks = [Task<Void, Never>]()

    init(observesSystem: Bool = true) {
        guard observesSystem else { return }
        systemEventTasks = [
            NSWorkspace.shared.notificationCenter.eventsTask(named: NSWorkspace.screensDidWakeNotification) { [weak self] in
                self?.noteDisturbance()
            },
            NotificationCenter.default.eventsTask(named: NSApplication.didChangeScreenParametersNotification) { [weak self] in
                self?.noteDisturbance()
            },
        ]
    }

    func noteDisturbance(at instant: ContinuousClock.Instant = .now) {
        lastDisturbance = instant
    }

    /// Whether the cache holding these items may become the saved order now. A changed item set counts as a disturbance.
    func allowsMirror(
        identifiers: Set<String>,
        restrictionChange: ContinuousClock.Instant?,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        if let lastIdentifiers, lastIdentifiers != identifiers {
            lastDisturbance = now
        }
        lastIdentifiers = identifiers
        return Self.isQuiet(now: now, events: [lastDisturbance, restrictionChange], quietPeriod: Self.quietPeriod)
    }

    static nonisolated func isQuiet(
        now: ContinuousClock.Instant,
        events: [ContinuousClock.Instant?],
        quietPeriod: Duration
    ) -> Bool {
        events.compactMap(\.self).allSatisfy { $0.duration(to: now) >= quietPeriod }
    }
}
