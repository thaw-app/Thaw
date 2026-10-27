//
//  TimedRehideStep.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// What the timed rehide countdown does when a reveal starts or the pointer moves.
nonisolated enum TimedRehideStep: Equatable {
    case start
    case keep
    case cancel

    /// The countdown runs only while the pointer is outside both bars, one at a time.
    static func next(pointerInBar: Bool, countdownRunning: Bool) -> Self {
        if pointerInBar {
            return .cancel
        }
        return countdownRunning ? .keep : .start
    }
}
