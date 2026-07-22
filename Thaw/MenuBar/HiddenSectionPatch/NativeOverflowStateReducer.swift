//
//  NativeOverflowStateReducer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Stabilizes the native overflow signal independently for each display.
/// Unavailable AX reads preserve the last state instead of looking like a
/// negative observation.
nonisolated struct NativeOverflowStateReducer: Sendable {
    private nonisolated struct DisplayState: Sendable {
        var isActive = false
        var candidate: Bool?
        var candidateCount = 0
    }

    let presentThreshold: Int
    let absentThreshold: Int
    private var states = [CGDirectDisplayID: DisplayState]()

    init(presentThreshold: Int = 2, absentThreshold: Int = 3) {
        self.presentThreshold = max(1, presentThreshold)
        self.absentThreshold = max(1, absentThreshold)
    }

    func isActive(on displayID: CGDirectDisplayID) -> Bool {
        states[displayID]?.isActive ?? false
    }

    /// Drops all tracked state for a display, e.g. because it is no longer
    /// connected or no longer the active menu-bar display and so will not be
    /// probed again until it earns that status back. A later reactivation on
    /// that display starts a fresh debounce window instead of resuming a
    /// stale candidate count from before the display went unobserved.
    mutating func forget(_ displayID: CGDirectDisplayID) {
        states.removeValue(forKey: displayID)
    }

    /// Consumes an observation and returns the new stable state only when it
    /// changes. Repeated stable observations are no-ops.
    mutating func consume(
        _ observation: NativeOverflowObservation,
        on displayID: CGDirectDisplayID
    ) -> Bool? {
        let observedActive: Bool
        switch observation {
        case .unavailable:
            return nil
        case .absent:
            observedActive = false
        case .present:
            observedActive = true
        }

        var state = states[displayID] ?? DisplayState()
        guard observedActive != state.isActive else {
            state.candidate = nil
            state.candidateCount = 0
            states[displayID] = state
            return nil
        }

        if state.candidate == observedActive {
            state.candidateCount += 1
        } else {
            state.candidate = observedActive
            state.candidateCount = 1
        }

        let threshold = observedActive ? presentThreshold : absentThreshold
        guard state.candidateCount >= threshold else {
            states[displayID] = state
            return nil
        }

        state.isActive = observedActive
        state.candidate = nil
        state.candidateCount = 0
        states[displayID] = state
        return observedActive
    }
}
