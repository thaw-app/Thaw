//
//  ControlCenterBridgeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Testing
@testable import Thaw

/// Both ends of the Control Center bridge, against a scratch suite in place of the app group
/// and a recorder in place of Control Center. The app state is never set up.
@MainActor
@Suite("Control Center bridge", .serialized)
struct ControlCenterBridgeTests {
    private final class Reloads {
        var kinds: [String] = []
    }

    private func withPublisher(_ body: (ControlStatePublisher, UserDefaults, Reloads) throws -> Void) throws {
        let name = ScratchDefaults.name("ControlState")
        defer { ScratchDefaults.remove(name) }
        let suite = try #require(UserDefaults(suiteName: name))
        let reloads = Reloads()
        let publisher = ControlStatePublisher(defaults: suite) { reloads.kinds.append($0) }
        try body(publisher, suite, reloads)
    }

    private func stored(in suite: UserDefaults) throws -> ControlStatePublisher.Snapshot? {
        try suite.data(forKey: ControlStatePublisher.stateKey).map {
            try JSONDecoder().decode(ControlStatePublisher.Snapshot.self, from: $0)
        }
    }

    @Test("The snapshot is stored under its short keys")
    func snapshotKeys() throws {
        let data = try JSONEncoder().encode(ControlStatePublisher.Snapshot(isHiddenSectionRevealed: true, isZenModeActive: false))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Bool])
        #expect(object == ["hiddenRevealed": true, "zenActive": false])
    }

    @Test("Without an app state both controls read off")
    func missingAppState() {
        #expect(ControlStatePublisher.snapshot(for: nil) == .init(isHiddenSectionRevealed: false, isZenModeActive: false))
    }

    @Test("Setup publishes the current state once and reloads both controls")
    func setupPublishes() throws {
        try withPublisher { publisher, suite, reloads in
            let appState = AppState()
            publisher.performSetup(with: appState)
            publisher.performSetup(with: appState)

            let snapshot = try stored(in: suite)
            #expect(snapshot == ControlStatePublisher.snapshot(for: appState))
            #expect(reloads.kinds == ControlStatePublisher.controlKinds, "a second setup changes nothing")
        }
    }

    @Test("A clean quit erases the snapshot and reloads the controls")
    func terminationErases() throws {
        try withPublisher { publisher, suite, reloads in
            let appState = AppState()
            publisher.performSetup(with: appState)
            reloads.kinds.removeAll()

            publisher.handleTermination()

            let snapshot = try stored(in: suite)
            #expect(snapshot == nil)
            #expect(reloads.kinds == ControlStatePublisher.controlKinds)
        }
    }

    @Test("The app's quit notification erases the snapshot")
    func quitNotificationErases() async throws {
        let name = ScratchDefaults.name("ControlState")
        defer { ScratchDefaults.remove(name) }
        let suite = try #require(UserDefaults(suiteName: name))
        let center = NotificationCenter()
        let publisher = ControlStatePublisher(defaults: suite, reloadControl: { _ in }, terminationCenter: center)
        publisher.performSetup(with: AppState())
        #expect(try stored(in: suite) != nil)

        center.post(name: NSApplication.willTerminateNotification, object: nil)
        // The quit is received on the main queue, so wait for it rather than reading at once.
        let deadline = ContinuousClock.now + .seconds(10)
        while try stored(in: suite) != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(try stored(in: suite) == nil)
    }

    @Test("Without the app group nothing is written or reloaded")
    func missingGroup() {
        var reloads = 0
        let publisher = ControlStatePublisher(defaults: nil) { _ in reloads += 1 }
        publisher.performSetup(with: AppState())
        publisher.handleTermination()
        #expect(reloads == ControlStatePublisher.controlKinds.count, "only the quit asks for reloads")
    }

    @Test("Each control command maps to its hotkey action")
    func commandActions() {
        #expect(ControlCommandObserver.Command.toggleHidden.action == .toggleHiddenSection)
        #expect(ControlCommandObserver.Command.toggleZen.action == .toggleZenMode)
        #expect(Set(ControlCommandObserver.Command.allCases.map(\.rawValue)) == [
            "com.stonerl.Thaw.control.toggle-hidden",
            "com.stonerl.Thaw.control.toggle-zen",
        ])
    }

    @Test("Only the hidden-section toggle confirms, and only once there is a section")
    func commandConfirmations() {
        let appState = AppState()
        #expect(ControlCommandObserver.Command.toggleZen.confirmation(appState: appState) == nil)
        let confirmation = ControlCommandObserver.Command.toggleHidden.confirmation(appState: appState)
        if let section = appState.menuBarManager.section(withName: .hidden) {
            #expect(confirmation?.symbol == (section.isHidden ? "eye" : "eye.slash"))
        } else {
            #expect(confirmation == nil)
        }
    }
}
