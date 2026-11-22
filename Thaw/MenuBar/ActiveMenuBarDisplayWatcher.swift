//
//  ActiveMenuBarDisplayWatcher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel

/// Reports when the active menu bar moves to another display. macOS sends no notification for the move,
/// so app, Space and click events ask, and a one-second check catches the rest. A display change is the
/// display-change coordinator's presentation step instead.
@MainActor
final class ActiveMenuBarDisplayWatcher {
    var onChange: (() -> Void)?
    /// Whether anything depends on the active display right now. The
    /// one-second check exists only while something does.
    var isNeeded: () -> Bool = { true }

    /// How long a throttled check trusts the last answer. The pointer stream
    /// asks on every move, and each read is a round trip to the window server.
    static let throttleInterval: Duration = .milliseconds(100)

    /// The one-second check's interval and the slack macOS may add to coalesce wake-ups.
    static let timerInterval: TimeInterval = 1
    static let timerTolerance: TimeInterval = 0.2

    private let readDisplayID: () -> CGDirectDisplayID?
    private var lastDisplayID: CGDirectDisplayID?
    private var lastCheck: ContinuousClock.Instant?
    let idleGate: IdleGate
    /// Set by start(), in the +Live file.
    var observationTasks: [Task<Void, Never>] = []
    var idleGateSubscription: AnyCancellable?
    private var timer: Timer?

    var isTimerArmed: Bool {
        timer != nil
    }

    init(
        readDisplayID: @escaping () -> CGDirectDisplayID? = { Bridging.getActiveMenuBarDisplayID() },
        idleGate: IdleGate = .shared
    ) {
        self.readDisplayID = readDisplayID
        self.idleGate = idleGate
    }

    isolated deinit {
        timer?.invalidate()
        observationTasks.forEach { $0.cancel() }
    }

    /// Whether the one-second check should exist.
    nonisolated static func wantsTimer(isNeeded: Bool, mayRunIdleWork: Bool) -> Bool {
        isNeeded && mayRunIdleWork
    }

    /// Arms or drops the one-second check to match wantsTimer(isNeeded:mayRunIdleWork:).
    func updateTimer() {
        guard Self.wantsTimer(isNeeded: isNeeded(), mayRunIdleWork: idleGate.mayRunIdleWork) else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.timerInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
        timer.tolerance = Self.timerTolerance
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    /// Reads the active display and reports a change from the last known one.
    /// A throttled check, from the pointer stream, skips the read while the
    /// last one is younger than throttleInterval.
    func check(throttled: Bool = false, now: ContinuousClock.Instant = .now) {
        if throttled, let lastCheck, now - lastCheck < Self.throttleInterval {
            return
        }
        lastCheck = now
        guard let displayID = readDisplayID() else { return }
        defer { lastDisplayID = displayID }
        if let lastDisplayID, lastDisplayID != displayID {
            onChange?()
        }
    }
}
