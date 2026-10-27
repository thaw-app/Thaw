//
//  SettingsChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Merged settings choices")
struct SettingsChoiceTests {
    private final class Switches: AutomaticUpdateSwitches {
        var automaticallyChecksForUpdates = false
        var automaticallyDownloadsUpdates = false
    }

    @Test("Automatic updates reads both switches as one choice", arguments: [
        (false, false, AutomaticUpdates.off),
        (false, true, AutomaticUpdates.off),
        (true, false, AutomaticUpdates.check),
        (true, true, AutomaticUpdates.download),
    ])
    func readsUpdateChoice(checks: Bool, downloads: Bool, expected: AutomaticUpdates) {
        #expect(AutomaticUpdates(checks: checks, downloads: downloads) == expected)
    }

    @Test("Choosing an update setting writes both switches")
    func writesUpdateChoice() {
        let switches = Switches()

        switches.automaticUpdates = .download
        #expect(switches.automaticallyChecksForUpdates && switches.automaticallyDownloadsUpdates)

        switches.automaticUpdates = .check
        #expect(switches.automaticallyChecksForUpdates && !switches.automaticallyDownloadsUpdates)

        switches.automaticUpdates = .off
        #expect(!switches.automaticallyChecksForUpdates && !switches.automaticallyDownloadsUpdates)
        #expect(AutomaticUpdates.allCases.allSatisfy { !String(describing: $0.localized).isEmpty })
        #expect(AutomaticUpdates.allCases.allSatisfy { $0.id == $0 })
    }

    @Test("The spacing choice reads the apply mode and the confirmation switch", arguments: [
        (SpacingApplyMode.relaunchApps, true, SpacingApplyChoice.askFirst),
        (SpacingApplyMode.relaunchApps, false, SpacingApplyChoice.relaunchNow),
        (SpacingApplyMode.writeOnly, true, SpacingApplyChoice.waitForRestart),
        (SpacingApplyMode.writeOnly, false, SpacingApplyChoice.waitForRestart),
    ])
    func readsSpacingChoice(mode: SpacingApplyMode, confirms: Bool, expected: SpacingApplyChoice) {
        #expect(SpacingApplyChoice(mode: mode, confirms: confirms) == expected)
    }

    @Test("Apply to All Displays asks only when the choice asks or no profile says where to save", arguments: [
        (SpacingApplyMode.relaunchApps, true, true, true),
        (SpacingApplyMode.relaunchApps, true, false, true),
        (SpacingApplyMode.relaunchApps, false, true, false),
        (SpacingApplyMode.relaunchApps, false, false, false),
        (SpacingApplyMode.writeOnly, true, true, false),
        (SpacingApplyMode.writeOnly, true, false, true),
        (SpacingApplyMode.writeOnly, false, true, false),
        (SpacingApplyMode.writeOnly, false, false, false),
    ])
    func globalApplyAsks(mode: SpacingApplyMode, confirms: Bool, hasActiveProfile: Bool, expected: Bool) {
        #expect(SpacingApplyChoice.globalApplyAsks(mode: mode, confirms: confirms, hasActiveProfile: hasActiveProfile) == expected)
    }

    @Test("Each spacing choice maps back to what the rest of Thaw reads")
    func spacingChoiceRoundTrips() {
        #expect(SpacingApplyChoice.askFirst.mode == .relaunchApps && SpacingApplyChoice.askFirst.confirms == true)
        #expect(SpacingApplyChoice.relaunchNow.mode == .relaunchApps && SpacingApplyChoice.relaunchNow.confirms == false)
        #expect(SpacingApplyChoice.waitForRestart.mode == .writeOnly && SpacingApplyChoice.waitForRestart.confirms == nil)
        for choice in SpacingApplyChoice.allCases {
            #expect(SpacingApplyChoice(mode: choice.mode, confirms: choice.confirms ?? true) == choice)
        }
    }
}
