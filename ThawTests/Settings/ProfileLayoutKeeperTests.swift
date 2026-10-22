//
//  ProfileLayoutKeeperTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Layout changes are saved into the active profile", .timeLimit(.minutes(1)))
struct ProfileLayoutKeeperTests {
    private struct SaveFailure: Error {}

    private func waitForSaves(_ saves: () -> [UUID], count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while saves().count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(80))
    }

    @Test func aBurstOfChangesSavesOnce() async throws {
        let id = UUID()
        var saves = [UUID]()
        let keeper = ProfileLayoutKeeper(delay: .milliseconds(30), target: { id }, save: { saves.append($0) })
        keeper.noteUserLayoutChange()
        keeper.noteUserLayoutChange()
        try await waitForSaves({ saves }, count: 1)
        #expect(saves == [id])
    }

    @Test func aProfileThatDoesntKeepChangesIsLeftAlone() async throws {
        var saves = [UUID]()
        let keeper = ProfileLayoutKeeper(delay: .milliseconds(30), target: { nil }, save: { saves.append($0) })
        keeper.noteUserLayoutChange()
        try await Task.sleep(for: .milliseconds(150))
        #expect(saves.isEmpty)
    }

    /// The bar then shows the new profile's layout, which isn't the old one's.
    @Test func aSwitchBeforeTheSaveDropsIt() async throws {
        var active = UUID()
        var saves = [UUID]()
        let keeper = ProfileLayoutKeeper(delay: .milliseconds(30), target: { active }, save: { saves.append($0) })
        keeper.noteUserLayoutChange()
        active = UUID()
        try await Task.sleep(for: .milliseconds(150))
        #expect(saves.isEmpty)
    }

    @Test func aFailedSaveIsLoggedNotThrown() async throws {
        var attempts = 0
        let keeper = ProfileLayoutKeeper(delay: .milliseconds(30), target: { UUID(uuidString: "00000000-0000-0000-0000-000000000001") }) { _ in
            attempts += 1
            throw SaveFailure()
        }
        keeper.noteUserLayoutChange()
        let deadline = ContinuousClock.now + .seconds(3)
        while attempts == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(attempts == 1)
    }

    @Test func theAppKeeperSavesNothingWithoutAnActiveProfile() async throws {
        let appState = AppState()
        let keeper = ProfileLayoutKeeper(
            profileManager: appState.profileManager,
            itemManager: appState.itemManager,
            groupManager: appState.itemGroupManager
        )
        // No profile is active in a fresh app state, so nothing is saved.
        keeper.noteUserLayoutChange()
        #expect(appState.profileManager.activeProfileID == nil)
    }

    @Test func dragsAndLayoutEditsReportAChange() {
        let repairs = RepairOrchestrator()
        var reports = 0
        repairs.onUserLayoutChange = { reports += 1 }
        repairs.request(.structuralNormalization, cause: .userDragEnded)
        repairs.request(.authoredOrderApply, cause: .userEdit)
        repairs.request(.structuralNormalization, cause: .settled)
        #expect(reports == 2)
    }
}
