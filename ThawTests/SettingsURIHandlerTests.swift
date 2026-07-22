//
//  SettingsURIHandlerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class SettingsURIHandlerTests: XCTestCase {
    // MARK: - Static Arrays Validation

    func testSupportedBooleanKeysNotEmpty() {
        XCTAssertFalse(SettingsURIHandler.supportedBooleanKeys.isEmpty)
    }

    func testSupportedBooleanKeysContainsExpectedKeys() {
        let keys = SettingsURIHandler.supportedBooleanKeys
        XCTAssertTrue(keys.contains("autoRehide"))
        XCTAssertTrue(keys.contains("showOnClick"))
        XCTAssertTrue(keys.contains("showOnHover"))
        XCTAssertTrue(keys.contains("useIceBar"))
        XCTAssertTrue(keys.contains("enableDiagnosticLogging"))
        XCTAssertTrue(keys.contains("enableExperimentalOverflowPrevention"))
        XCTAssertTrue(keys.contains("alwaysUseAppIconForMenuBarItems"))
    }

    func testDoubleKeysNotEmpty() {
        XCTAssertFalse(SettingsURIHandler.doubleKeys.isEmpty)
    }

    func testDoubleKeysContainsExpectedKeys() {
        let keys = SettingsURIHandler.doubleKeys
        XCTAssertTrue(keys.contains("rehideInterval"))
        XCTAssertTrue(keys.contains("showOnHoverDelay"))
        XCTAssertTrue(keys.contains("tooltipDelay"))
        XCTAssertTrue(keys.contains("iconRefreshInterval"))
    }

    func testEnumKeysNotEmpty() {
        XCTAssertFalse(SettingsURIHandler.enumKeys.isEmpty)
    }

    func testEnumKeysContainsRehideStrategy() {
        XCTAssertTrue(SettingsURIHandler.enumKeys.contains("rehideStrategy"))
    }

    func testPerDisplayKeysNotEmpty() {
        XCTAssertFalse(SettingsURIHandler.perDisplayKeys.isEmpty)
    }

    func testPerDisplayKeysContainsExpectedKeys() {
        let keys = SettingsURIHandler.perDisplayKeys
        XCTAssertTrue(keys.contains("useIceBar"))
        XCTAssertTrue(keys.contains("iceBarLocation"))
        XCTAssertTrue(keys.contains("alwaysShowHiddenItems"))
        XCTAssertTrue(keys.contains("iceBarLayout"))
        XCTAssertTrue(keys.contains("gridColumns"))
    }

    // MARK: - isValidSettingsKey() Tests

    func testIsValidSettingsKeyWithBooleanKey() {
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("autoRehide"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("showOnClick"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("enableDiagnosticLogging"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("enableExperimentalOverflowPrevention"))
    }

    func testSetAndToggleEnableExperimentalOverflowPreventionViaURI() {
        let original = Defaults.bool(forKey: .enableExperimentalOverflowPrevention)
        defer {
            Defaults.set(original, forKey: .enableExperimentalOverflowPrevention)
        }

        XCTAssertTrue(SettingsURIHandler.handleSet(key: "enableExperimentalOverflowPrevention", value: "true", sender: nil))
        XCTAssertTrue(Defaults.bool(forKey: .enableExperimentalOverflowPrevention))

        XCTAssertTrue(SettingsURIHandler.handleToggle(key: "enableExperimentalOverflowPrevention", sender: nil))
        XCTAssertFalse(Defaults.bool(forKey: .enableExperimentalOverflowPrevention))
    }

    func testIsValidSettingsKeyWithDoubleKey() {
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("rehideInterval"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("showOnHoverDelay"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("tooltipDelay"))
    }

    func testIsValidSettingsKeyWithEnumKey() {
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("rehideStrategy"))
    }

    func testIsValidSettingsKeyWithPerDisplayKey() {
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("useIceBar"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("iceBarLocation"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("alwaysShowHiddenItems"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("iceBarLayout"))
        XCTAssertTrue(SettingsURIHandler.isValidSettingsKey("gridColumns"))
    }

    func testIsValidSettingsKeyWithUnknownKey() {
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("unknownKey"))
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("notAKey"))
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("randomSetting"))
    }

    func testIsValidSettingsKeyWithEmptyString() {
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey(""))
    }

    func testIsValidSettingsKeyWithPartialMatch() {
        // Should not match partial key names
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("autoRe"))
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("show"))
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("rehide"))
    }

    func testIsValidSettingsKeyIsCaseSensitive() {
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("AUTOREHIDE"))
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("AutoRehide"))
        XCTAssertFalse(SettingsURIHandler.isValidSettingsKey("SHOWONCLICK"))
    }

    // MARK: - parseBool() Tests

    func testParseBoolTrue() {
        XCTAssertEqual(SettingsURIHandler.parseBool("true"), true)
        XCTAssertEqual(SettingsURIHandler.parseBool("TRUE"), true)
        XCTAssertEqual(SettingsURIHandler.parseBool("True"), true)
        XCTAssertEqual(SettingsURIHandler.parseBool("tRuE"), true)
    }

    func testParseBoolOne() {
        XCTAssertEqual(SettingsURIHandler.parseBool("1"), true)
    }

    func testParseBoolYes() {
        XCTAssertEqual(SettingsURIHandler.parseBool("yes"), true)
        XCTAssertEqual(SettingsURIHandler.parseBool("YES"), true)
        XCTAssertEqual(SettingsURIHandler.parseBool("Yes"), true)
    }

    func testParseBoolFalse() {
        XCTAssertEqual(SettingsURIHandler.parseBool("false"), false)
        XCTAssertEqual(SettingsURIHandler.parseBool("FALSE"), false)
        XCTAssertEqual(SettingsURIHandler.parseBool("False"), false)
        XCTAssertEqual(SettingsURIHandler.parseBool("fAlSe"), false)
    }

    func testParseBoolZero() {
        XCTAssertEqual(SettingsURIHandler.parseBool("0"), false)
    }

    func testParseBoolNo() {
        XCTAssertEqual(SettingsURIHandler.parseBool("no"), false)
        XCTAssertEqual(SettingsURIHandler.parseBool("NO"), false)
        XCTAssertEqual(SettingsURIHandler.parseBool("No"), false)
    }

    func testParseBoolInvalid() {
        XCTAssertNil(SettingsURIHandler.parseBool("invalid"))
        XCTAssertNil(SettingsURIHandler.parseBool(""))
        XCTAssertNil(SettingsURIHandler.parseBool("2"))
        XCTAssertNil(SettingsURIHandler.parseBool("-1"))
        XCTAssertNil(SettingsURIHandler.parseBool("truthy"))
        XCTAssertNil(SettingsURIHandler.parseBool("y"))
        XCTAssertNil(SettingsURIHandler.parseBool("n"))
    }

    // MARK: - parseDouble() Tests

    func testParseDoubleValid() {
        XCTAssertEqual(SettingsURIHandler.parseDouble("1.5"), 1.5)
        XCTAssertEqual(SettingsURIHandler.parseDouble("0"), 0.0)
        XCTAssertEqual(SettingsURIHandler.parseDouble("0.0"), 0.0)
        XCTAssertEqual(SettingsURIHandler.parseDouble("100"), 100.0)
    }

    func testParseDoubleNegative() {
        XCTAssertEqual(SettingsURIHandler.parseDouble("-1.5"), -1.5)
        XCTAssertEqual(SettingsURIHandler.parseDouble("-100"), -100.0)
    }

    func testParseDoubleScientificNotation() {
        XCTAssertEqual(SettingsURIHandler.parseDouble("1e10"), 1e10)
        XCTAssertEqual(SettingsURIHandler.parseDouble("1.5e-3"), 1.5e-3)
    }

    func testParseDoubleInvalid() {
        XCTAssertNil(SettingsURIHandler.parseDouble("invalid"))
        XCTAssertNil(SettingsURIHandler.parseDouble(""))
        XCTAssertNil(SettingsURIHandler.parseDouble("1.2.3"))
        XCTAssertNil(SettingsURIHandler.parseDouble("abc123"))
        XCTAssertNil(SettingsURIHandler.parseDouble("12abc"))
    }

    // MARK: - PerDisplayScope Tests

    func testPerDisplayScopeActiveDisplayRawValue() {
        XCTAssertEqual(SettingsURIHandler.PerDisplayScope.activeDisplay.rawValue, "active")
    }

    func testPerDisplayScopeAllEnabledDisplaysRawValue() {
        XCTAssertEqual(SettingsURIHandler.PerDisplayScope.allEnabledDisplays.rawValue, "allEnabled")
    }

    func testPerDisplayScopeAllNonIceBarDisplaysRawValue() {
        XCTAssertEqual(SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays.rawValue, "allNonIceBar")
    }

    func testPerDisplayScopeSpecificDisplayRawValue() {
        let scope = SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "ABC-123-DEF")
        XCTAssertEqual(scope.rawValue, "specific:ABC-123-DEF")
    }

    func testPerDisplayScopeSpecificUUIDReturnsNilForNonSpecific() {
        XCTAssertNil(SettingsURIHandler.PerDisplayScope.activeDisplay.specificUUID)
        XCTAssertNil(SettingsURIHandler.PerDisplayScope.allEnabledDisplays.specificUUID)
        XCTAssertNil(SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays.specificUUID)
    }

    func testPerDisplayScopeSpecificUUIDReturnsUUIDForSpecific() {
        let uuid = "ABC-123-DEF-456"
        let scope = SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: uuid)
        XCTAssertEqual(scope.specificUUID, uuid)
    }

    func testPerDisplayScopeEquatableSameCases() {
        XCTAssertEqual(
            SettingsURIHandler.PerDisplayScope.activeDisplay,
            SettingsURIHandler.PerDisplayScope.activeDisplay
        )
        XCTAssertEqual(
            SettingsURIHandler.PerDisplayScope.allEnabledDisplays,
            SettingsURIHandler.PerDisplayScope.allEnabledDisplays
        )
        XCTAssertEqual(
            SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays,
            SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays
        )
    }

    func testPerDisplayScopeEquatableDifferentCases() {
        XCTAssertNotEqual(
            SettingsURIHandler.PerDisplayScope.activeDisplay,
            SettingsURIHandler.PerDisplayScope.allEnabledDisplays
        )
        XCTAssertNotEqual(
            SettingsURIHandler.PerDisplayScope.activeDisplay,
            SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays
        )
        XCTAssertNotEqual(
            SettingsURIHandler.PerDisplayScope.allEnabledDisplays,
            SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays
        )
    }

    func testPerDisplayScopeEquatableSpecificSameUUID() {
        let uuid = "SAME-UUID-123"
        XCTAssertEqual(
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: uuid),
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: uuid)
        )
    }

    func testPerDisplayScopeEquatableSpecificDifferentUUID() {
        XCTAssertNotEqual(
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "UUID-1"),
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "UUID-2")
        )
    }

    func testPerDisplayScopeEquatableSpecificVsOther() {
        XCTAssertNotEqual(
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "UUID-1"),
            SettingsURIHandler.PerDisplayScope.activeDisplay
        )
    }

    // MARK: - resolveRevealItemIdentifier() Tests

    func testResolveRevealItemIdentifierWithItemIDReturnsCanonicalIdentifier() {
        let identifier = SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: nil,
            itemID: "com.bjango.istatmenus.cpu:CPU",
            sectionAssignment: [:]
        )
        XCTAssertEqual(identifier, "com.bjango.istatmenus.cpu:CPU")
    }

    func testResolveRevealItemIdentifierWithBundleResolvesSingleAssignedMatch() {
        let sectionAssignment: [String: MenuBarSection.Name] = [
            "com.example.app:MenuExtra": .hidden,
            "com.other.app:MenuExtra": .alwaysHidden,
        ]
        let identifier = SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: "com.example.app",
            itemID: nil,
            sectionAssignment: sectionAssignment
        )
        XCTAssertEqual(identifier, "com.example.app:MenuExtra")
    }

    func testResolveRevealItemIdentifierRejectsAmbiguousOrMissingParams() {
        // Neither bundle nor item-id provided.
        XCTAssertNil(SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: nil,
            itemID: nil,
            sectionAssignment: [:]
        ))

        // Both bundle and item-id provided.
        XCTAssertNil(SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: "com.example.app",
            itemID: "com.example.app:MenuExtra",
            sectionAssignment: [:]
        ))

        // Bundle matches zero assigned items.
        XCTAssertNil(SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: "com.unknown.app",
            itemID: nil,
            sectionAssignment: ["com.example.app:MenuExtra": .hidden]
        ))

        // Bundle matches more than one assigned item (ambiguous).
        let ambiguousAssignment: [String: MenuBarSection.Name] = [
            "com.bjango.istatmenus.cpu:CPU": .hidden,
            "com.bjango.istatmenus.cpu:Memory": .alwaysHidden,
        ]
        XCTAssertNil(SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: "com.bjango.istatmenus.cpu",
            itemID: nil,
            sectionAssignment: ambiguousAssignment
        ))
    }
}
