//
//  main.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Foundation

// Bound AX messaging before any element exists (`UIElement.init` applies it),
// or one wedged app stalls the scan for the six-second system default.
// Not user-overridable: the service can't read `Defaults`.
UIElement.defaultMessagingTimeout = Float(SharedConstants.axMessagingTimeout)

// The app enables file logging via configureLogging so both processes share
// one file. Earlier messages still reach OSLog.

// SourcePIDCache is an actor; `start()` only wires up the Combine
// observer pipeline used for periodic cache cleanup, so it does not
// need to complete before the listener activates.
Task {
    await SourcePIDCache.shared.start()
}

Listener.shared.activate()

// Drain an autoreleasepool every 60 seconds. Without NSApplication nothing
// else does, and main-thread autoreleased objects would accumulate forever.
while true {
    autoreleasepool {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 60))
    }
}
