//
//  MenuBarGeometryRefresh.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics

/// Coalesces menu-bar geometry reads and publishes only the current request.
@MainActor
final class MenuBarGeometryRefresh {
    struct Snapshot: Sendable {
        var itemBounds: [CGRect]
        var chevronFrame: CGRect
        /// Only this display's live edge can update bounds mirrored onto another display.
        var sourceScreenFrame: CGRect?
        /// When the bounds were read. A change seen after this is newer than
        /// the snapshot.
        var readAt: ContinuousClock.Instant = .now
    }

    enum Event {
        case geometryChanged
        case visibilityChanged(isRevealed: Bool)
        case immediate

        var delay: Duration {
            switch self {
            case .geometryChanged: .milliseconds(200)
            case .visibilityChanged(isRevealed: false): .milliseconds(350)
            case .visibilityChanged(isRevealed: true), .immediate: .zero
            }
        }
    }

    private let read: @MainActor (ContinuousClock.Instant?) async -> Snapshot?
    private let publish: @MainActor (Snapshot) -> Void
    private let setPending: @MainActor (Bool) -> Void
    private let now: () -> ContinuousClock.Instant
    private let sleep: @MainActor (Duration) async throws -> Void
    private let slot = TaskSlot()
    private var deadline: ContinuousClock.Instant?
    private var revealSettleDeadline: ContinuousClock.Instant?
    private var minimumReadTime: ContinuousClock.Instant?

    init(
        read: @escaping @MainActor (ContinuousClock.Instant?) async -> Snapshot?,
        publish: @escaping @MainActor (Snapshot) -> Void,
        setPending: @escaping @MainActor (Bool) -> Void,
        now: @escaping () -> ContinuousClock.Instant = { .now },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.read = read
        self.publish = publish
        self.setPending = setPending
        self.now = now
        self.sleep = sleep
    }

    func schedule(_ event: Event) {
        let requestedAt = now()
        switch event {
        case .geometryChanged:
            // Frame publishers have already settled. Invalidate stale reads,
            // but do not make a reveal pay another full debounce interval.
            deadline = deadline ?? requestedAt.advanced(by: event.delay)
        case let .visibilityChanged(isRevealed):
            minimumReadTime = requestedAt
            revealSettleDeadline = isRevealed ? requestedAt.advanced(by: .milliseconds(350)) : nil
            deadline = requestedAt.advanced(by: event.delay)
        case .immediate:
            deadline = requestedAt.advanced(by: event.delay)
        }
        let minimumReadTime = minimumReadTime
        let revealSettleDeadline = revealSettleDeadline
        let deadline = deadline ?? requestedAt
        setPending(true)
        slot.replace { [weak self, sleep, read, now] ticket in
            var nextRead = deadline
            while true {
                do {
                    try await sleep(max(.zero, now().duration(to: nextRead)))
                } catch {
                    self?.finishIfCurrent(ticket)
                    return
                }
                guard !Task.isCancelled else { return }
                let snapshot = await read(minimumReadTime)
                guard let self, !Task.isCancelled, self.slot.isCurrent(ticket) else { return }
                if let snapshot, minimumReadTime.map({ snapshot.readAt >= $0 }) ?? true {
                    self.publish(snapshot)
                }
                guard let revealSettleDeadline, now() < revealSettleDeadline else {
                    self.finishIfCurrent(ticket)
                    return
                }
                // AX can answer before the reflow lands, so keep drawing
                // answers until the settle deadline.
                self.setPending(false)
                nextRead = min(now().advanced(by: .milliseconds(100)), revealSettleDeadline)
            }
        }
    }

    func cancel() {
        slot.cancel()
        deadline = nil
        revealSettleDeadline = nil
        minimumReadTime = nil
        setPending(false)
    }

    private func finishIfCurrent(_ ticket: TaskSlot.Ticket) {
        guard slot.isCurrent(ticket) else { return }
        deadline = nil
        revealSettleDeadline = nil
        setPending(false)
    }
}
