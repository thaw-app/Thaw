//
//  ProfileSectionSwitchesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Switching profiles must not turn off Always Hidden or the overflow switch.
@Suite("Profile section switches")
struct ProfileSectionSwitchesTests {
    private func snapshot(alwaysHidden: Bool, overflow: Bool, tooltips: Bool = false) -> AdvancedSettingsSnapshot {
        var snapshot = AdvancedSettingsSnapshot.defaults
        snapshot.enableAlwaysHiddenSection = alwaysHidden
        snapshot.enableMenuBarItemOverflow = overflow
        snapshot.showMenuBarTooltips = tooltips
        return snapshot
    }

    @Test("A profile saved with Always Hidden off leaves it on")
    func keepsAlwaysHiddenOn() {
        let merged = snapshot(alwaysHidden: false, overflow: false).merged(onto: snapshot(alwaysHidden: true, overflow: false))
        #expect(merged.enableAlwaysHiddenSection)
    }

    @Test("A profile saved with Always Hidden on turns it on")
    func turnsAlwaysHiddenOn() {
        let merged = snapshot(alwaysHidden: true, overflow: false).merged(onto: snapshot(alwaysHidden: false, overflow: false))
        #expect(merged.enableAlwaysHiddenSection)
    }

    @Test("The overflow switch keeps the current value either way", arguments: [true, false])
    func overflowStaysCurrent(current: Bool) {
        let merged = snapshot(alwaysHidden: false, overflow: !current).merged(onto: snapshot(alwaysHidden: false, overflow: current))
        #expect(merged.enableMenuBarItemOverflow == current)
    }

    @Test("Other settings still come from the profile")
    func otherSettingsApply() {
        let merged = snapshot(alwaysHidden: false, overflow: false, tooltips: true)
            .merged(onto: snapshot(alwaysHidden: false, overflow: false, tooltips: false))
        #expect(merged.showMenuBarTooltips)
    }
}
