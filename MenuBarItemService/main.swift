//
//  main.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// Diagnostic file logging is enabled by the main app via the
// configureLogging XPC request once it has opened its own log file.
// That way both processes append to a single shared file instead of
// each minting its own timestamped filename at startup. Anything
// logged before the configureLogging request arrives still reaches
// OSLog; only the on-disk diagnostic file is gated.

// The SkyLight source-PID cache is a macOS <=26 role: on macOS 27 menu-bar
// hosting moved to MenuBarAgent and the SkyLight source-PID path is retired, so
// its observers are not started there. The listener's macOS 27 role is
// out-of-process Accessibility reads (`menuBarItemSnapshots`), which need no
// cache. Branching the two roles avoids running obsolete SkyLight work on 27.
if #unavailable(macOS 27) {
    SourcePIDCache.shared.start()
}
Listener.shared.activate()

// Run the RunLoop in a loop that drains an autoreleasepool every
// 60 seconds. Without NSApplication there is no automatic pool
// management, so ObjC/CF objects autoreleased on the main thread
// (Combine pipeline, Timer callbacks, KVO notifications) would
// accumulate indefinitely.
while true {
    autoreleasepool {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 60))
    }
}
