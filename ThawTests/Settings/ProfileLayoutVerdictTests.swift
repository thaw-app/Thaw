//
//  ProfileLayoutVerdictTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins the flag that tells a caller a profile's layout half never ran.
///
/// The settings half of a profile applies whatever happens, so without this
/// flag a user gets their appearance and spacing back while the item
/// arrangement, the part they built the profile for, is silently untouched.
/// applyProfileLayout reports that as false, ProfileManager records it,
/// and the Profiles pane and Simple Mode read it.
///
/// Two properties matter: a retry starts clean, and a superseded apply cannot
/// raise the flag over the apply that replaced it. The apply itself needs an
/// AppState and relaunches every menu bar app, so only the generation
/// bookkeeping runs here, against a ProfileManager in a temporary directory.
@MainActor
@Suite("Profile layout verdict", .serialized)
struct ProfileLayoutVerdictTests {
    /// Runs body with a manager whose profiles live in a throwaway
    /// directory, so nothing reads or rewrites the tester's real profiles.
    private func withManager<T>(_ body: (ProfileManager) throws -> T) throws -> T {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileLayoutVerdictTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try body(ProfileManager(profilesDirectory: tmp))
    }

    @Test("A manager that has applied nothing reports no failed layout")
    func freshManagerHasNoVerdict() throws {
        try withManager { manager in
            #expect(!manager.layoutDidNotRun, "Nothing has been applied, so nothing can have failed to apply")
            #expect(manager.layoutTask == nil)
        }
    }

    @Test("Opening a new apply clears the previous verdict")
    func newApplyClearsTheVerdict() throws {
        try withManager { manager in
            let first = manager.beginLayoutApply()
            manager.recordLayoutDidNotRun(generation: first)
            #expect(manager.layoutDidNotRun)

            _ = manager.beginLayoutApply()

            // The retry is the user's answer to the warning; it must not open
            // already showing it.
            #expect(!manager.layoutDidNotRun)
        }
    }

    @Test("A superseded apply cannot raise the flag over the one that replaced it")
    func staleApplyCannotRaiseTheFlag() throws {
        try withManager { manager in
            let superseded = manager.beginLayoutApply()
            let current = manager.beginLayoutApply()

            // The cancelled apply finishes late and reports its own failure.
            manager.recordLayoutDidNotRun(generation: superseded)
            #expect(!manager.layoutDidNotRun, "The apply that reported this is no longer the one on screen")

            manager.recordLayoutDidNotRun(generation: current)
            #expect(manager.layoutDidNotRun, "The apply in force still gets to report")
        }
    }

    @Test("Every apply gets its own generation")
    func generationsDoNotRepeat() throws {
        try withManager { manager in
            let generations = (0 ..< 8).map { _ in manager.beginLayoutApply() }
            #expect(Set(generations).count == generations.count)
        }
    }

    @Test("The apply in force can report more than once without changing the answer")
    func recordingIsIdempotent() throws {
        try withManager { manager in
            let generation = manager.beginLayoutApply()
            manager.recordLayoutDidNotRun(generation: generation)
            manager.recordLayoutDidNotRun(generation: generation)

            #expect(manager.layoutDidNotRun)
        }
    }

    @Test("An apply that runs never raises the flag")
    func silenceMeansItRan() throws {
        try withManager { manager in
            // A cancelled apply and an empty item order both report true
            // from applyProfileLayout, so the flag stays down: neither is a
            // layout that could not be written.
            _ = manager.beginLayoutApply()

            #expect(!manager.layoutDidNotRun)
        }
    }
}
