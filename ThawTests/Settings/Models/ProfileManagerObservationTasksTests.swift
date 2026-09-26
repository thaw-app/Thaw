//
//  ProfileManagerObservationTasksTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `ProfileManager.startObservationTasks()`, the observation wiring
/// `performSetup(with:)` runs, without a live `AppState`.
///
/// Every observer task starts, and a repeated setup replaces the previous
/// tasks instead of leaking them. Stream mechanics are covered by
/// `DebouncedNotificationTaskTests`.
@Suite("Profile manager observation tasks")
@MainActor
struct ProfileManagerObservationTasksTests {
    private func withManager(_ body: (ProfileManager) throws -> Void) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileManagerObservationTasksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try body(ProfileManager(profilesDirectory: tmp))
    }

    @Test("Starting observation starts all three tasks")
    func startingObservationStartsAllThreeTasks() throws {
        try withManager { manager in
            manager.startObservationTasks()

            #expect(manager.screenParametersTask != nil)
            #expect(manager.focusFilterActivatedTask != nil)
            #expect(manager.focusFilterDeactivatedTask != nil)
        }
    }

    @Test("A repeated setup cancels the previous tasks")
    func repeatedSetupCancelsThePreviousTasks() throws {
        try withManager { manager in
            manager.startObservationTasks()
            let first = try #require(manager.screenParametersTask)
            let activated = try #require(manager.focusFilterActivatedTask)
            let deactivated = try #require(manager.focusFilterDeactivatedTask)

            manager.startObservationTasks()

            #expect(first.isCancelled)
            #expect(activated.isCancelled)
            #expect(deactivated.isCancelled)
            #expect(manager.screenParametersTask != nil)
        }
    }
}
