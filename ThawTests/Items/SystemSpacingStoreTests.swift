//
//  SystemSpacingStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins that a test's spacing writes land in scratch values, never in the Mac's menu bar spacing.
@MainActor
@Suite("System spacing store", .serialized, .scratchDefaults)
struct SystemSpacingStoreTests {
    private static let spacing = "NSStatusItemSpacing"
    private static let padding = "NSStatusItemSelectionPadding"

    /// The Mac's own values. Reading them changes nothing.
    private static func macSpacing() -> [Int?] {
        [SystemSpacingStore.live.read(spacing), SystemSpacingStore.live.read(padding)]
    }

    @Test("Under the scratch-defaults trait, the spacing manager writes the test's values and leaves the Mac's alone")
    func writesStayInTheScratchValues() async throws {
        let scratch = try #require(ScratchDefaults.spacingValues)
        // Proves the manager reads the scratch values before anything is written.
        scratch[Self.spacing] = 7
        try #require(SystemSpacingStore.current.read(Self.spacing) == 7)
        let mac = Self.macSpacing()

        let manager = MenuBarItemSpacingManager()
        manager.offset = -11
        manager.spacingApplyMode = .writeOnly
        try await manager.applyOffset(relaunchApps: false)

        #expect(scratch[Self.spacing] == 5)
        #expect(scratch[Self.padding] == 5)
        #expect(Self.macSpacing() == mac)
        #expect(DisplaySettingsManager.currentSystemSpacing() == 5, "the display settings read the same values")
    }

    @Test("Setting up the display settings writes their seeded spacing to the test's values, not the Mac's")
    func displaySetupWritesStayInTheScratchValues() async throws {
        let scratch = try #require(ScratchDefaults.spacingValues)
        // A Mac whose spacing was changed to 2, while the test's settings have the default.
        scratch[Self.spacing] = 2
        scratch[Self.padding] = 2
        let mac = Self.macSpacing()
        let appState = AppState()
        let displaySettings = appState.settings.displaySettings
        try #require(appState.spacingManager.store.read(Self.spacing) == 2)
        // Write-only, so the apply below never quits and relaunches the Mac's menu bar apps.
        displaySettings.spacingApplyMode = .writeOnly

        displaySettings.performSetup(with: appState)
        try #require(appState.spacingManager.spacingApplyMode == .writeOnly)
        // A display without an entry of its own takes the default template, offset 0.
        displaySettings.configurations = ["Test display": .defaultConfiguration]
        for _ in 0 ..< 100 where scratch[Self.spacing] != 16 {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(scratch[Self.spacing] == 16)
        #expect(scratch[Self.padding] == 16)
        #expect(Self.macSpacing() == mac)
    }

    @Test("A spacing manager keeps the store it was made with, so a write that lands after its test goes there")
    func managerKeepsItsStore() async throws {
        let outer = try #require(ScratchDefaults.spacingValues)
        var inner: ScratchSpacingValues?
        var manager: MenuBarItemSpacingManager?
        try ScratchDefaults.withStore(named: "SpacingLate") { _ in
            inner = ScratchDefaults.spacingValues
            manager = MenuBarItemSpacingManager()
        }
        let values = try #require(inner)
        let late = try #require(manager)
        values[Self.spacing] = 9
        try #require(late.store.read(Self.spacing) == 9, "the manager still reads the store it was made with")
        let mac = Self.macSpacing()

        late.offset = -12
        late.spacingApplyMode = .writeOnly
        try await late.applyOffset(relaunchApps: false)

        #expect(values[Self.spacing] == 4)
        #expect(values[Self.padding] == 4)
        #expect(outer[Self.spacing] == nil, "the store current by then is left alone")
        #expect(Self.macSpacing() == mac)
    }

    @Test("Scratch values start unset, so the spacing reads as macOS's default")
    func scratchStartsUnset() throws {
        let scratch = try #require(ScratchDefaults.spacingValues)
        #expect(scratch[Self.spacing] == nil)
        #expect(DisplaySettingsManager.currentSystemSpacing() == nil)
        #expect(MenuBarItemSpacingManager().isOnDisk(offset: 0))
    }

    @Test("A nested scratch store has its own values, and leaving it puts back the one it replaced")
    func nestedStoreIsRestored() throws {
        let outer = try #require(ScratchDefaults.spacingValues)
        outer[Self.spacing] = 4
        try ScratchDefaults.withStore(named: "SpacingInner") { _ in
            #expect(SystemSpacingStore.current.read(Self.spacing) == nil)
        }
        #expect(ScratchDefaults.spacingValues === outer)
        #expect(SystemSpacingStore.current.read(Self.spacing) == 4)
    }
}
