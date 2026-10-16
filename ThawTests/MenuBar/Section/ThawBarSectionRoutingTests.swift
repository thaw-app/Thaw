//
//  ThawBarSectionRoutingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Which sections present in the Thaw Bar.
///
/// The display-wide setting sends every section. The always-hidden-only setting
/// sends just always-hidden, so hidden still expands inline; reaching
/// always-hidden inline would unfurl hidden too, since it sits left of hidden's
/// control item. Notch overflow is in `NotchOverflowRevealTests`.
@Suite("Thaw Bar section routing")
struct ThawBarSectionRoutingTests {
    @Test(
        "The display-wide setting sends every section to the Thaw Bar",
        arguments: MenuBarSection.Name.allCases
    )
    func displayWideSettingRoutesEverySection(name: MenuBarSection.Name) {
        #expect(
            MenuBarSection.usesThawBar(
                for: name,
                displayUsesThawBar: true,
                alwaysHiddenUsesThawBar: false
            )
        )
    }

    @Test(
        "The display-wide setting wins over the always-hidden-only setting",
        arguments: MenuBarSection.Name.allCases
    )
    func displayWideSettingWinsOverAlwaysHiddenOnly(name: MenuBarSection.Name) {
        #expect(
            MenuBarSection.usesThawBar(
                for: name,
                displayUsesThawBar: true,
                alwaysHiddenUsesThawBar: true
            )
        )
    }

    @Test("Always-hidden-only sends the always-hidden section to the Thaw Bar")
    func alwaysHiddenOnlyRoutesTheAlwaysHiddenSection() {
        #expect(
            MenuBarSection.usesThawBar(
                for: .alwaysHidden,
                displayUsesThawBar: false,
                alwaysHiddenUsesThawBar: true
            )
        )
    }

    /// Hidden keeps expanding in the menu bar while always-hidden opens in the panel.
    @Test(
        "Always-hidden-only leaves the other sections inline",
        arguments: [MenuBarSection.Name.visible, .hidden]
    )
    func alwaysHiddenOnlyLeavesTheOtherSectionsInline(name: MenuBarSection.Name) {
        #expect(
            !MenuBarSection.usesThawBar(
                for: name,
                displayUsesThawBar: false,
                alwaysHiddenUsesThawBar: true
            )
        )
    }

    @Test(
        "Both settings off keeps every section inline",
        arguments: MenuBarSection.Name.allCases
    )
    func bothSettingsOffKeepsEverySectionInline(name: MenuBarSection.Name) {
        #expect(
            !MenuBarSection.usesThawBar(
                for: name,
                displayUsesThawBar: false,
                alwaysHiddenUsesThawBar: false
            )
        )
    }
}
