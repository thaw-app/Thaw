//
//  DisplayProfileSwitchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The display change's resolveProfile step, which replaced ProfileManager's own screen observer.
@MainActor
@Suite("Display profile switch", .serialized, .scratchDefaults)
struct DisplayProfileSwitchTests {
    private let suites = ScratchSuites(prefix: "DisplayProfileSwitchTests")

    @Test("Docking applies the docked display's profile once")
    func appliesResolvedProfileOnce() {
        let target = RecordingTarget()
        let docked = target.addProfile(display: "DOCK")
        let profileSwitch = DisplayProfileSwitch(displayUUID: "BUILTIN")

        profileSwitch.settle(displayUUID: "DOCK", activeSpaceKey: nil, on: target)
        profileSwitch.settle(displayUUID: "DOCK", activeSpaceKey: nil, on: target)

        #expect(target.applied == [docked])
    }

    @Test("A change that leaves the bar where it was applies nothing")
    func sameDisplayAppliesNothing() {
        let target = RecordingTarget()
        target.addProfile(display: "DOCK")
        let profileSwitch = DisplayProfileSwitch(displayUUID: "DOCK")

        profileSwitch.settle(displayUUID: "DOCK", activeSpaceKey: nil, on: target)

        #expect(target.applied.isEmpty)
    }

    @Test("A change with no display owning the bar keeps the last one to compare against")
    func missingDisplayKeepsTheLastOne() {
        let target = RecordingTarget()
        target.addProfile(display: "BUILTIN")
        let profileSwitch = DisplayProfileSwitch(displayUUID: "BUILTIN")

        profileSwitch.settle(displayUUID: nil, activeSpaceKey: nil, on: target)
        profileSwitch.settle(displayUUID: "BUILTIN", activeSpaceKey: nil, on: target)

        #expect(target.applied.isEmpty)
        #expect(profileSwitch.lastDisplayUUID == "BUILTIN")
    }

    @Test("A display reached while a Space's profile wins is not switched to on the next change")
    func yieldedDisplayStillCounts() {
        let target = RecordingTarget()
        target.addProfile(display: "DOCK")
        target.addProfile(space: "space-2")
        let profileSwitch = DisplayProfileSwitch(displayUUID: "BUILTIN")

        profileSwitch.settle(displayUUID: "DOCK", activeSpaceKey: "space-2", on: target)
        profileSwitch.settle(displayUUID: "DOCK", activeSpaceKey: nil, on: target)

        #expect(target.applied.isEmpty)
    }

    @Test("The effect step leaves the profile alone when no profile names a display")
    func effectWithoutProfilesAppliesNothing() async throws {
        let directory = try ProfileTestDirectory.make(seeding: ["Default"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = ProfileManager(profilesDirectory: directory)
        let manager = MenuBarItemManager()
        let effects = MenuBarDisplayChangeEffects(itemManager: manager, repairs: manager.repairs, imageCache: MenuBarItemImageCache(), displaySettings: DisplaySettingsManager(), profiles: profiles, presentationMonitor: PresentationMonitor(), menuBarManager: MenuBarManager())

        await effects.resolveDisplayProfile()

        #expect(profiles.activeProfileID == nil)
        #expect(profiles.layoutTask == nil)
    }

    @Test("A switch started during a settle is the pending apply the settle's tail leaves to finish")
    func settleTailLeavesTheSwitchToFinish() throws {
        let defaults = try #require(suites.make())
        let settled = ProfileSettleReapply.Record(defaults: defaults)
        try ProfileTestDirectory.withManager(seeding: ["Laptop", "Docked"]) { profiles, _ in
            let laptop = try #require(profiles.profiles.first { $0.name == "Laptop" })
            let docked = try #require(profiles.profiles.first { $0.name == "Docked" })
            profiles.activeProfileID = laptop.id
            settled.lastSettledProfileID = laptop.id

            profiles.switchAutomatically(to: docked, on: AppState(), trigger: "a test display")
            // Stop the apply before it reaches the settings, spacing or layout; it has only been scheduled.
            profiles.layoutTask?.cancel()

            #expect(profiles.activeProfileID == docked.id)
            #expect(profiles.pendingApplyProfileID == docked.id)
            #expect(settled.settle(activeProfileID: profiles.activeProfileID, pendingApplyProfileID: profiles.pendingApplyProfileID) == .leavePendingApply)
        }
    }

    @Test("The profile manager no longer observes screen-parameter changes itself")
    func profilesHaveNoScreenObserver() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Thaw/Settings/Models/Profiles", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "the Profiles folder holds no Swift sources to scan")

        let observers = try files.filter { file in
            try String(contentsOf: file, encoding: .utf8).contains("didChangeScreenParametersNotification")
        }

        #expect(observers.map(\.lastPathComponent).isEmpty)
    }
}

@MainActor
private final class RecordingTarget: DisplayProfileTarget {
    private(set) var profiles: [ProfileMetadata] = []
    var activeProfileID: UUID?
    var focusFilterActive = false
    private(set) var applied: [UUID] = []

    @discardableResult
    func addProfile(display: String? = nil, space: String? = nil) -> UUID {
        let meta = ProfileMetadata(id: UUID(), name: "Profile", createdAt: .now, modifiedAt: .now, associatedDisplayUUID: display, associatedSpaceKey: space)
        profiles.append(meta)
        return meta.id
    }

    func applyResolvedDisplayProfile(id: UUID) {
        applied.append(id)
        activeProfileID = id
    }
}
