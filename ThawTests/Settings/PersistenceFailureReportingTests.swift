//
//  PersistenceFailureReportingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// didSet cannot throw: report failed writes to panes and clear warnings on success, using scratch defaults to protect user settings.
/// Test only the spacer model because manager mutations create real NSStatusItems in the tester's menu bar.
@MainActor
@Suite("Persistence failure reporting", .serialized)
struct PersistenceFailureReportingTests {
    /// Runs body with Defaults pointed at an empty, throwaway suite.
    private func withScratchDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
        let suiteName = "PersistenceFailureReportingTests.\(UUID().uuidString)"
        let scratch = try #require(UserDefaults(suiteName: suiteName))
        let previous = Defaults.store
        Defaults.store = scratch
        defer {
            Defaults.store = previous
            scratch.removePersistentDomain(forName: suiteName)
        }
        return try body(scratch)
    }

    // MARK: Appearance

    @Test("A failed appearance write is reported, and the next good one clears it")
    func appearanceFailureCycle() throws {
        try withScratchDefaults { _ in
            let manager = MenuBarAppearanceManager()
            #expect(manager.lastPersistenceFailure == nil, "Nothing has been written yet")

            // A non-finite Double is what JSONEncoder refuses by default,
            // and margins are the plain Doubles on the configuration.
            manager.configuration.leftMargin = .infinity

            let failure = try #require(manager.lastPersistenceFailure, "The encode threw and the pane has to hear it")
            #expect(!failure.isEmpty)
            #expect(
                Defaults.data(forKey: .menuBarAppearanceConfigurationV2) == nil,
                "Nothing reached the store, which is the whole reason the flag exists"
            )

            manager.configuration.leftMargin = 4

            #expect(manager.lastPersistenceFailure == nil, "A stale warning is as wrong as a missing one")
            #expect(Defaults.data(forKey: .menuBarAppearanceConfigurationV2) != nil)
        }
    }

    @Test("An appearance write that succeeds never raises the flag")
    func appearanceSuccessIsSilent() throws {
        try withScratchDefaults { _ in
            let manager = MenuBarAppearanceManager()

            manager.configuration.isInset.toggle()

            #expect(manager.lastPersistenceFailure == nil)
            #expect(Defaults.data(forKey: .menuBarAppearanceConfigurationV2) != nil)
        }
    }

    // MARK: Displays

    /// Use the memberwise initializer to bypass withItemSpacingOffset's ±16 clamp and reach JSONEncoder's nonfinite-value failure.
    private var unencodableDisplayConfiguration: DisplayThawBarConfiguration {
        let base = DisplayThawBarConfiguration.defaultConfiguration
        return DisplayThawBarConfiguration(
            useThawBar: base.useThawBar,
            thawBarLocation: base.thawBarLocation,
            alwaysShowHiddenItems: base.alwaysShowHiddenItems,
            thawBarLayout: base.thawBarLayout,
            gridColumns: base.gridColumns,
            itemSpacingOffset: .infinity
        )
    }

    @Test("A failed global display write is reported, and the next good one clears it")
    func displayFailureCycle() throws {
        try withScratchDefaults { _ in
            let manager = DisplaySettingsManager()
            #expect(manager.lastPersistenceFailure == nil, "A load from an empty store is not a failure")

            manager.globalConfiguration = unencodableDisplayConfiguration

            let failure = try #require(manager.lastPersistenceFailure)
            #expect(!failure.isEmpty)
            #expect(Defaults.data(forKey: .globalDisplayConfiguration) == nil, "Nothing reached the store")

            manager.globalConfiguration = .defaultConfiguration

            #expect(manager.lastPersistenceFailure == nil)
            #expect(Defaults.data(forKey: .globalDisplayConfiguration) != nil)
        }
    }

    @Test("A display write that succeeds never raises the flag")
    func displaySuccessIsSilent() throws {
        try withScratchDefaults { _ in
            let manager = DisplaySettingsManager()

            manager.globalConfiguration = .defaultConfiguration.withUseThawBar(true)

            #expect(manager.lastPersistenceFailure == nil)
            #expect(Defaults.data(forKey: .globalDisplayConfiguration) != nil)
        }
    }

    @Test("A per-display write clears a failure left by the global one")
    func displayFlagIsShared() throws {
        try withScratchDefaults { _ in
            let manager = DisplaySettingsManager()
            manager.globalConfiguration = unencodableDisplayConfiguration
            #expect(manager.lastPersistenceFailure != nil)

            // One flag covers every display write, so the pane's warning has
            // to come down as soon as any of them lands.
            manager.configurations = ["TEST-DISPLAY-UUID": .defaultConfiguration]

            #expect(manager.lastPersistenceFailure == nil)
            #expect(Defaults.data(forKey: .displayThawBarConfigurations) != nil)
        }
    }

    // MARK: Spacers

    @Test("A spacer width the user can set is a width that cannot be stored")
    func spacerWidthCanDefeatTheEncoder() {
        // NaN comparisons are false, so clamped(to:) lets NaN widths reach persistence through init and setWidth.
        #expect(MenuBarSpacer(width: .nan).width.isNaN)
        #expect(throws: (any Error).self) {
            try JSONEncoder().encode([MenuBarSpacer(width: .nan)])
        }
    }

    @Test("An ordinary spacer round-trips, so the flag stays down on the happy path")
    func spacerRoundTrips() throws {
        let spacer = MenuBarSpacer(width: 24)
        let decoded = try JSONDecoder().decode([MenuBarSpacer].self, from: JSONEncoder().encode([spacer]))

        #expect(decoded == [spacer])
    }
}
