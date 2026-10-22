//
//  IconShadeReadSchedule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Decides when the overlay reads the shade macOS drew the icons in. One read runs
/// at a time, a bar change that arrives during a read gets a read of its own once
/// that one ends, and after a read that found nothing only a bar change reads again.
nonisolated struct IconShadeReadSchedule {
    private(set) var isReading = false
    private var readAfterCurrent = false
    private var lastReadFoundNothing = false

    /// Whether to start a read now, marking one as running when it does. force says
    /// the bar changed; hasShade says a shade is already known.
    mutating func shouldStart(force: Bool, hasShade: Bool) -> Bool {
        guard force || (!hasShade && !lastReadFoundNothing) else {
            return false
        }
        guard !isReading else {
            if force {
                readAfterCurrent = true
            }
            return false
        }
        isReading = true
        return true
    }

    /// Records the end of the running read. Returns true when a bar change came in
    /// during it, so the caller reads again.
    mutating func finish(found: Bool) -> Bool {
        let readAgain = readAfterCurrent
        isReading = false
        readAfterCurrent = false
        lastReadFoundNothing = !found
        return readAgain
    }

    /// Forgets everything, for a read that was cancelled before it ended.
    mutating func reset() {
        self = IconShadeReadSchedule()
    }
}
