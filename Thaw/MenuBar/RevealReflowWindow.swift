//
//  RevealReflowWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel

/// Whether a reveal or hide is still reflowing the bar, as opposed to a section left open. It sits inside
/// the kit's longer transition window, so it only holds the MenuBarAgent nudge off if that flag clears early.
@MainActor
final class RevealReflowWindow {
    /// Generous reflow window; observed settling takes tens of milliseconds.
    static nonisolated let settleWindow = Duration.milliseconds(500)

    /// A monotonic clock, so a wall-clock change can't open or close the window.
    private let now: () -> ContinuousClock.Instant
    private var lastTransition: ContinuousClock.Instant?
    private var subscription: AnyCancellable?

    init(now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    var isSettling: Bool {
        Self.isSettling(lastTransition: lastTransition, now: now())
    }

    static nonisolated func isSettling(lastTransition: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        guard let lastTransition else {
            return false
        }
        return lastTransition.duration(to: now) < settleWindow
    }

    func noteTransition() {
        lastTransition = now()
    }

    /// The first value is the current section, not a change. Changes are taken on the main actor as they
    /// are made, so the window opens at the change and not after whatever the main thread does next.
    func observe(_ revealedSection: AnyPublisher<MenuBarSectionName?, Never>) {
        subscription = revealedSection
            .dropFirst()
            .sink { [weak self] _ in self?.noteTransition() }
    }
}
