//
//  main.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

SourcePIDCache.shared.start()
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
