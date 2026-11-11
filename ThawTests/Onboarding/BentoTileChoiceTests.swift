//
//  BentoTileChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// A card click turned Simple Mode off whatever the picker said, and the Zen Mode card opened Shortcuts.
@MainActor
@Suite("Onboarding card choice")
struct BentoTileChoiceTests {
    @Test("Under Simple Mode a card keeps Simple Mode and opens no pane; under All Settings it opens its pane")
    func followsThePicker() {
        for demo in BentoDemo.allCases {
            let simple = BentoTileChoice.outcome(for: demo, simpleMode: true)
            #expect(simple.simpleMode && simple.pane == nil)
            let full = BentoTileChoice.outcome(for: demo, simpleMode: false)
            #expect(!full.simpleMode && full.pane == demo.pane)
        }
    }

    @Test("The Zen Mode card opens Visibility, where Zen Mode's settings are")
    func zenOpensVisibility() {
        #expect(BentoDemo.zen.pane == .visibility)
    }

    @Test("A card draws whether or not it opens a pane")
    func tileDrawsInBothModes() {
        let tiles = [
            BentoTile(demo: .find, index: 0, appeared: true) {},
            BentoTile(demo: .find, index: 0, appeared: true, opensPane: false) {},
        ]
        for tile in tiles {
            let host = NSHostingView(rootView: tile.frame(width: 300, height: 150))
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.width > 0)
        }
    }

    @Test("A card click on a fresh screen keeps the preselected Simple Mode")
    func clickKeepsPreselectedSimpleMode() {
        var outcomes: [(OnboardingOutcome, SettingsNavigationIdentifier?)] = []
        let view = OnboardingBentoView(finishesFlow: true) { outcomes.append(($0, $1)) }
        view.chooseCard(.zen)
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.0.simpleMode == true)
        #expect(outcomes.first?.1 == nil)
    }
}
