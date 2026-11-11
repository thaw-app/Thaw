//
//  SettingsPageModelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Settings page models", .serialized, .scratchDefaults)
struct SettingsPageModelTests {
    /// Yields to the main actor until condition holds or a generous bound passes.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func postURIChange(_ key: String, _ value: Any, as field: String = "value") {
        NotificationCenter.default.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: ["key": key, field: value]
        )
    }

    @Test("Setup loads the stored values and then follows Settings URI changes")
    func setupLoadsAndFollowsURIChanges() async {
        Defaults.set(7.0, forKey: .tooltipDelay)
        let settings = VisibilitySettings()

        settings.performSetup()
        #expect(settings.tooltipDelay == 7)

        postURIChange("tooltipDelay", 4.5, as: "doubleValue")
        await waitUntil { settings.tooltipDelay == 4.5 }
        #expect(settings.tooltipDelay == 4.5)
    }

    @Test("Layout keeps the app state it was set up with")
    func layoutKeepsAppState() {
        let appState = AppState()
        let settings = LayoutSettings()
        settings.performSetup(with: appState)
        #expect(settings.appState === appState)
    }

    @Test("Observing a flag delivers its current value, then each change")
    func observeDeliversChanges() async {
        let settings = VisibilitySettings()
        settings.tooltipDelay = 1
        var seen: [Double] = []

        let cancellable = settings.observe(\.tooltipDelay) { seen.append($0) }
        await waitUntil { seen == [1] }
        settings.tooltipDelay = 2
        await waitUntil { seen == [1, 2] }
        cancellable.cancel()

        #expect(seen == [1, 2])
    }

    @Test("A Settings URI change for a moved key reaches the model that now holds it")
    func movedKeysFollowURIChanges() async {
        let settings = AppSettings()
        settings.performSetup(with: AppState())
        let flips: [(key: String, read: () -> Bool)] = [
            ("enableAlwaysHiddenSection", { settings.layout.enableAlwaysHiddenSection }),
            ("showOnClick", { settings.visibility.showOnClick }),
            ("enableSwapBar", { settings.visibility.enableSwapBar }),
            ("lockThawBarPosition", { settings.thawBar.lockThawBarPosition }),
            ("hideApplicationMenus", { settings.general.hideApplicationMenus }),
            ("fetchReleaseNotes", { settings.privacy.fetchReleaseNotes }),
            ("showSpaceIndicator", { settings.spaces.showSpaceIndicator }),
            ("enableDiagnosticLogging", { settings.tools.enableDiagnosticLogging }),
            ("enableControlItemPanel", { settings.widgets.enableControlItemPanel }),
        ]
        for flip in flips {
            let wanted = !flip.read()
            postURIChange(flip.key, wanted)
            await waitUntil { flip.read() == wanted }
            #expect(flip.read() == wanted, "\(flip.key) did not follow its Settings URI change")
        }

        postURIChange("rehideStrategy", RehideStrategy.timed.rawValue, as: "rawEnumValue")
        await waitUntil { settings.visibility.rehideStrategy == .timed }
        #expect(settings.visibility.rehideStrategy == .timed)
    }
}
