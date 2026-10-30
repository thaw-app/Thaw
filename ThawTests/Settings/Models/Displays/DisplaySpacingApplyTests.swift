//
//  DisplaySpacingApplyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Spacing applies driven through a stand-in host: nothing is written to disk, no app is
/// relaunched, no settling starts and no alert is shown. Settings live in a throwaway suite.
@MainActor
@Suite("Display spacing apply", .serialized, .scratchDefaults)
struct DisplaySpacingApplyTests {
    private struct ApplyFailed: LocalizedError {
        var errorDescription: String? {
            "disk full"
        }
    }

    /// Records what the manager asked of the host.
    @MainActor
    private final class Recorder {
        var applies: [(forceRelaunch: Bool, relaunchApps: Bool)] = []
        var started: [(reason: String, expected: Set<String>)] = []
        var cancelled: [String] = []
        var reapplied = 0
        var prompts = 0
        var outcome = MenuBarItemSpacingManager.ApplyOutcome(didRelaunch: false, recoveredBundleIDs: [], failedAppNames: [])
        var error: Error?
        var approves = true
        /// Wait here before answering, so a test can act while an apply is in flight.
        var gate: CheckedContinuation<Void, Never>?
        var holdsApply = false

        var finished: Bool {
            !cancelled.isEmpty || reapplied > 0
        }
    }

    private let recorder = Recorder()
    private let spacingManager = MenuBarItemSpacingManager()

    private func makeManager(confirms: Bool = false) throws -> DisplaySettingsManager {
        try Defaults.set(JSONEncoder().encode([String: DisplayThawBarConfiguration]()), forKey: .displayThawBarConfigurations)
        let manager = DisplaySettingsManager()
        let recorder = recorder
        let prompt: @MainActor () -> Bool = {
            recorder.prompts += 1
            return recorder.approves
        }
        let apply: @MainActor (Bool, Bool) async throws -> MenuBarItemSpacingManager.ApplyOutcome = { forceRelaunch, relaunchApps in
            recorder.applies.append((forceRelaunch, relaunchApps))
            if recorder.holdsApply {
                await withCheckedContinuation { recorder.gate = $0 }
            }
            if let error = recorder.error {
                throw error
            }
            return recorder.outcome
        }
        manager.spacingHost = DisplaySpacingApplyHost(
            spacingManager: spacingManager,
            applyOffset: apply,
            startSettling: { recorder.started.append(($0, $1)) },
            cancelSettling: { recorder.cancelled.append($0) },
            reapplyActiveProfile: { recorder.reapplied += 1 },
            confirmRelaunch: confirms ? prompt : nil
        )
        return manager
    }

    private func activeUUID() throws -> String {
        try #require(DisplaySettingsManager().activeMenuBarDisplayUUID, "the test host has a display that owns the menu bar")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
    }

    private func setOffset(_ offset: Double, on manager: DisplaySettingsManager, uuid: String) {
        manager.configurations = [uuid: DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(offset)]
    }

    @Test("Editing the active display's spacing applies it and relaunches, then ends the preflight when nothing changed")
    func configurationChangeAppliesActiveSpacing() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager()

        setOffset(3, on: manager, uuid: uuid)
        await waitUntil { recorder.finished }

