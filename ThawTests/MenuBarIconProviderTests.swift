//
//  MenuBarIconProviderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MenuBarIconProviderTests: XCTestCase {
    // MARK: - SF Symbol Map Tests

    func testSystemSymbolMapIsNotEmpty() {
        XCTAssertFalse(
            MenuBarIconProvider.systemSymbolMap.isEmpty,
            "System symbol map should contain mappings"
        )
    }

    func testAllMappedSFSymbolsExist() {
        var missingSymbols = [String]()

        for (title, symbolName) in MenuBarIconProvider.systemSymbolMap {
            if NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) == nil {
                missingSymbols.append("\(title) -> \(symbolName)")
            }
        }

        XCTAssertTrue(
            missingSymbols.isEmpty,
            "The following SF Symbols do not exist: \(missingSymbols.joined(separator: ", "))"
        )
    }

    func testKnownSystemItemMappings() {
        // Verify critical system items are mapped
        let expectedMappings: [String: String] = [
            "WiFi": "wifi",
            "Battery": "battery.100percent",
            "Sound": "speaker.wave.2.fill",
            "Bluetooth": "NSBluetoothTemplate", // Note: This is in systemNamedImageMap, not symbolMap
        ]

        // Check SF Symbol mappings
        XCTAssertEqual(MenuBarIconProvider.systemSymbolMap["WiFi"], "wifi")
        XCTAssertEqual(MenuBarIconProvider.systemSymbolMap["Battery"], "battery.100percent")
        XCTAssertEqual(MenuBarIconProvider.systemSymbolMap["Sound"], "speaker.wave.2.fill")
        XCTAssertEqual(MenuBarIconProvider.systemSymbolMap["Display"], "sun.max.fill")
        XCTAssertEqual(MenuBarIconProvider.systemSymbolMap["Focus"], "moon.fill")
        XCTAssertEqual(MenuBarIconProvider.systemSymbolMap["FocusModes"], "moon.fill")
    }

    func testTimeMachineVariantsAllMapToSameSymbol() {
        // TimeMachine has multiple title variants that should all map to the same symbol
        let expectedSymbol = "clock.arrow.circlepath"

        let timeMachineKeys = [
            "com.apple.menuextra.TimeMachine",
            "TimeMachineMenuExtra.TMMenuExtraHost",
            "TimeMachine.TMMenuExtraHost",
        ]

        for key in timeMachineKeys {
            XCTAssertEqual(
                MenuBarIconProvider.systemSymbolMap[key],
                expectedSymbol,
                "TimeMachine variant '\(key)' should map to '\(expectedSymbol)'"
            )
        }
    }

    // MARK: - Named Image Map Tests

    func testSystemNamedImageMapIsNotEmpty() {
        XCTAssertFalse(
            MenuBarIconProvider.systemNamedImageMap.isEmpty,
            "System named image map should contain mappings"
        )
    }

    func testBluetoothMapsToNamedImage() {
        XCTAssertEqual(
            MenuBarIconProvider.systemNamedImageMap["Bluetooth"],
            "NSBluetoothTemplate"
        )
    }

    func testAllMappedNamedImagesExist() {
        var missingImages = [String]()

        for (title, imageName) in MenuBarIconProvider.systemNamedImageMap {
            if NSImage(named: NSImage.Name(imageName)) == nil {
                missingImages.append("\(title) -> \(imageName)")
            }
        }

        XCTAssertTrue(
            missingImages.isEmpty,
            "The following named images do not exist: \(missingImages.joined(separator: ", "))"
        )
    }

    // MARK: - Map Completeness Tests

    func testNoOverlapBetweenMaps() {
        // Ensure no title appears in both maps (would cause ambiguity)
        let symbolKeys = Set(MenuBarIconProvider.systemSymbolMap.keys)
        let namedImageKeys = Set(MenuBarIconProvider.systemNamedImageMap.keys)

        let overlap = symbolKeys.intersection(namedImageKeys)

        XCTAssertTrue(
            overlap.isEmpty,
            "These titles appear in both maps: \(overlap)"
        )
    }

    func testAllMapKeysAreNonEmpty() {
        for key in MenuBarIconProvider.systemSymbolMap.keys {
            XCTAssertFalse(key.isEmpty, "Symbol map contains empty key")
        }

        for key in MenuBarIconProvider.systemNamedImageMap.keys {
            XCTAssertFalse(key.isEmpty, "Named image map contains empty key")
        }
    }

    func testAllMapValuesAreNonEmpty() {
        for (key, value) in MenuBarIconProvider.systemSymbolMap {
            XCTAssertFalse(value.isEmpty, "Symbol map value for '\(key)' is empty")
        }

        for (key, value) in MenuBarIconProvider.systemNamedImageMap {
            XCTAssertFalse(value.isEmpty, "Named image map value for '\(key)' is empty")
        }
    }
}
