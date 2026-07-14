//
//  SimpleSemaphoreTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class SimpleSemaphoreTests: XCTestCase {
    func testCancellingQueuedWaitDoesNotConsumeNextSignal() async throws {
        let semaphore = SimpleSemaphore(value: 1)
        try await semaphore.wait()

        let queuedWait = Task {
            try await semaphore.wait(timeout: .seconds(5))
        }
        await Task.yield()
        queuedWait.cancel()

        // Signal before detached cancellation cleanup could run. The signal
        // must not hand its permit to the cancelled waiter.
        await semaphore.signal()

        do {
            _ = try await queuedWait.value
            XCTFail("Cancelled waiter unexpectedly acquired a permit")
        } catch is CancellationError {
            // Expected.
        }

        try await semaphore.wait(timeout: .milliseconds(100))
    }
}
