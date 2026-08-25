//
//  ApplicationTermination.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Requests app termination after event-tracking and presentation run loops
/// unwind so `applicationShouldTerminate` can complete its asynchronous cleanup.
@MainActor
enum ApplicationTermination {
    typealias Scheduler = (@escaping @MainActor () -> Void) -> Void

    static func request() {
        request(
            schedule: scheduleOnDefaultRunLoop,
            terminate: terminateApplication
        )
    }

    static func request(
        schedule: Scheduler,
        terminate: @escaping @MainActor () -> Void
    ) {
        schedule(terminate)
    }

    private static func scheduleOnDefaultRunLoop(
        _ action: @escaping @MainActor () -> Void
    ) {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                action()
            }
        }
    }

    private static func terminateApplication() {
        NSApp.terminate(nil)
    }
}
