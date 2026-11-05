//
//  DisplayConfigurationBindingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The bindings the Thaw Bar page and the Displays Template tab edit through.
/// No manager here is wired to an AppState, so no spacing is ever applied.
@MainActor
@Suite("Display configuration bindings", .serialized, .scratchDefaults)
struct DisplayConfigurationBindingTests {
    private static let uuid = "TEST-DISPLAY-UUID"

    private func makeManager() throws -> DisplaySettingsManager {
        let configurations = [Self.uuid: DisplayThawBarConfiguration.defaultConfiguration]
        try Defaults.set(JSONEncoder().encode(configurations), forKey: .displayThawBarConfigurations)
        Defaults.removeObject(forKey: .globalDisplayConfiguration)
        return DisplaySettingsManager()
    }

    @Test("Editing the template changes only the template, so no display moves")
    func templateEditLeavesDisplays() throws {
        let manager = try makeManager()
        let binding = manager.binding(for: .template, \.thawBarLocation) { $0.withThawBarLocation($1) }

        binding.wrappedValue = .leftAligned

        #expect(manager.globalConfiguration.thawBarLocation == .leftAligned)
        #expect(manager.configuration(forUUID: Self.uuid).thawBarLocation == .dynamic)
        #expect(binding.wrappedValue == .leftAligned)
    }

    @Test("Editing a display changes only that display, and leaves the template alone")
    func displayEditLeavesTemplate() throws {
        let manager = try makeManager()
        let target = DisplaySettingsManager.ConfigurationTarget.display(Self.uuid)
        let binding = manager.binding(for: target, \.gridColumns) { $0.withGridColumns($1) }

        binding.wrappedValue = 7

        #expect(manager.configuration(forUUID: Self.uuid).gridColumns == 7)
        #expect(manager.configuration(for: target).gridColumns == 7)
        #expect(manager.globalConfiguration.gridColumns == DisplayThawBarConfiguration.defaultConfiguration.gridColumns)
    }
}
