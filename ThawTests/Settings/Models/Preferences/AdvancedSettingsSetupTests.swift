//
//  AdvancedSettingsSetupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Advanced settings setup and observation", .serialized, .scratchDefaults)
struct AdvancedSettingsSetupTests {
    /// Yields to the main actor until condition holds or a generous bound passes.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("Setup loads the stored values and then follows Settings URI changes")
    func setupLoadsAndFollowsURIChanges() async {
        Defaults.set(7.0, forKey: .tooltipDelay)
        let appState = AppState()
        let settings = AdvancedSettings()

        settings.performSetup(with: appState)
        #expect(settings.tooltipDelay == 7)
        #expect(settings.appState === appState)

        NotificationCenter.default.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: ["key": "tooltipDelay", "doubleValue": 4.5]
        )
        await waitUntil { settings.tooltipDelay == 4.5 }
        #expect(settings.tooltipDelay == 4.5)
    }

    @Test("Observing a flag delivers its current value, then each change")
    func observeDeliversChanges() async {
        let settings = AdvancedSettings()
        settings.tooltipDelay = 1
        var seen: [Double] = []

        let cancellable = settings.observe(\.tooltipDelay) { seen.append($0) }
        await waitUntil { seen == [1] }
        settings.tooltipDelay = 2
        await waitUntil { seen == [1, 2] }
        cancellable.cancel()

        #expect(seen == [1, 2])
    }
}
