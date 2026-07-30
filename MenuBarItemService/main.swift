//
//  main.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Foundation

// Bound accessibility messaging before anything creates an element.
// `defaultMessagingTimeout` is applied in `UIElement.init`, so it only
// affects elements created after this point — and SourcePIDCache walks
// every status item owner's extras menu bar, so a single wedged app
// would otherwise stall the service for the system default of six
// seconds. Unlike the main app this is not user-overridable: the
// service has no access to `Defaults`.
UIElement.defaultMessagingTimeout = Float(SharedConstants.axMessagingTimeout)

// Diagnostic file logging is enabled by the main app via the
// configureLogging XPC request once it has opened its own log file.
// That way both processes append to a single shared file instead of
// each minting its own timestamped filename at startup. Anything
// logged before the configureLogging request arrives still reaches
// OSLog; only the on-disk diagnostic file is gated.

// SourcePIDCache is an actor; `start()` only wires up the Combine
// observer pipeline used for periodic cache cleanup, so it does not
// need to complete before the listener activates.
Task {
    await SourcePIDCache.shared.start()
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
