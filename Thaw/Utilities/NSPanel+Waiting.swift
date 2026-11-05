//
//  NSPanel+Waiting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI
import ThawCapture

extension NSPanel {
    /// Waits until the panel is no longer visible, or until timeout elapses.
    /// Observes isVisible with KVO rather than polling the main thread.
    @MainActor
    func waitUntilClosed(timeout: Duration = .milliseconds(200)) async {
        guard isVisible else { return }

        // The wait observes cancellation, so the timeout ends it.
        try? await Task<Void, any Error>.withTimeout(timeout) {
            await self.waitForInvisibleWithKVO()
        }
    }

    @MainActor
    private func waitForInvisibleWithKVO() async {
        // The values iterator ends when the task is cancelled.
        for await visible in publisher(for: \.isVisible).values where !visible {
            return
        }
    }
}
