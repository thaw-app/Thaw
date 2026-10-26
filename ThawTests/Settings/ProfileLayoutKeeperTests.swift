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

    /// The settle wait returns at once without suspending, so once a test has
    /// seen a wait asked for, the task that asked has saved or given up.
    private let sleeps = RecordedSleeps()

    private func makeKeeper(
        target: @escaping @MainActor () -> UUID?,
        save: @escaping @MainActor (UUID) throws -> Void
    ) -> ProfileLayoutKeeper {
        ProfileLayoutKeeper(delay: .milliseconds(30), target: target, save: save, sleep: { [sleeps] in try sleeps.sleep(for: $0) })
    }

    @Test func aBurstOfChangesSavesOnce() async {
        let id = UUID()
        var saves = [UUID]()
        let keeper = makeKeeper(target: { id }, save: { saves.append($0) })
        keeper.noteUserLayoutChange()
        keeper.noteUserLayoutChange()
        await sleeps.waitForSleeps(2)
        #expect(sleeps.durations == [.milliseconds(30), .milliseconds(30)])
        #expect(saves == [id])
    }

    @Test func aProfileThatDoesntKeepChangesIsLeftAlone() {
        var saves = [UUID]()
        let keeper = makeKeeper(target: { nil }, save: { saves.append($0) })
        keeper.noteUserLayoutChange()
        // Nothing is scheduled, so no later save can come.
        #expect(sleeps.durations.isEmpty)
        #expect(saves.isEmpty)
    }

    /// The bar then shows the new profile's layout, which isn't the old one's.
    @Test func aSwitchBeforeTheSaveDropsIt() async {
        var active = UUID()
        var saves = [UUID]()
        let keeper = makeKeeper(target: { active }, save: { saves.append($0) })
        keeper.noteUserLayoutChange()
        active = UUID()
        await sleeps.waitForSleeps(1)
        #expect(saves.isEmpty)
    }

    @Test func aFailedSaveIsLoggedNotThrown() async {
        var attempts = 0
        let keeper = makeKeeper(target: { UUID(uuidString: "00000000-0000-0000-0000-000000000001") }, save: { _ in
            attempts += 1
            throw SaveFailure()
        })
        keeper.noteUserLayoutChange()
        await sleeps.waitForSleeps(1)
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
