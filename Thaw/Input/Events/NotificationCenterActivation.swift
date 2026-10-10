//
//  NotificationCenterActivation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

@MainActor
final class NotificationCenterActivation {
    enum Request: Equatable {
        case clock(CGPoint)
        case shortcut(SystemNotificationCenterHotkey)
    }

    enum Lease {
        case acquired
        case notRequired
        case unavailable
    }

    private let activate: (Request) async -> Void
    private let panelPresenting: () -> Bool
    private let now: () -> Date
    private var pending: [Request] = []
    private var worker: Task<Void, Never>?
    private let restoreSlot = TaskSlot()
    private var restoreLease: (() -> Void)?
    private var leaseAcquiredAt: Date?
    private var restorationPause: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// How long a release must be held before the replayed activation posts,
    /// counted from lease acquisition (the physical press when prepared at mouse-down).
    static let minimumReleaseAge: TimeInterval = 0.06

    /// How often the restore task checks for the panel; every tick of lag
    /// keeps the hidden items in the bar.
    static let pollInterval = Duration.milliseconds(20)

    /// Longest the release survives a panel that never presents.
    static let presentationTimeout = Duration.seconds(1.2)

    /// Held after the panel appears, so the slide-out clears the bar before
    /// concealment snaps back. The hidden items are in the bar meanwhile.
    static let escapeGrace = Duration.milliseconds(150)

    /// Held after the panel disappears on a close gesture, so the slide-in
    /// finishes before the bar returns.
    static let dismissGrace = Duration.milliseconds(120)

    var isBusy: Bool {
        worker != nil || restoreLease != nil
    }

    init(
        activate: @escaping (Request) async -> Void,
        panelPresenting: @escaping () -> Bool = NotificationCenterActivation.systemPanelPresenting,
        now: @escaping () -> Date = { Date() }
    ) {
        self.activate = activate
        self.panelPresenting = panelPresenting
        self.now = now
    }

    /// Notification Center is presenting when its panel window is on-screen.
    /// The flag flips within ~100 ms of open and close, inside one poll interval.
    private static nonisolated func systemPanelPresenting() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Notification Center"
        }
    }

    func enqueue(_ request: Request) {
        pending.append(request)
        if restoreLease != nil {
            scheduleRestoration(panelWasPresentingAtStart: panelPresenting())
        }
        startIfNeeded()
    }

    /// Acquires the release lease at mouse-down so mouse-up needs no added settle.
    /// A press that never completes restores itself at the usual bound.
    func prepareLease(
        begin: @escaping () -> Lease,
        restore: @escaping () -> Void
    ) {
        guard restoreLease == nil else {
            scheduleRestoration(panelWasPresentingAtStart: panelPresenting())
            return
        }
        switch begin() {
        case .acquired:
            restoreLease = restore
            leaseAcquiredAt = now()
            scheduleRestoration(panelWasPresentingAtStart: panelPresenting())
        case .notRequired, .unavailable:
            break
        }
    }

    func cancel() {
        pending.removeAll()
        worker?.cancel()
        restoreAssertion()
    }

    func waitUntilIdle() async {
        while worker != nil || restoreSlot.isRunning {
            if let worker {
                await worker.value
            } else {
                await restoreSlot.waitUntilFinished()
            }
        }
    }

    isolated deinit {
        restoreSlot.cancel()
        restoreLease?()
    }

    private func startIfNeeded() {
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            defer {
                worker = nil
                startIfNeeded()
            }
            while !Task.isCancelled, !pending.isEmpty {
                let request = pending.removeFirst()
                await activate(request)
            }
        }
    }

    /// Keeps the assertion released until the panel is up, plus a grace for the
    /// slide-out. The restore polls the panel rather than using a fixed delay.
    func replay(
        begin: () -> Lease,
        restore: @escaping () -> Void,
        send: () -> Void,
        pause: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        guard !Task.isCancelled else { return }
        restoreSlot.cancel()
        var acquired = false
        if restoreLease == nil {
            switch begin() {
            case .acquired:
                restoreLease = restore
                acquired = true
            case .notRequired:
                break
            case .unavailable:
                return
            }
        }
        restorationPause = pause
        do {
            let panelWasPresentingAtStart = panelPresenting()
            if acquired {
                leaseAcquiredAt = now()
                // No press to age through, so keep the full release settle.
                // Shorter settles were never shown safe for input-tap readiness.
                try await pause(.milliseconds(60))
            } else if let acquiredAt = leaseAcquiredAt {
                // Prepared at mouse-down: wait out the rest of the minimum age,
                // usually zero after a human click.
                let age = now().timeIntervalSince(acquiredAt)
                let remaining = Self.minimumReleaseAge - age
                if remaining > 0 {
                    try await pause(.milliseconds(Int((remaining * 1000).rounded())))
                }
            }
            try Task.checkCancellation()
            send()
            if restoreLease != nil {
                scheduleRestoration(panelWasPresentingAtStart: panelWasPresentingAtStart)
            }
        } catch {
            restoreAssertion()
        }
    }

    private func scheduleRestoration(panelWasPresentingAtStart: Bool) {
        let pause = restorationPause
        let presenting = panelPresenting
        restoreSlot.replace { [weak self] ticket in
            // Opening: wait for the panel, then grace the slide-out. Closing:
            // restore as soon as it clears. Both are bounded by the timeout.
            let waitingForDismissal = panelWasPresentingAtStart
            var settled = false
            var waited = Duration.zero
            while !Task.isCancelled {
                let present = presenting()
                if waitingForDismissal ? !present : present {
                    settled = true
                    break
                }
                guard waited < Self.presentationTimeout else { break }
                do {
                    try await pause(Self.pollInterval)
                } catch {
                    break
                }
                waited += Self.pollInterval
            }
            if settled {
                try? await pause(waitingForDismissal ? Self.dismissGrace : Self.escapeGrace)
            }
            guard let self, self.restoreSlot.isCurrent(ticket) else { return }
            self.restoreAssertion()
        }
    }

    private func restoreAssertion() {
        restoreSlot.cancel()
        let restore = restoreLease
        restoreLease = nil
        leaseAcquiredAt = nil
        restore?()
    }
}
