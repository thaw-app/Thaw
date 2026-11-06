//
//  ProfileLayoutBehaviorSectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("The profile Layout section", .serialized)
struct ProfileLayoutBehaviorSectionTests {
    private func render(_ manager: ProfileManager, _ profile: ProfileMetadata) -> OffscreenRender<some View> {
        let view = ProfileLayoutBehaviorSection(profileManager: manager, profile: profile, errorMessage: .constant(nil))
            .frame(width: 520, height: 220)
        return OffscreenRender(view, size: CGSize(width: 520, height: 220))
    }

    @Test("Draws both switches and redraws when one changes")
    func drawsAndRedraws() async throws {
        try ProfileTestDirectory.withManager(seeding: ["Default"]) { manager, _ in
            let profile = try #require(manager.profiles.first)
            let render = render(manager, profile)
            let before = try render.pixels()
            #expect(before.contains { $0 != 0 })
            manager.setLayoutBehavior(keepsChanges: false, forProfileID: profile.id)
            #expect(manager.profiles.first?.keepsLayoutChanges == false)
        }
    }

    @Test("Each switch reads and saves its own setting")
    func switchesSave() throws {
        try ProfileTestDirectory.withManager(seeding: ["Default"]) { manager, tmp in
            let profile = try #require(manager.profiles.first)
            var error: String?
            let section = ProfileLayoutBehaviorSection(
                profileManager: manager,
                profile: profile,
                errorMessage: Binding { error } set: { error = $0 }
            )
            #expect(section.keepsChanges.wrappedValue)
            #expect(!section.reappliesAtLaunch.wrappedValue)

            section.keepsChanges.wrappedValue = false
            section.reappliesAtLaunch.wrappedValue = true

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.keepsLayoutChanges == false)
            #expect(reloaded.profiles.first?.reappliesAtLaunch == true)
            #expect(error == nil)
        }
    }
}
