//
//  RevealReflowWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel

/// Whether a reveal or hide is still reflowing the bar, as opposed to a section simply left open.
///
/// The window opens each time the revealed section changes and lasts ``settleWindow``. It sits
/// inside the kit's own reveal/hide transition window, which opens at the same change and lasts
/// longer, so it only holds the MenuBarAgent nudge off if that flag is cleared early.
@MainActor
final class RevealReflowWindow {
    /// Generous reflow window; observed settling takes tens of milliseconds.
    static nonisolated let settleWindow: TimeInterval = 0.5

    private let now: () -> Date
    private var lastTransition: Date?
    private var subscription: AnyCancellable?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    var isSettling: Bool {
        Self.isSettling(lastTransition: lastTransition, now: now())
    }

    static nonisolated func isSettling(lastTransition: Date?, now: Date) -> Bool {
        guard let lastTransition else {
            return false
        }
        return now.timeIntervalSince(lastTransition) < settleWindow
    }

    func noteTransition() {
        lastTransition = now()
    }

    /// Follows the revealed section. The first value is the section revealed when the subscription
    /// starts, not a change. Each change is taken as it is made, on the main actor, so the window
    /// opens at the change and not after whatever the main thread does next.
    func observe(_ revealedSection: AnyPublisher<MenuBarSectionName?, Never>) {
        subscription = revealedSection
            .dropFirst()
            .sink { [weak self] _ in self?.noteTransition() }
    }
}
