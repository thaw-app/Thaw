//
//  HiddenItemsPresentationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Hidden items appear in one of three places")
struct HiddenItemsPresentationTests {
    @Test("There are three choices, in the order the picker shows them")
    func threeChoices() {
        #expect(HiddenItemsPresentation.allCases == [.onClick, .thawBar, .alwaysShown])
    }

    @Test("Both switches off reads as on click")
    func neitherSwitch() {
        #expect(HiddenItemsPresentation(useThawBar: false, alwaysShowHiddenItems: false) == .onClick)
    }

    @Test("Only the Thaw Bar switch reads as the Thaw Bar")
    func onlyThawBar() {
        #expect(HiddenItemsPresentation(useThawBar: true, alwaysShowHiddenItems: false) == .thawBar)
    }

    @Test("Only the always-show switch reads as always shown")
    func onlyAlwaysShow() {
        #expect(HiddenItemsPresentation(useThawBar: false, alwaysShowHiddenItems: true) == .alwaysShown)
    }

    @Test("Both switches on reads as the Thaw Bar, which is what the user sees today")
    func bothSwitches() {
        #expect(HiddenItemsPresentation(useThawBar: true, alwaysShowHiddenItems: true) == .thawBar)
    }

    @Test("Each choice writes the two switches it stands for")
    func writesSwitches() {
        #expect(HiddenItemsPresentation.onClick.switches == HiddenItemsPresentation.Switches(useThawBar: false, alwaysShowHiddenItems: false))
        #expect(HiddenItemsPresentation.thawBar.switches == HiddenItemsPresentation.Switches(useThawBar: true, alwaysShowHiddenItems: false))
        #expect(HiddenItemsPresentation.alwaysShown.switches == HiddenItemsPresentation.Switches(useThawBar: false, alwaysShowHiddenItems: true))
    }

    @Test("A written choice reads back as itself", arguments: HiddenItemsPresentation.allCases)
    func roundTrips(choice: HiddenItemsPresentation) {
        let switches = choice.switches
        #expect(HiddenItemsPresentation(useThawBar: switches.useThawBar, alwaysShowHiddenItems: switches.alwaysShowHiddenItems) == choice)
    }

    @Test("Each choice has its own symbol")
    func symbols() {
        let symbols = Set(HiddenItemsPresentation.allCases.map(\.systemImage))
        #expect(symbols.count == 3)
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) is not an SF Symbol")
        }
    }

    @Test("Choosing in the picker writes both bindings and leaves the Thaw Bar settings alone")
    func pickerBindingWrites() {
        var useThawBar = true
        var alwaysShow = true
        let controls = ThawBarConfigurationControls(
            alwaysShowHiddenItems: Binding { alwaysShow } set: { alwaysShow = $0 },
            useThawBar: Binding { useThawBar } set: { useThawBar = $0 },
            location: .constant(.dynamic),
            layout: .constant(.horizontal),
            gridColumns: .constant(4),
            context: .display
        )
        #expect(controls.presentation.wrappedValue == .thawBar)
        controls.presentation.wrappedValue = .alwaysShown
        #expect(!useThawBar)
        #expect(alwaysShow)
        controls.presentation.wrappedValue = .onClick
        #expect(!useThawBar)
        #expect(!alwaysShow)
        controls.presentation.wrappedValue = .thawBar
        #expect(useThawBar)
        #expect(!alwaysShow)
    }

    @Test("The controls draw for a display and for the global template")
    func controlsDraw() throws {
        for context in [ThawBarConfigurationControls<EmptyView>.Context.display, .globalTemplate] {
            let view = Form {
                ThawBarConfigurationControls(
                    alwaysShowHiddenItems: .constant(false),
                    useThawBar: .constant(true),
                    location: .constant(.dynamic),
                    layout: .constant(.horizontal),
                    gridColumns: .constant(4),
                    context: context
                )
            }
            .frame(width: 520, height: 400)
            let render = OffscreenRender(view, size: CGSize(width: 520, height: 400))
            #expect(try render.pixels().contains { $0 != 0 })
        }
    }
}
