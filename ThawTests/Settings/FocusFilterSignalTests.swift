//
//  FocusFilterSignalTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents
import Foundation
import Testing
@testable import Thaw

/// Any process can post the Focus filter notifications, so only the system's Focus state may switch profiles.
@MainActor
@Suite("Focus filter signal", .serialized)
struct FocusFilterSignalTests {
    /// Stands in for the system's Focus filter state.
    private final class SystemFocus {
        var profileID: String?
    }

    private static func signal(reading focus: SystemFocus) -> FocusFilterSignal {
        FocusFilterSignal { focus.profileID }
    }

    @Test("An active system Focus profile applies")
    func systemProfileApplies() {
        let id = UUID().uuidString
        #expect(FocusFilterSignal.action(systemProfileID: id, focusFilterActive: false) == .apply(profileID: id))
        #expect(FocusFilterSignal.action(systemProfileID: id, focusFilterActive: true) == .apply(profileID: id))
    }

    @Test("Focus reverts only when the system reports no Focus profile")
    func revertsOnlyWithoutSystemProfile() {
        #expect(FocusFilterSignal.action(systemProfileID: nil, focusFilterActive: true) == .revert)
        #expect(FocusFilterSignal.action(systemProfileID: nil, focusFilterActive: false) == .ignore)
    }

    @Test("A malformed profile ID from the system counts as no profile")
    func malformedSystemProfileIsIgnored() {
        #expect(FocusFilterSignal.action(systemProfileID: "not-a-uuid", focusFilterActive: false) == .ignore)
    }

    @Test("A forged deactivation leaves the Focus profile in place")
    func forgedDeactivationIsIgnored() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["Work"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let id = try #require(manager.profiles.first?.id)
        let focus = SystemFocus()
        focus.profileID = id.uuidString
        manager.focusFilterSignal = Self.signal(reading: focus)
        manager.activeProfileID = id

        await manager.handleFocusFilterSignal()
        #expect(manager.focusFilterActive)

        // A deactivation notification while the system still reports the Focus profile changes nothing.
        await manager.handleFocusFilterSignal()
        #expect(manager.focusFilterActive)
        #expect(manager.activeProfileID == id)

        focus.profileID = nil
        await manager.handleFocusFilterSignal()
        #expect(!manager.focusFilterActive)
    }

    @Test("A forged activation with no system Focus profile changes nothing")
    func forgedActivationIsIgnored() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["Work"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        manager.focusFilterSignal = Self.signal(reading: SystemFocus())

        await manager.handleFocusFilterSignal()
        #expect(!manager.focusFilterActive)
        #expect(manager.activeProfileID == nil)
    }

    private struct ReadFailure: Error {}

    @Test("A failed read of the system's Focus state leaves an active Focus profile in place")
    func failedReadIsIgnored() async {
        let failing = FocusFilterSignal { throw ReadFailure() }
        #expect(await failing.action(focusFilterActive: true) == .ignore)
        #expect(await failing.action(focusFilterActive: false) == .ignore)
    }

    @Test("No active Focus filter reads as no profile, and other errors stay failures")
    func notFoundMeansNoProfile() async throws {
        let none = try await FocusFilterSignal.profileID { throw SetFocusFilterIntentError.notFound }
        #expect(none == nil)
        let id = UUID().uuidString
        #expect(try await FocusFilterSignal.profileID { id } == id)
        await #expect(throws: ReadFailure.self) {
            try await FocusFilterSignal.profileID { throw ReadFailure() }
        }
    }
}
