//
//  HotkeyActionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Hotkey action")
struct HotkeyActionTests {
    // MARK: - Raw Value Tests

    @Test("Every action keeps its historical raw value")
    func rawValues() {
        #expect(HotkeyAction.toggleHiddenSection.rawValue == "ToggleHiddenSection")
        #expect(HotkeyAction.toggleAlwaysHiddenSection.rawValue == "ToggleAlwaysHiddenSection")
        #expect(HotkeyAction.searchMenuBarItems.rawValue == "SearchMenuBarItems")
        #expect(HotkeyAction.enableIceBar.rawValue == "EnableIceBar")
        #expect(HotkeyAction.toggleApplicationMenus.rawValue == "ToggleApplicationMenus")
        #expect(HotkeyAction.toggleAutoRehide.rawValue == "ToggleAutoRehide")
        #expect(HotkeyAction.profileApply.rawValue == "ProfileApply")
        #expect(HotkeyAction.openMenuBarItem.rawValue == "OpenMenuBarItem")
    }

    // MARK: - Init from Raw Value Tests

    @Test("A known raw value produces its action")
    func initFromRawValue() {
        #expect(HotkeyAction(rawValue: "ToggleHiddenSection") == .toggleHiddenSection)
        #expect(HotkeyAction(rawValue: "SearchMenuBarItems") == .searchMenuBarItems)
        #expect(HotkeyAction(rawValue: "ProfileApply") == .profileApply)
    }

    @Test("An unknown raw value produces nil")
    func initFromInvalidRawValue() {
        #expect(HotkeyAction(rawValue: "InvalidAction") == nil)
        #expect(HotkeyAction(rawValue: "") == nil)
        #expect(HotkeyAction(rawValue: "togglehiddensection") == nil) // case-sensitive
    }

    // MARK: - CaseIterable Tests

    @Test("There are seven actions")
    func allCasesCount() {
        #expect(HotkeyAction.allCases.count == 7)
    }

    @Test("All cases contains every expected action")
    func allCasesContainsExpectedActions() {
        let allCases = HotkeyAction.allCases
        #expect(allCases.contains(.toggleHiddenSection))
        #expect(allCases.contains(.toggleAlwaysHiddenSection))
        #expect(allCases.contains(.searchMenuBarItems))
        #expect(allCases.contains(.enableIceBar))
        #expect(allCases.contains(.toggleApplicationMenus))
        #expect(allCases.contains(.profileApply))
        #expect(allCases.contains(.openMenuBarItem))
    }

    // MARK: - Settings Actions Tests

    @Test("Settings actions excludes profileApply")
    func settingsActionsExcludesProfileApply() {
        let settingsActions = HotkeyAction.settingsActions
        #expect(!settingsActions.contains(.profileApply))
    }

    @Test("Settings actions excludes openMenuBarItem")
    func settingsActionsExcludesOpenMenuBarItem() {
        let settingsActions = HotkeyAction.settingsActions
        #expect(!settingsActions.contains(.openMenuBarItem))
    }

    @Test("Settings actions contains the remaining actions")
    func settingsActionsContainsOtherActions() {
        let settingsActions = HotkeyAction.settingsActions
        #expect(settingsActions.contains(.toggleHiddenSection))
        #expect(settingsActions.contains(.toggleAlwaysHiddenSection))
        #expect(settingsActions.contains(.searchMenuBarItems))
        #expect(settingsActions.contains(.enableIceBar))
        #expect(settingsActions.contains(.toggleApplicationMenus))
        #expect(settingsActions.contains(.toggleAutoRehide))
    }

    @Test("Settings actions is all cases minus two")
    func settingsActionsCount() {
        // All cases minus the externally-handled profileApply and openMenuBarItem.
        #expect(HotkeyAction.settingsActions.count == HotkeyAction.allCases.count - 2)
    }

    // MARK: - Codable Tests

    @Test("Every action survives an encode/decode round trip")
    func encodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for action in HotkeyAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(HotkeyAction.self, from: data)
            #expect(decoded == action)
        }
    }

    @Test("A bare JSON string decodes to its action")
    func decodeFromStringJSON() throws {
        let json = "\"ToggleHiddenSection\"".data(using: .utf8)!
        let decoder = JSONDecoder()

        let decoded = try decoder.decode(HotkeyAction.self, from: json)
        #expect(decoded == .toggleHiddenSection)
    }
}
