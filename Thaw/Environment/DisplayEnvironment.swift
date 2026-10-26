//
//  DisplayEnvironment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel

/// The one observer of screen-parameter changes. A posting invalidates the snapshot at once; the
/// snapshot settles once two geometry reads agree, so a burst of postings publishes a single change.
@MainActor
final class DisplayEnvironment {
    let snapshot: EnvironmentSnapshot
    /// Sends at each screen-parameter posting, in the posting turn, for readers that drop state at once.
    let invalidations: AnyPublisher<Void, Never>
    /// Sends once per settle, ``EnvironmentChange/none`` included, for readers that rebuild on settled geometry.
    let settlements: AnyPublisher<EnvironmentChange, Never>

    private let invalidationSubject = PassthroughSubject<Void, Never>()
    private let settlementSubject = PassthroughSubject<EnvironmentChange, Never>()

    private let center: NotificationCenter
    private let timing: EnvironmentSettle.Timing
    private let read: @MainActor () -> DisplayArrangement
    private let sleep: @MainActor (Duration) async throws -> Void
    private let slot = TaskSlot()
    private var observer: NSObjectProtocol?
    private let diagLog = DiagLog(category: "DisplayEnvironment")

    init(
        center: NotificationCenter = .default,
        timing: EnvironmentSettle.Timing = EnvironmentSettle.Timing(),
        baseline: DisplayArrangement? = nil,
        read: @escaping @MainActor () -> DisplayArrangement = { .current },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.center = center
        self.timing = timing
        self.read = read
        self.sleep = sleep
        snapshot = EnvironmentSnapshot(arrangement: baseline ?? read())
        invalidations = invalidationSubject.eraseToAnyPublisher()
        settlements = settlementSubject.eraseToAnyPublisher()
    }

    /// Calling it again while observing does nothing.
    func start() {
        guard observer == nil else { return }
        // The main queue delivers in the posting turn, so readers see the invalidation before anything else runs.
        observer = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteScreenParametersChanged() }
        }
    }

    func stop() {
        if let observer {
            center.removeObserver(observer)
        }
        observer = nil
        slot.cancel()
    }

    /// Restarts the settle, so the quiet period runs from the newest posting.
    func noteScreenParametersChanged() {
        snapshot.invalidate()
        invalidationSubject.send()
        slot.replace { [weak self] ticket in
            await self?.settle(ticket)
        }
    }

    func waitUntilSettled() async {
        await slot.waitUntilFinished()
    }

    private func settle(_ ticket: TaskSlot.Ticket) async {
        var previous: DisplayArrangement?
        var reads = 0
        while true {
            do {
                try await sleep(EnvironmentSettle.delay(beforeRead: reads + 1, timing: timing))
            } catch {
                return
            }
            guard slot.isCurrent(ticket) else { return }
            let current = read()
            reads += 1
            if EnvironmentSettle.isSettled(previous: previous, current: current, reads: reads, timing: timing) {
                publish(current, reads: reads)
                return
            }
            previous = current
        }
    }

    private func publish(_ arrangement: DisplayArrangement, reads: Int) {
        let change = snapshot.settle(on: arrangement)
        settlementSubject.send(change)
        if change == .none {
            diagLog.debug("Display environment settled unchanged at generation \(snapshot.generation) after \(reads) reads")
        } else {
            diagLog.info("Display environment generation \(snapshot.generation) settled: \(change.rawValue), \(arrangement.frames.count) displays, \(reads) reads")
        }
    }
}
