//
//  IconShadeReadSchedule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Decides when the overlay reads the shade macOS drew the icons in. One read runs
/// at a time, a bar change that arrives during a read gets a read of its own once
/// that one ends, and after a read that found nothing only a bar change reads again.
struct IconShadeReadSchedule {
    private(set) var isReading = false
    private var readOwed = false
    private var lastReadFoundNothing = false
    private var lastBar: MenuBarAverageColorInfo?

    /// Whether to start a read now, marking one as running when it does. bar is this
    /// display's average colour, and a change from the one last asked about means
    /// macOS may have flipped the icons. hasShade says a shade is already known.
    mutating func shouldStart(bar: MenuBarAverageColorInfo?, hasShade: Bool) -> Bool {
        let barChanged = bar != lastBar
        lastBar = bar
        readOwed = readOwed || barChanged
        guard readOwed || (!hasShade && !lastReadFoundNothing), !isReading else {
            return false
        }
        isReading = true
        readOwed = false
        return true
    }

    /// Records the end of the running read. Returns true when a bar change came in
    /// during it, so the caller asks again and the next start reads.
    mutating func finish(found: Bool) -> Bool {
        isReading = false
        lastReadFoundNothing = !found
        return readOwed
    }

    /// Forgets everything, for a read that was cancelled before it ended.
    mutating func reset() {
        self = IconShadeReadSchedule()
    }
}