        #expect(spacingManager.offset == 3)
        #expect(manager.lastAppliedActiveDisplayUUID == uuid)
        #expect(recorder.applies.map(\.forceRelaunch) == [false])
        #expect(recorder.applies.map(\.relaunchApps) == [true], "an edit is a spacing change, so apps relaunch")
        #expect(recorder.started.map(\.reason) == ["spacingRelaunch:configurationsChanged:preflight"])
        #expect(recorder.cancelled == ["spacingRelaunch:configurationsChanged:noOp"])
        #expect(recorder.reapplied == 0)
        #expect(manager.lastSpacingApplyFailure == nil)
        #expect(!manager.isReapplyingSpacing)
    }

    @Test("A relaunch wave waits for the relaunched apps, reapplies the active profile and names the apps that failed")
    func relaunchWaveSettlesAndReapplies() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager()
        recorder.outcome = .init(didRelaunch: true, recoveredBundleIDs: ["com.example.one"], failedAppNames: ["Alpha", "Beta"])

        setOffset(2, on: manager, uuid: uuid)
        await waitUntil { recorder.finished }

        #expect(recorder.reapplied == 1)
        #expect(recorder.cancelled.isEmpty)
        #expect(recorder.started.map(\.reason) == ["spacingRelaunch:configurationsChanged:preflight", "spacingRelaunch:configurationsChanged"])
        #expect(recorder.started.last?.expected == ["com.example.one"])
        let failure = try #require(manager.lastSpacingApplyFailure)
        #expect(failure.contains("Alpha") && failure.contains("Beta"))
    }

    @Test("A failed apply is reported and ends the preflight settling")
    func failedApplyIsReported() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager()
        recorder.error = ApplyFailed()

        setOffset(1, on: manager, uuid: uuid)
        await waitUntil { recorder.finished }

        #expect(recorder.cancelled == ["spacingRelaunch:configurationsChanged:error"])
        #expect(manager.lastSpacingApplyFailure == "disk full")
        #expect(recorder.reapplied == 0)
    }

    @Test("A profile a display change switched to only writes its spacing")
    func displayProfileSwitchOnlyWrites() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager()

        manager.assignConfigurations([uuid: .defaultConfiguration.withItemSpacingOffset(4)], writeOnly: true)
        await waitUntil { recorder.finished }

        #expect(recorder.applies.map(\.relaunchApps) == [false])
        #expect(recorder.started.map(\.reason) == ["spacingRelaunch:displayProfileSwitch:preflight"])
        #expect(spacingManager.offset == 4)
    }

    @Test("A display change for the display spacing was last applied to does nothing; another display only writes")
    func displayChangeApply() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager()

        manager.lastAppliedActiveDisplayUUID = uuid
        manager.applySpacingForDisplayChange()
        await waitUntil { !recorder.applies.isEmpty }
        #expect(recorder.applies.isEmpty)

        manager.lastAppliedActiveDisplayUUID = "SOME-OTHER-DISPLAY"
        manager.applySpacingForDisplayChange()
        await waitUntil { recorder.finished }
        #expect(recorder.applies.map(\.relaunchApps) == [false])
        #expect(recorder.started.map(\.reason) == ["spacingRelaunch:screenParametersChanged:preflight"])
        #expect(manager.lastAppliedActiveDisplayUUID == uuid)
    }

    @Test("Reapplying spacing for a display that does not own the menu bar does nothing")
    func reapplyIgnoresOtherDisplays() async throws {
        _ = try activeUUID()
        let manager = try makeManager(confirms: true)
        manager.confirmSpacingRelaunch = true

        manager.reapplySpacing(forDisplayUUID: "NOT-THE-ACTIVE-DISPLAY")
        await waitUntil { !recorder.applies.isEmpty }

        #expect(recorder.prompts == 0)
        #expect(recorder.applies.isEmpty)
    }

    @Test("Declining the relaunch prompt applies nothing")
    func reapplyDeclined() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager(confirms: true)
        manager.spacingApplyMode = .relaunchApps
        manager.confirmSpacingRelaunch = true
        recorder.approves = false

        manager.reapplySpacing(forDisplayUUID: uuid)
        await waitUntil { !recorder.applies.isEmpty }

        #expect(recorder.prompts == 1)
        #expect(recorder.applies.isEmpty)
        #expect(!manager.isReapplyingSpacing)
    }

    @Test("Approving the prompt forces a relaunch wave, and a second reapply while it runs is ignored")
    func reapplyApproved() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager(confirms: true)
        manager.spacingApplyMode = .relaunchApps
        manager.confirmSpacingRelaunch = true
        recorder.holdsApply = true

        manager.reapplySpacing(forDisplayUUID: uuid)
        #expect(manager.isReapplyingSpacing)
        await waitUntil { recorder.gate != nil }
        manager.reapplySpacing(forDisplayUUID: uuid)

        #expect(recorder.prompts == 1, "the second reapply never asks")
        #expect(recorder.applies.map(\.forceRelaunch) == [true])
        #expect(recorder.applies.map(\.relaunchApps) == [true])
        #expect(recorder.started.map(\.reason) == ["spacingRelaunch:userReapply:preflight"])

        try #require(recorder.gate).resume()
        await waitUntil { recorder.finished }
        await waitUntil { !manager.isReapplyingSpacing }
        #expect(!manager.isReapplyingSpacing)
        #expect(recorder.cancelled == ["spacingRelaunch:userReapply:noOp"])
    }

    @Test("Write-only mode reapplies without asking and without forcing a relaunch")
    func reapplyWriteOnly() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager(confirms: true)
        manager.confirmSpacingRelaunch = true
        manager.spacingApplyMode = .writeOnly

        manager.reapplySpacing(forDisplayUUID: uuid)
        await waitUntil { recorder.finished }

        #expect(recorder.prompts == 0)
        #expect(recorder.applies.map(\.forceRelaunch) == [false])
        #expect(!manager.isReapplyingSpacing)
    }

    @Test("Switching off confirmations reapplies without asking")
    func reapplyWithoutConfirmation() async throws {
        let uuid = try activeUUID()
        let manager = try makeManager(confirms: true)
        manager.spacingApplyMode = .relaunchApps
        manager.confirmSpacingRelaunch = false

        manager.reapplySpacing(forDisplayUUID: uuid)
        await waitUntil { recorder.finished }

        #expect(recorder.prompts == 0)
        #expect(recorder.applies.map(\.forceRelaunch) == [true])
    }

    @Test("The apply mode is passed on to the spacing manager")
    func applyModeReachesSpacingManager() throws {
        let manager = try makeManager()
        manager.spacingApplyMode = .writeOnly
        #expect(spacingManager.spacingApplyMode == .writeOnly)
        manager.spacingApplyMode = .relaunchApps
        #expect(spacingManager.spacingApplyMode == .relaunchApps)
    }

    @Test("Without a host, a configuration change is only saved")
    func noHostOnlySaves() async throws {
        let uuid = try activeUUID()
        try Defaults.set(JSONEncoder().encode([String: DisplayThawBarConfiguration]()), forKey: .displayThawBarConfigurations)
        let manager = DisplaySettingsManager()

        setOffset(5, on: manager, uuid: uuid)
        await waitUntil { manager.lastAppliedActiveDisplayUUID != nil }

        #expect(manager.lastAppliedActiveDisplayUUID == nil, "nothing was applied")
        #expect(manager.configurations[uuid]?.itemSpacingOffset == 5)
    }

    @Test("A per-display change posted from a thaw:// URL reaches an observing manager")
    func observerReceivesURIChange() async throws {
        let uuid = "URI-OBSERVER-TEST-DISPLAY"
        let manager = try makeManager()
        manager.configurations = [uuid: .defaultConfiguration]
        manager.configureObservers()

        // No other manager knows this display, so only this one acts on it.
        NotificationCenter.default.post(
            name: .perDisplaySettingsDidChangeViaURI,
            object: nil,
            userInfo: ["key": "gridColumns", "scope": "specific:\(uuid)", "stringValue": "7"]
        )
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while manager.configurations[uuid]?.gridColumns != 7, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(manager.configurations[uuid]?.gridColumns == 7)
    }
}
