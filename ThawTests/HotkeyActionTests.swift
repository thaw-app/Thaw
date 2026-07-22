//
//  HotkeyActionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class HotkeyActionTests: XCTestCase {
    func testCasesAndRawValuesRemainStable() {
        let expected: [(HotkeyAction, String)] = [
            (.toggleHiddenSection, "ToggleHiddenSection"),
            (.toggleAlwaysHiddenSection, "ToggleAlwaysHiddenSection"),
            (.searchMenuBarItems, "SearchMenuBarItems"),
            (.enableIceBar, "EnableIceBar"),
            (.toggleApplicationMenus, "ToggleApplicationMenus"),
            (.profileApply, "ProfileApply"),
            (.openMenuBarItem, "OpenMenuBarItem"),
        ]

        XCTAssertEqual(HotkeyAction.allCases, expected.map(\.0))
        for (action, rawValue) in expected {
            XCTAssertEqual(action.rawValue, rawValue)
            XCTAssertEqual(HotkeyAction(rawValue: rawValue), action)
        }
        XCTAssertNil(HotkeyAction(rawValue: "InvalidAction"))
        XCTAssertNil(HotkeyAction(rawValue: ""))
        XCTAssertNil(HotkeyAction(rawValue: "togglehiddensection")) // case-sensitive
    }

    func testSettingsActionsExcludeExternallyHandledActions() {
        XCTAssertEqual(
            HotkeyAction.settingsActions,
            [.toggleHiddenSection, .toggleAlwaysHiddenSection, .searchMenuBarItems, .enableIceBar, .toggleApplicationMenus]
        )
    }

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for action in HotkeyAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(HotkeyAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }
}
