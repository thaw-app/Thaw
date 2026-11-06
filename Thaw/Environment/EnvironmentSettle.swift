//
//  EnvironmentSettle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// When a run of geometry reads after a screen change counts as settled.
nonisolated enum EnvironmentSettle {
    struct Timing: Sendable {
        /// How long the postings must stay quiet before the first read.
        var quiet: Duration = .milliseconds(300)
        /// The wait before each read that confirms the one before it.
        var confirm: Duration = .milliseconds(150)
        /// The most reads one settle takes. The last one wins when they never agree.
        var maxReads = 6
    }

    static func isSettled(previous: DisplayArrangement?, current: DisplayArrangement, reads: Int, timing: Timing) -> Bool {
        previous == current || reads >= timing.maxReads
    }

    /// Reads are counted from 1.
    static func delay(beforeRead read: Int, timing: Timing) -> Duration {
        read <= 1 ? timing.quiet : timing.confirm
    }
}
