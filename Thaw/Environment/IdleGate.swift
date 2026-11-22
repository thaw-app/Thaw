//
//  IdleGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel

/// Whether Thaw's periodic checks may run, from the two signals that say nobody is looking.
nonisolated struct IdleGateState: Equatable, Sendable {
    enum Signal: Sendable {
        case displaysSlept, displaysWoke, sessionResigned, sessionBecameActive
    }

    private(set) var displaysAsleep = false
    private(set) var sessionInactive = false

    /// Both signals have to clear, since a wake and a return to the session arrive in either order.
    var mayRunIdleWork: Bool {
        !displaysAsleep && !sessionInactive
    }

    func applying(_ signal: Signal) -> IdleGateState {
        var next = self
        switch signal {
        case .displaysSlept: next.displaysAsleep = true
        case .displaysWoke: next.displaysAsleep = false
        case .sessionResigned: next.sessionInactive = true
        case .sessionBecameActive: next.sessionInactive = false
        }
        return next
    }
}

/// Pauses periodic work while every display sleeps or the login session is inactive, as after a
/// fast user switch. Owners subscribe and stop their timers; one-off reactions to events keep running.
@MainActor
final class IdleGate {
    static let shared = IdleGate()

    private static let diagLog = DiagLog(category: "IdleGate")
    private static let signals: [(Notification.Name, IdleGateState.Signal)] = [
        (NSWorkspace.screensDidSleepNotification, .displaysSlept),
        (NSWorkspace.screensDidWakeNotification, .displaysWoke),
        (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
        (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
    ]

    private(set) var state = IdleGateState()
    private var subscribers: [UUID: @MainActor (Bool) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private let center: NotificationCenter

    var mayRunIdleWork: Bool {
        state.mayRunIdleWork
    }

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
        observers = Self.signals.map { name, signal in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.note(signal) }
            }
        }
    }

    isolated deinit {
        observers.forEach(center.removeObserver)
    }

    /// Calls every subscriber when mayRunIdleWork flips, and only then.
    func note(_ signal: IdleGateState.Signal) {
        let wasAllowed = mayRunIdleWork
        state = state.applying(signal)
        let isAllowed = mayRunIdleWork
        guard isAllowed != wasAllowed else { return }
        Self.diagLog.info(isAllowed ? "Displays awake and session active, resuming idle work" : "Displays asleep or session inactive, pausing idle work")
        for subscriber in Array(subscribers.values) {
            subscriber(isAllowed)
        }
    }

    /// Calls onChange with the new answer each time mayRunIdleWork flips, until the token is released.
    func subscribe(_ onChange: @escaping @MainActor (Bool) -> Void) -> AnyCancellable {
        let id = UUID()
        subscribers[id] = onChange
        return AnyCancellable { [weak self] in
            Self.onMain { _ = self?.subscribers.removeValue(forKey: id) }
        }
    }

    /// A repeating main run loop timer that exists only while idle work may run. onResume runs once
    /// each time the gate opens again, before the first tick, so a change made meanwhile is not missed.
    func repeating(
        every interval: TimeInterval,
        tolerance: TimeInterval,
        mode: RunLoop.Mode = .default,
        onResume: (@MainActor () async -> Void)? = nil,
        tick: @escaping @MainActor () async -> Void
    ) -> AnyCancellable {
        let timer = IdleGatedTimer(interval: interval, tolerance: tolerance, mode: mode, onResume: onResume, tick: tick)
        timer.apply(mayRun: mayRunIdleWork, resuming: false)
        let subscription = subscribe { [weak timer] in timer?.apply(mayRun: $0, resuming: $0) }
        return AnyCancellable {
            subscription.cancel()
            Self.onMain { timer.apply(mayRun: false, resuming: false) }
        }
    }

    /// A token can be released on any thread; what it undoes belongs to the main actor.
    private nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }
}

/// The timer behind IdleGate.repeating, armed and disarmed as the gate opens and closes.
@MainActor
final class IdleGatedTimer {
    private let interval: TimeInterval
    private let tolerance: TimeInterval
    private let mode: RunLoop.Mode
    private let onResume: (@MainActor () async -> Void)?
    private let tick: @MainActor () async -> Void
    private var timer: Timer?

    var isArmed: Bool {
        timer != nil
    }

    init(
        interval: TimeInterval,
        tolerance: TimeInterval,
        mode: RunLoop.Mode,
        onResume: (@MainActor () async -> Void)?,
        tick: @escaping @MainActor () async -> Void
    ) {
        self.interval = interval
        self.tolerance = tolerance
        self.mode = mode
        self.onResume = onResume
        self.tick = tick
    }

    isolated deinit {
        timer?.invalidate()
    }

    func apply(mayRun: Bool, resuming: Bool) {
        guard mayRun else {
            timer?.invalidate()
            timer = nil
            return
        }
        if resuming, let onResume {
            Task { await onResume() }
        }
        guard timer == nil else { return }
        // The main run loop runs the block on the main thread.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: mode)
        self.timer = timer
    }

    private func fire() {
        Task { await tick() }
    }
}
