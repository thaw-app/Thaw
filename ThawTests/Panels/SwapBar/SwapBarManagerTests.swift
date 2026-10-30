//
//  SwapBarManagerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import Testing
@testable import Thaw

/// The Swap Bar's show, hide and placement, with stand-ins that keep the panel off screen and
/// install no pointer monitor. Profiles live in a throwaway directory and settings in a throwaway suite.
@Suite("Swap Bar manager", .serialized, .scratchDefaults)
@MainActor
struct SwapBarManagerTests {
    /// Records what the manager asked to put on screen and to watch.
    private final class Recorder {
        var presented: [NSPanel] = []
        var pointerHandlers: [@MainActor () -> Void] = []
    }

    private let recorder = Recorder()
    private let displaySettlements = PassthroughSubject<EnvironmentChange, Never>()

    private func makeManager() -> SwapBarManager {
        let manager = SwapBarManager()
        let recorder = recorder
        manager.orderFront = { recorder.presented.append($0) }
        manager.startPointerMonitor = { handler in
            recorder.pointerHandlers.append(handler)
            return EventMonitor.passive(for: [.mouseMoved], scope: .local) { _ in
                // Never started, so it never fires.
            }
        }
        return manager
    }

    private static func makeAppState(profiles directory: URL) -> AppState {
        ProfileManager.$directoryOverride.withValue(directory) { AppState() }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Turning the switch on fills a panel, sizes it under the menu bar and starts watching the pointer, all without ordering it on screen")
    func switchOnShowsTheBar() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appState = Self.makeAppState(profiles: tmp)
        appState.settings.advanced.enableSwapBar = false
        let manager = makeManager()
        manager.performSetup(with: appState, displaySettlements: displaySettlements)

        appState.settings.advanced.enableSwapBar = true
        await waitUntil { !recorder.presented.isEmpty }

        let panel = try #require(recorder.presented.first as? SwapBarPanel)
        #expect(panel.contentView != nil)
        #expect(panel.frame.size == panel.fittingContentSize)
        #expect(NSScreen.screens.contains { $0.frame.intersects(panel.frame) }, "placed on a display")
        #expect(recorder.pointerHandlers.count == 1)
        #expect(!panel.isVisible)
    }

    @Test("Turning the switch off drops the panel and the pointer monitor, so turning it back on builds new ones")
    func switchOffHidesTheBar() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appState = Self.makeAppState(profiles: tmp)
        appState.settings.advanced.enableSwapBar = true
        let manager = makeManager()
        manager.performSetup(with: appState, displaySettlements: displaySettlements)
        await waitUntil { recorder.presented.count == 1 }

        appState.settings.advanced.enableSwapBar = false
        await Task.yield()
        appState.settings.advanced.enableSwapBar = true
        await waitUntil { recorder.presented.count == 2 }

        #expect(recorder.presented.count == 2)
        #expect(recorder.presented.first !== recorder.presented.last, "hiding released the old panel")
        #expect(recorder.pointerHandlers.count == 2, "hiding stopped the old monitor")
    }

    @Test("A settled display change places the bar again")
    func displayChangeRepositions() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appState = Self.makeAppState(profiles: tmp)
        appState.settings.advanced.enableSwapBar = true
        let manager = makeManager()
        manager.performSetup(with: appState, displaySettlements: displaySettlements)
        await waitUntil { !recorder.presented.isEmpty }
        let panel = try #require(recorder.presented.first)
        let placed = panel.frame
        let moved = placed.offsetBy(dx: -5000, dy: -5000)
        panel.setFrame(moved, display: false)

        displaySettlements.send(.rearranged)
        await waitUntil { panel.frame.origin != moved.origin }

        #expect(panel.frame == placed)
        #expect(recorder.presented.count == 1, "placing again does not present again")
    }

    @Test("A pointer move on the display the bar is on leaves it where it is")
    func pointerMoveOnSameDisplay() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appState = Self.makeAppState(profiles: tmp)
        appState.settings.advanced.enableSwapBar = true
        let manager = makeManager()
        manager.performSetup(with: appState, displaySettlements: displaySettlements)
        await waitUntil { !recorder.pointerHandlers.isEmpty }
        let panel = try #require(recorder.presented.first)
        let placed = panel.frame

        let pointerMoved = try #require(recorder.pointerHandlers.first)
        pointerMoved()

        #expect(panel.frame.size == placed.size)
    }

    @Test("Picking a profile in the bar makes it active; picking the active one again does nothing")
    func pickingAProfile() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appState = Self.makeAppState(profiles: tmp)
        // Spacing matching the disk and write-only mode keep the apply from writing spacing.
        let offset = (DisplaySettingsManager.currentSystemSpacing() ?? 16) - 16
        try #require(appState.spacingManager.isOnDisk(offset: offset), "spacing and padding on disk differ")
        appState.spacingManager.offset = offset
        appState.spacingManager.spacingApplyMode = .writeOnly
        let profiles = appState.profileManager
        let work = try profiles.saveProfile(name: "Work", from: appState)
        let home = try profiles.saveProfile(name: "Home", from: appState)
        #expect(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("\(work.uuidString).json").path), "profiles go to the throwaway directory")
        profiles.activeProfileID = work

        let view = SwapBarView(appState: appState)
        let homeMetadata = try #require(profiles.profiles.first { $0.id == home })
        view.apply(homeMetadata)
        #expect(profiles.activeProfileID == home)
        let task = try #require(profiles.layoutTask, "the switch runs the profile's apply")
        #expect(profiles.layoutTaskProfileID == home)
        await task.value

        view.apply(homeMetadata)
        #expect(profiles.layoutTask == nil, "the active profile is not applied again")
        #expect(profiles.activeProfileID == home)
    }
}
