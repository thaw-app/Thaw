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
    // MARK: - Raw Value Tests

    func testRawValues() {
        XCTAssertEqual(HotkeyAction.toggleHiddenSection.rawValue, "ToggleHiddenSection")
        XCTAssertEqual(HotkeyAction.toggleAlwaysHiddenSection.rawValue, "ToggleAlwaysHiddenSection")
        XCTAssertEqual(HotkeyAction.searchMenuBarItems.rawValue, "SearchMenuBarItems")
        XCTAssertEqual(HotkeyAction.enableIceBar.rawValue, "EnableIceBar")
        XCTAssertEqual(HotkeyAction.toggleApplicationMenus.rawValue, "ToggleApplicationMenus")
        XCTAssertEqual(HotkeyAction.profileApply.rawValue, "ProfileApply")
        XCTAssertEqual(HotkeyAction.openMenuBarItem.rawValue, "OpenMenuBarItem")
    }

    // MARK: - Init from Raw Value Tests

    func testInitFromRawValue() {
        XCTAssertEqual(HotkeyAction(rawValue: "ToggleHiddenSection"), .toggleHiddenSection)
        XCTAssertEqual(HotkeyAction(rawValue: "SearchMenuBarItems"), .searchMenuBarItems)
        XCTAssertEqual(HotkeyAction(rawValue: "ProfileApply"), .profileApply)
    }

    func testInitFromInvalidRawValue() {
        XCTAssertNil(HotkeyAction(rawValue: "InvalidAction"))
        XCTAssertNil(HotkeyAction(rawValue: ""))
        XCTAssertNil(HotkeyAction(rawValue: "togglehiddensection")) // case-sensitive
    }

    // MARK: - CaseIterable Tests

    func testAllCasesCount() {
        XCTAssertEqual(HotkeyAction.allCases.count, 7)
    }

    func testAllCasesContainsExpectedActions() {
        let allCases = HotkeyAction.allCases
        XCTAssertTrue(allCases.contains(.toggleHiddenSection))
        XCTAssertTrue(allCases.contains(.toggleAlwaysHiddenSection))
        XCTAssertTrue(allCases.contains(.searchMenuBarItems))
        XCTAssertTrue(allCases.contains(.enableIceBar))
        XCTAssertTrue(allCases.contains(.toggleApplicationMenus))
        XCTAssertTrue(allCases.contains(.profileApply))
        XCTAssertTrue(allCases.contains(.openMenuBarItem))
    }

    // MARK: - Settings Actions Tests

    func testSettingsActionsExcludesProfileApply() {
        let settingsActions = HotkeyAction.settingsActions
        XCTAssertFalse(settingsActions.contains(.profileApply))
    }

    func testSettingsActionsExcludesOpenMenuBarItem() {
        let settingsActions = HotkeyAction.settingsActions
        XCTAssertFalse(settingsActions.contains(.openMenuBarItem))
    }

    func testSettingsActionsContainsOtherActions() {
        let settingsActions = HotkeyAction.settingsActions
        XCTAssertTrue(settingsActions.contains(.toggleHiddenSection))
        XCTAssertTrue(settingsActions.contains(.toggleAlwaysHiddenSection))
        XCTAssertTrue(settingsActions.contains(.searchMenuBarItems))
        XCTAssertTrue(settingsActions.contains(.enableIceBar))
        XCTAssertTrue(settingsActions.contains(.toggleApplicationMenus))
    }

    func testSettingsActionsCount() {
        // All cases minus the externally-handled profileApply and openMenuBarItem.
        XCTAssertEqual(HotkeyAction.settingsActions.count, HotkeyAction.allCases.count - 2)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for action in HotkeyAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(HotkeyAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }

    func testDecodeFromStringJSON() throws {
        let json = "\"ToggleHiddenSection\"".data(using: .utf8)!
        let decoder = JSONDecoder()

        let decoded = try decoder.decode(HotkeyAction.self, from: json)
        XCTAssertEqual(decoded, .toggleHiddenSection)
    }
}
