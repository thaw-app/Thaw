//
//  ThawBarSectionRoutingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Tests for the rule that decides which sections present in the Thaw Bar.
///
/// The display-wide setting sends every section there. The always-hidden-only
/// setting sends the always-hidden section alone, so the hidden section still
/// expands inline; reaching the always-hidden items inline would otherwise
/// unfurl the hidden section too, since they sit to the left of its control
/// item.
///
/// Notch overflow can force the bar on top of this, which
/// `NotchOverflowRevealTests` covers.
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

    /// The point of the setting: the hidden section keeps expanding in the
    /// menu bar while the always-hidden items open in the panel.
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
