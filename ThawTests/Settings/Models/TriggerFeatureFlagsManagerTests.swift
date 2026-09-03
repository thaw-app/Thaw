//
//  TriggerFeatureFlagsManagerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Trigger feature flags manager")
@MainActor
struct TriggerFeatureFlagsManagerTests {
    // MARK: - Feature metadata

    @Test("Every feature has a unique raw value and a matching id")
    func rawValuesAreUnique() {
        let rawValues = TriggerFeature.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
        for feature in TriggerFeature.allCases {
            #expect(feature.id == feature.rawValue)
        }
    }

    @Test("Every feature carries a title and a detail")
    func titlesAndDetailsArePopulated() {
        for feature in TriggerFeature.allCases {
            #expect(!feature.title.isEmpty)
            #expect(!feature.detail.isEmpty)
        }
    }

    @Test("Status badges match the documented testing status")
    func statusBadges() {
        #expect(TriggerFeature.vpn.statusBadge == "Untested")
        #expect(TriggerFeature.audioOutput.statusBadge == "Untested")
        #expect(TriggerFeature.wifiSSID.statusBadge == "Experimental")
        #expect(TriggerFeature.focusMode.statusBadge == "Experimental")
        #expect(TriggerFeature.location.statusBadge == "Experimental")
        #expect(TriggerFeature.scriptResult.statusBadge == "Experimental")
        #expect(TriggerFeature.imageComparison.statusBadge == "Experimental")
        #expect(TriggerFeature.attentionSeeking.statusBadge == "Experimental")
        #expect(TriggerFeature.frontmostApp.statusBadge == nil)
        #expect(TriggerFeature.schedule.statusBadge == nil)
        #expect(TriggerFeature.compoundConditions.statusBadge == nil)
        #expect(TriggerFeature.invertAction.statusBadge == nil)
    }

    // MARK: - Defaults

    @Test("A fresh manager has every feature disabled")
    func freshManagerHasEverythingDisabled() throws {
        try withScratchDefaults { _ in
            let manager = TriggerFeatureFlagsManager()
            #expect(!manager.hasEnabledFlags)
            for feature in TriggerFeature.allCases {
                #expect(!manager.isEnabled(feature))
            }
        }
    }

    // MARK: - Enabling / disabling

    @Test("Enabling a feature turns it on, publishes, and persists")
    func enablingPersistsAndNotifies() throws {
        try withScratchDefaults { _ in
            var handlerCalls = 0
            let manager = TriggerFeatureFlagsManager()
            manager.addChangeHandler { handlerCalls += 1 }

            manager.setEnabled(.schedule, true)
            #expect(manager.isEnabled(.schedule))
            #expect(manager.hasEnabledFlags)
            #expect(handlerCalls == 1)
            #expect(Defaults.stringArray(forKey: .triggerFeatureFlags)?.contains("schedule") == true)

            manager.setEnabled(.schedule, false)
            #expect(!manager.isEnabled(.schedule))
            #expect(!manager.hasEnabledFlags)
            #expect(handlerCalls == 2)
            #expect(
                Defaults.stringArray(forKey: .triggerFeatureFlags)?.contains("schedule") == false
            )
        }
    }

    @Test("Disabling every flag clears and persists the empty set")
    func disableAllClearsAndPersists() throws {
        try withScratchDefaults { _ in
            let manager = TriggerFeatureFlagsManager()
            manager.setEnabled(.network, true)
            manager.setEnabled(.display, true)
            #expect(manager.hasEnabledFlags)

            manager.disableAll()
            #expect(!manager.hasEnabledFlags)
            let persisted = Defaults.stringArray(forKey: .triggerFeatureFlags) ?? []
            #expect(persisted.isEmpty)
        }
    }

    @Test("A second manager sees the first manager's persisted flags")
    func persistedFlagsSurviveReload() throws {
        try withScratchDefaults { _ in
            let first = TriggerFeatureFlagsManager()
            first.setEnabled(.energyMode, true)
            first.setEnabled(.thermalPressure, true)

            let second = TriggerFeatureFlagsManager()
            #expect(second.isEnabled(.energyMode))
            #expect(second.isEnabled(.thermalPressure))
            #expect(!second.isEnabled(.network))
            #expect(second.hasEnabledFlags)
        }
    }

    @Test("Constructing a manager does not rewrite the persisted set")
    func initDoesNotPersist() throws {
        try withScratchDefaults { _ in
            Defaults.set(["frontmostApp"], forKey: .triggerFeatureFlags)

            _ = TriggerFeatureFlagsManager()
            #expect(Defaults.stringArray(forKey: .triggerFeatureFlags) == ["frontmostApp"])
        }
    }

    // MARK: - Bindings

    @Test("Bindings read and write through the manager")
    func bindingsRoundTrip() throws {
        try withScratchDefaults { _ in
            let manager = TriggerFeatureFlagsManager()
            let binding = manager.binding(for: .focusMode)
            #expect(!binding.wrappedValue)

            binding.wrappedValue = true
            #expect(manager.isEnabled(.focusMode))

            binding.wrappedValue = false
            #expect(!manager.isEnabled(.focusMode))
        }
    }

    // MARK: - Menu bar menu escape hatch

    @Test("The all-off menu item preference persists immediately")
    func allOffMenuItemPersists() throws {
        try withScratchDefaults { _ in
            let manager = TriggerFeatureFlagsManager()
            #expect(!manager.showsAllOffInMenuBarMenu)

            manager.showsAllOffInMenuBarMenu = true
            #expect(Defaults.bool(forKey: .showTriggerFeatureFlagsAllOffMenuItem))

            let reloaded = TriggerFeatureFlagsManager()
            #expect(reloaded.showsAllOffInMenuBarMenu)
        }
    }
}
