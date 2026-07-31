//
//  OnboardingMockupsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

@Suite("Onboarding mockups")
struct OnboardingMockupsTests {
    // MARK: - ThawManagementMockupModel

    @MainActor
    @Suite("Management mockup model")
    struct ThawManagementMockupModelTests {
        @Test("Restarting resets the items to hidden")
        func restartResetsToHidden() {
            let model = ThawManagementMockupModel()
            model.itemsHidden = false

            model.restart()

            #expect(model.itemsHidden)
        }

        @Test("Toggling flips the hidden state")
        func toggleFlipsHiddenState() {
            let model = ThawManagementMockupModel()
            let initial = model.itemsHidden

            model.toggle()
            #expect(model.itemsHidden == !initial)

            model.toggle()
            #expect(model.itemsHidden == initial)
        }
    }

    // MARK: - ThawAppearanceMockupModel

    @MainActor
    @Suite("Appearance mockup model")
    struct ThawAppearanceMockupModelTests {
        @Test("There is one style label per style")
        func styleLabelsHasOneEntryPerStyle() {
            #expect(ThawAppearanceMockupModel.styleLabels.count == 3)
            for label in ThawAppearanceMockupModel.styleLabels {
                #expect(!label.isEmpty)
            }
        }

        @Test("Restarting resets the style index to zero")
        func restartResetsStyleIndexToZero() {
            let model = ThawAppearanceMockupModel()
            model.select(2)

            model.restart()

            #expect(model.styleIndex == 0)
        }

        @Test("Selecting updates the style index")
        func selectUpdatesIndex() {
            let model = ThawAppearanceMockupModel()

            model.select(1)
            #expect(model.styleIndex == 1)

            model.select(2)
            #expect(model.styleIndex == 2)
        }

        @Test("Selecting the current style index is a no-op")
        func selectCurrentIndexIsNoOp() {
            let model = ThawAppearanceMockupModel()
            model.select(1)
            #expect(model.styleIndex == 1)

            model.select(1)
            #expect(model.styleIndex == 1)
        }
    }

    // MARK: - ThawHotkeysMockupModel

    @MainActor
    @Suite("Hotkeys mockup model")
    struct ThawHotkeysMockupModelTests {
        @Test("Restarting resets the items to not visible")
        func restartResetsToNotVisible() {
            let model = ThawHotkeysMockupModel()
            model.itemsVisible = true

            model.restart()

            #expect(!model.itemsVisible)
        }

        @Test("Triggering toggles visibility")
        func triggerTogglesVisibility() {
            let model = ThawHotkeysMockupModel()
            let initial = model.itemsVisible

            model.trigger()
            #expect(model.itemsVisible == !initial)

            model.trigger()
            #expect(model.itemsVisible == initial)
        }
    }

    // MARK: - ThawProfilesMockupModel

    @MainActor
    @Suite("Profiles mockup model")
    struct ThawProfilesMockupModelTests {
        @Test("There is one focus mode per profile")
        func focusModesHasOneEntryPerProfile() {
            #expect(ThawProfilesMockupModel.focusModes.count == 3)
            for mode in ThawProfilesMockupModel.focusModes {
                #expect(!mode.name.isEmpty)
                #expect(!mode.symbol.isEmpty)
                #expect(!mode.items.isEmpty)
            }
        }

        @Test("The active focus mode reflects the focus index")
        func activeReflectsFocusIndex() {
            let model = ThawProfilesMockupModel()
            #expect(model.active.symbol == ThawProfilesMockupModel.focusModes[0].symbol)

            model.select(1)
            #expect(model.active.symbol == ThawProfilesMockupModel.focusModes[1].symbol)
        }

        @Test("Selecting updates the focus index")
        func selectUpdatesIndex() {
            let model = ThawProfilesMockupModel()

            model.select(2)
            #expect(model.focusIndex == 2)
        }

        @Test("Selecting the current focus index is a no-op")
        func selectCurrentIndexIsNoOp() {
            let model = ThawProfilesMockupModel()
            model.select(1)
            #expect(model.focusIndex == 1)

            model.select(1)
            #expect(model.focusIndex == 1)
        }

        @Test("Restarting resets the focus index to zero")
        func restartResetsFocusIndexToZero() {
            let model = ThawProfilesMockupModel()
            model.select(2)

            model.restart()

            #expect(model.focusIndex == 0)
        }
    }
}
