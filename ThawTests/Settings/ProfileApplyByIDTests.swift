//
//  ProfileApplyByIDTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Applying a profile by identifier, as the Shortcuts intent and
/// thaw://apply-profile do. Profiles live in a throwaway directory.
@MainActor
@Suite("Profile apply by identifier", .serialized)
struct ProfileApplyByIDTests {
    private func withManager(_ body: (ProfileManager, URL) async throws -> Void) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileApplyByIDTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await body(ProfileManager(profilesDirectory: tmp), tmp)
    }

    @Test("A profile with no file fails to apply and leaves the active profile alone")
    func missingProfileChangesNothing() async throws {
        try await withManager { manager, _ in
            let active = UUID()
            manager.activeProfileID = active

            await #expect(throws: (any Error).self) {
                try await manager.applyProfileAwaitingLayout(id: UUID(), to: AppState())
            }

            #expect(manager.activeProfileID == active)
            #expect(manager.layoutTask == nil, "Nothing was loaded, so no layout may have started")
            #expect(!manager.layoutDidNotRun)
        }
    }

    @Test("A profile file that cannot be decoded fails the same way")
    func unreadableProfileChangesNothing() async throws {
        try await withManager { manager, directory in
            let id = UUID()
            try Data("not a profile".utf8).write(to: directory.appendingPathComponent("\(id.uuidString).json"))

            await #expect(throws: (any Error).self) {
                try await manager.applyProfileAwaitingLayout(id: id, to: AppState())
            }

            #expect(manager.activeProfileID == nil)
            #expect(manager.layoutTask == nil)
        }
    }
}
