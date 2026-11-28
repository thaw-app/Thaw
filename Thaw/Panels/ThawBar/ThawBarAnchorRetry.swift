//
//  ThawBarAnchorRetry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// One later look for the Thaw icon when an open found no usable frame for it, so a frame that
/// arrives a moment late doesn't leave the bar at the right edge.
@MainActor
final class ThawBarAnchorRetry {
    /// Long enough for the icon to report its frame after the click that opened the bar.
    static nonisolated let delay = Duration.milliseconds(100)

    private let slot = TaskSlot()
    private var opening: ContinuousClock.Instant?

    /// Runs place after the delay, once per open and only when the bar belongs under the icon.
    func schedule(for location: ThawBarLocation, opening: ContinuousClock.Instant?, _ place: @escaping @MainActor () -> Void) {
        guard location == .thawIcon, opening != self.opening else { return }
        self.opening = opening
        slot.replace { [weak self] ticket in
            try? await Task.sleep(for: Self.delay)
            guard self?.slot.isCurrent(ticket) == true else { return }
            place()
        }
    }

    func cancel() {
        slot.cancel()
    }

    func waitUntilFinished() async {
        await slot.waitUntilFinished()
    }
}

extension ThawBarPanel {
    /// Reads the icon's frame again and places the bar by it, while the bar is still open on that screen.
    /// A retry left from an opening on another display leaves the bar where the newer opening put it.
    func retryIconAnchor(on screen: NSScreen) {
        guard currentSection != nil, self.screen == screen else { return }
        staleAnchorWindowID = nil
        updateOrigin(for: screen)
    }
}
