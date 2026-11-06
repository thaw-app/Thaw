//
//  DisplayChangeSpacingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Display change spacing", .serialized, .timeLimit(.minutes(1)))
struct DisplayChangeSpacingTests {
    @Test("The seed step seeds the display settings and applies nothing")
    func seedStepSeeds() {
        let spacing = RecordingSpacing()
        let effects = makeEffects(spacing)

        effects.seedDisplayConfigurations()

        #expect(spacing.calls == [.seed])
    }

    @Test("The spacing step applies the display settings' spacing and seeds nothing")
    func applyStepApplies() {
        let spacing = RecordingSpacing()
        let effects = makeEffects(spacing)

        effects.applyDisplaySpacing()

        #expect(spacing.calls == [.apply])
    }

    @Test(
        "A display change keeping the active display applies no spacing",
        arguments: [("display-a", "display-a"), (nil, nil)] as [(String?, String?)]
    )
    func unchangedActiveDisplaySkips(current: String?, last: String?) {
        #expect(DisplaySettingsManager.displayChangeSpacingReason(
            currentActiveDisplayUUID: current,
            lastAppliedActiveDisplayUUID: last
        ) == nil)
    }

    @Test(
        "A display change moving the menu bar writes spacing without relaunching apps",
        arguments: [("display-b", "display-a"), ("display-a", nil), (nil, "display-a")] as [(String?, String?)]
    )
    func changedActiveDisplayWritesOnly(current: String?, last: String?) throws {
        let reason = try #require(DisplaySettingsManager.displayChangeSpacingReason(
            currentActiveDisplayUUID: current,
            lastAppliedActiveDisplayUUID: last
        ))
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: reason))
    }

    @Test("Seeding gives each connected display the global template and records its name", .scratchDefaults)
    func seedingCopiesTheTemplate() throws {
        let connected = namedConnectedDisplayUUIDs()
        try #require(!connected.isEmpty, "needs a connected display")
        let manager = DisplaySettingsManager()
        manager.globalConfiguration = DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(3)
        manager.configurations = [:]
        manager.knownDisplays = [:]

        manager.seedConnectedDisplays()

        for uuid in connected {
            #expect(manager.configurations[uuid] == manager.globalConfiguration)
            #expect(manager.knownDisplays[uuid] != nil)
        }
    }

    /// The configurations are seeded for every display first, so neither setup nor a posting has
    /// anything to seed, and the last applied display is the current one, so nothing is applied;
    /// only the known-display cache would show a reaction.
    @Test("The display settings no longer react to a raw screen-parameters posting", .scratchDefaults)
    func noReactionToRawPosting() async throws {
        let connected = namedConnectedDisplayUUIDs()
        try #require(!connected.isEmpty, "needs a connected display")
        let manager = DisplaySettingsManager()
        manager.configurations = Dictionary(uniqueKeysWithValues: connected.map { ($0, manager.globalConfiguration) })
        let appState = AppState()
        manager.performSetup(with: appState)
        manager.lastAppliedActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()
        manager.knownDisplays = [:]
        // An observer that a task adds is only in place once that task has started.
        try await Task.sleep(for: .milliseconds(200))

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(1500))

        #expect(manager.knownDisplays.isEmpty)
        withExtendedLifetime(appState) {}
    }

    private func makeEffects(_ spacing: some DisplayChangeSpacing) -> MenuBarDisplayChangeEffects {
        let manager = MenuBarItemManager()
        return MenuBarDisplayChangeEffects(
            itemManager: manager,
            repairs: manager.repairs,
            imageCache: MenuBarItemImageCache(),
            displaySettings: spacing,
            profiles: ProfileManager(),
            presentationMonitor: PresentationMonitor(),
            menuBarManager: MenuBarManager()
        )
    }

    private func namedConnectedDisplayUUIDs() -> [String] {
        NSScreen.managedScreens.compactMap { screen in
            guard !screen.localizedName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Bridging.getDisplayUUIDString(for: screen.displayID)
        }
    }
}

@MainActor
private final class RecordingSpacing: DisplayChangeSpacing {
    enum Call: Equatable {
        case seed
        case apply
    }

    private(set) var calls: [Call] = []

    func seedConnectedDisplays() {
        calls.append(.seed)
    }

    func applySpacingForDisplayChange() {
        calls.append(.apply)
    }
}
