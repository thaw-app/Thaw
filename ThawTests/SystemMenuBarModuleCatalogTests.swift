//
//  SystemMenuBarModuleCatalogTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
@testable import Thaw
import XCTest

/// Characterization suite for ``SystemMenuBarModuleCatalog``. These lock in the
/// exact mappings the catalog replaced in ``RuntimeModuleController`` and
/// ``RuntimeSessionController`` so the relocation stays behavior-preserving.
final class SystemMenuBarModuleCatalogTests: XCTestCase {
    // MARK: - Control Center mapping parity

    func testControlCenterKeysMatchOriginalLiteral() {
        // The exact dictionary RuntimeModuleController used before the
        // catalog. Any drift here is a runtime CC-governance change.
        XCTAssertEqual(
            SystemMenuBarModuleCatalog.controlCenterKeysByMenuExtraTitle,
            [
                "com.apple.menuextra.airdrop": "AirDrop",
                "com.apple.menuextra.bluetooth": "Bluetooth",
                "com.apple.menuextra.wifi": "WiFi",
                "com.apple.menuextra.now-playing": "NowPlaying",
                "com.apple.menuextra.user": "UserSwitcher",
                "com.apple.menuextra.focusmode": "FocusModes",
            ]
        )
    }

    func testRuntimeModuleControllerExposesCatalogMap() {
        XCTAssertEqual(
            RuntimeModuleController.moduleKeysByMenuExtraTitle,
            SystemMenuBarModuleCatalog.controlCenterKeysByMenuExtraTitle
        )
    }

    // MARK: - Assessment index mapping parity

    func testAssessmentSystemItemIDMatchesOriginalSwitch() {
        // Every (title → id) pair from the pre-catalog switch, exhaustively.
        let expected: [String: Int] = [
            "Battery": 0,
            "Bluetooth": 1, "com.apple.menuextra.bluetooth": 1,
            "Clock": 2, "com.apple.menuextra.clock": 2,
            "Displays": 3, "Display": 3, "com.apple.menuextra.displays": 3,
            "Keyboard": 4, "com.apple.menuextra.keyboard": 4,
            "Sound": 5, "Volume": 5, "com.apple.menuextra.volume": 5,
            "WiFi": 6, "Wi-Fi": 6, "com.apple.menuextra.wifi": 6,
            "ScreenMirroring": 7, "Screen Mirroring": 7, "com.apple.menuextra.screenmirroring": 7,
            "BentoBox-0": 8, "ControlCenter": 8, "com.apple.menuextra.controlcenter": 8,
        ]
        for (title, id) in expected {
            XCTAssertEqual(
                SystemMenuBarModuleCatalog.assessmentSystemItemID(forTitle: title),
                id,
                "title \(title) should map to \(id)"
            )
        }
    }

    func testAssessmentSystemItemIDNilForUnknownTitle() {
        XCTAssertNil(SystemMenuBarModuleCatalog.assessmentSystemItemID(forTitle: "AirDrop"))
        XCTAssertNil(SystemMenuBarModuleCatalog.assessmentSystemItemID(forTitle: "Alpha"))
        XCTAssertNil(SystemMenuBarModuleCatalog.assessmentSystemItemID(forTitle: ""))
    }

    func testTrailingPositionsModuleKeyUsesCanonicalPrefix() {
        XCTAssertEqual(
            SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: "WiFi"),
            "module:WiFi"
        )
        XCTAssertEqual(
            SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: "com.apple.menuextra.display"),
            "module:Display"
        )
        XCTAssertEqual(
            SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: "com.apple.menuextra.sound"),
            "module:Sound"
        )
    }

    func testEveryAssessmentIndexZeroThroughEightIsRepresentedOnce() {
        let ids = SystemMenuBarModuleCatalog.all.compactMap(\.assessmentSystemItemID).sorted()
        XCTAssertEqual(ids, Array(0 ... 8))
    }

    // MARK: - Catalog integrity

    func testNoDuplicateMenuExtraTitles() {
        let titles = SystemMenuBarModuleCatalog.all.compactMap(\.controlCenterMenuExtraTitle)
        XCTAssertEqual(titles.count, Set(titles).count, "duplicate Control Center menu-extra titles")
    }

    func testAssessmentTitleAliasesAreDisjointAcrossModules() {
        var seen = Set<String>()
        for module in SystemMenuBarModuleCatalog.all {
            for alias in module.assessmentTitleAliases {
                XCTAssertTrue(seen.insert(alias).inserted, "alias \(alias) claimed by more than one module")
            }
        }
    }

    func testEveryModuleWithAliasesHasAnIDAndViceVersa() {
        for module in SystemMenuBarModuleCatalog.all {
            XCTAssertEqual(
                module.assessmentSystemItemID != nil,
                !module.assessmentTitleAliases.isEmpty,
                "\(module.name): assessment ID and title aliases must be present together"
            )
        }
    }
}
