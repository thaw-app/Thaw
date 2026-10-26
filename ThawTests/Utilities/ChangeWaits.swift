//
//  ChangeWaits.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation

/// Returns once condition holds, checking it again each time publisher sends rather than polling
/// against a deadline. The publisher must not send its current value on subscription, so pass a
/// @Published projection with dropFirst(). It sends before the property changes, and the check runs
/// on the main actor once the change has landed.
@MainActor
func waitUntil<Changes: Publisher>(_ condition: () -> Bool, wakingOn changes: Changes) async where Changes.Failure == Never {
    var wake: AnyCancellable?
    while !condition() {
        await withCheckedContinuation { woken in
            wake = changes.first().sink { _ in woken.resume() }
        }
    }
    wake?.cancel()
}

/// Returns once condition holds, checking it again at each change to what observed reads rather
/// than polling against a deadline.
@MainActor
func waitUntil(_ condition: () -> Bool, tracking observed: () -> Void) async {
    while !condition() {
        await withCheckedContinuation { changed in
            withObservationTracking(observed) {
                changed.resume()
            }
        }
    }
}
