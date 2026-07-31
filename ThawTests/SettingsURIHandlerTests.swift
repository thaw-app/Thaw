//
//  SettingsURIHandlerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Settings URI handler keys and parsing", .serialized)
struct SettingsURIHandlerTests {
    // MARK: - Static Arrays Validation

    @Test("The supported boolean key table is populated")
    func supportedBooleanKeysNotEmpty() {
        #expect(!SettingsURIHandler.supportedBooleanKeys.isEmpty)
    }

    @Test("The boolean key table carries the expected keys")
    func supportedBooleanKeysContainsExpectedKeys() {
        let keys = SettingsURIHandler.supportedBooleanKeys
        #expect(keys.contains("autoRehide"))
        #expect(keys.contains("showOnClick"))
        #expect(keys.contains("showOnHover"))
        #expect(keys.contains("useIceBar"))
        #expect(keys.contains("enableDiagnosticLogging"))
    }

    @Test("The double key table is populated")
    func doubleKeysNotEmpty() {
        #expect(!SettingsURIHandler.doubleKeys.isEmpty)
    }

    @Test("The double key table carries the expected keys")
    func doubleKeysContainsExpectedKeys() {
        let keys = SettingsURIHandler.doubleKeys
        #expect(keys.contains("rehideInterval"))
        #expect(keys.contains("showOnHoverDelay"))
        #expect(keys.contains("tooltipDelay"))
        #expect(keys.contains("iconRefreshInterval"))
    }

    @Test("The enum key table is populated")
    func enumKeysNotEmpty() {
        #expect(!SettingsURIHandler.enumKeys.isEmpty)
    }

    @Test("The enum key table carries rehideStrategy")
    func enumKeysContainsRehideStrategy() {
        #expect(SettingsURIHandler.enumKeys.contains("rehideStrategy"))
    }

    @Test("The per-display key table is populated")
    func perDisplayKeysNotEmpty() {
        #expect(!SettingsURIHandler.perDisplayKeys.isEmpty)
    }

    @Test("The per-display key table carries the expected keys")
    func perDisplayKeysContainsExpectedKeys() {
        let keys = SettingsURIHandler.perDisplayKeys
        #expect(keys.contains("useIceBar"))
        #expect(keys.contains("iceBarLocation"))
        #expect(keys.contains("alwaysShowHiddenItems"))
        #expect(keys.contains("iceBarLayout"))
        #expect(keys.contains("gridColumns"))
    }

    // MARK: - isValidSettingsKey() Tests

    @Test("A boolean key is a valid settings key")
    func isValidSettingsKeyWithBooleanKey() {
        #expect(SettingsURIHandler.isValidSettingsKey("autoRehide"))
        #expect(SettingsURIHandler.isValidSettingsKey("showOnClick"))
        #expect(SettingsURIHandler.isValidSettingsKey("enableDiagnosticLogging"))
    }

    @Test("A double key is a valid settings key")
    func isValidSettingsKeyWithDoubleKey() {
        #expect(SettingsURIHandler.isValidSettingsKey("rehideInterval"))
        #expect(SettingsURIHandler.isValidSettingsKey("showOnHoverDelay"))
        #expect(SettingsURIHandler.isValidSettingsKey("tooltipDelay"))
    }

    @Test("An enum key is a valid settings key")
    func isValidSettingsKeyWithEnumKey() {
        #expect(SettingsURIHandler.isValidSettingsKey("rehideStrategy"))
    }

    @Test("A per-display key is a valid settings key")
    func isValidSettingsKeyWithPerDisplayKey() {
        #expect(SettingsURIHandler.isValidSettingsKey("useIceBar"))
        #expect(SettingsURIHandler.isValidSettingsKey("iceBarLocation"))
        #expect(SettingsURIHandler.isValidSettingsKey("alwaysShowHiddenItems"))
        #expect(SettingsURIHandler.isValidSettingsKey("iceBarLayout"))
        #expect(SettingsURIHandler.isValidSettingsKey("gridColumns"))
    }

    @Test("An unknown key is not a valid settings key")
    func isValidSettingsKeyWithUnknownKey() {
        #expect(!SettingsURIHandler.isValidSettingsKey("unknownKey"))
        #expect(!SettingsURIHandler.isValidSettingsKey("notAKey"))
        #expect(!SettingsURIHandler.isValidSettingsKey("randomSetting"))
    }

    @Test("The empty string is not a valid settings key")
    func isValidSettingsKeyWithEmptyString() {
        #expect(!SettingsURIHandler.isValidSettingsKey(""))
    }

    @Test("A prefix of a real key is not a valid settings key")
    func isValidSettingsKeyWithPartialMatch() {
        // Should not match partial key names
        #expect(!SettingsURIHandler.isValidSettingsKey("autoRe"))
        #expect(!SettingsURIHandler.isValidSettingsKey("show"))
        #expect(!SettingsURIHandler.isValidSettingsKey("rehide"))
    }

    @Test("Key validation is case sensitive")
    func isValidSettingsKeyIsCaseSensitive() {
        #expect(!SettingsURIHandler.isValidSettingsKey("AUTOREHIDE"))
        #expect(!SettingsURIHandler.isValidSettingsKey("AutoRehide"))
        #expect(!SettingsURIHandler.isValidSettingsKey("SHOWONCLICK"))
    }

    // MARK: - parseBool() Tests

    @Test("Every spelling of \"true\" parses as true")
    func parseBoolTrue() {
        #expect(SettingsURIHandler.parseBool("true") == true)
        #expect(SettingsURIHandler.parseBool("TRUE") == true)
        #expect(SettingsURIHandler.parseBool("True") == true)
        #expect(SettingsURIHandler.parseBool("tRuE") == true)
    }

    @Test("\"1\" parses as true")
    func parseBoolOne() {
        #expect(SettingsURIHandler.parseBool("1") == true)
    }

    @Test("Every spelling of \"yes\" parses as true")
    func parseBoolYes() {
        #expect(SettingsURIHandler.parseBool("yes") == true)
        #expect(SettingsURIHandler.parseBool("YES") == true)
        #expect(SettingsURIHandler.parseBool("Yes") == true)
    }

    @Test("Every spelling of \"false\" parses as false")
    func parseBoolFalse() {
        #expect(SettingsURIHandler.parseBool("false") == false)
        #expect(SettingsURIHandler.parseBool("FALSE") == false)
        #expect(SettingsURIHandler.parseBool("False") == false)
        #expect(SettingsURIHandler.parseBool("fAlSe") == false)
    }

    @Test("\"0\" parses as false")
    func parseBoolZero() {
        #expect(SettingsURIHandler.parseBool("0") == false)
    }

    @Test("Every spelling of \"no\" parses as false")
    func parseBoolNo() {
        #expect(SettingsURIHandler.parseBool("no") == false)
        #expect(SettingsURIHandler.parseBool("NO") == false)
        #expect(SettingsURIHandler.parseBool("No") == false)
    }

    @Test("Anything else parses as nil")
    func parseBoolInvalid() {
        #expect(SettingsURIHandler.parseBool("invalid") == nil)
        #expect(SettingsURIHandler.parseBool("") == nil)
        #expect(SettingsURIHandler.parseBool("2") == nil)
        #expect(SettingsURIHandler.parseBool("-1") == nil)
        #expect(SettingsURIHandler.parseBool("truthy") == nil)
        #expect(SettingsURIHandler.parseBool("y") == nil)
        #expect(SettingsURIHandler.parseBool("n") == nil)
    }

    // MARK: - parseDouble() Tests

    @Test("A well-formed double parses to its value")
    func parseDoubleValid() {
        #expect(SettingsURIHandler.parseDouble("1.5") == 1.5)
        #expect(SettingsURIHandler.parseDouble("0") == 0.0)
        #expect(SettingsURIHandler.parseDouble("0.0") == 0.0)
        #expect(SettingsURIHandler.parseDouble("100") == 100.0)
    }

    @Test("A negative double parses to its value")
    func parseDoubleNegative() {
        #expect(SettingsURIHandler.parseDouble("-1.5") == -1.5)
        #expect(SettingsURIHandler.parseDouble("-100") == -100.0)
    }

    @Test("Scientific notation parses to its value")
    func parseDoubleScientificNotation() {
        #expect(SettingsURIHandler.parseDouble("1e10") == 1e10)
        #expect(SettingsURIHandler.parseDouble("1.5e-3") == 1.5e-3)
    }

    @Test("A malformed double parses as nil")
    func parseDoubleInvalid() {
        #expect(SettingsURIHandler.parseDouble("invalid") == nil)
        #expect(SettingsURIHandler.parseDouble("") == nil)
        #expect(SettingsURIHandler.parseDouble("1.2.3") == nil)
        #expect(SettingsURIHandler.parseDouble("abc123") == nil)
        #expect(SettingsURIHandler.parseDouble("12abc") == nil)
    }

    // MARK: - PerDisplayScope Tests

    @Test("The active display scope spells itself \"active\"")
    func perDisplayScopeActiveDisplayRawValue() {
        #expect(SettingsURIHandler.PerDisplayScope.activeDisplay.rawValue == "active")
    }

    @Test("The all-enabled scope spells itself \"allEnabled\"")
    func perDisplayScopeAllEnabledDisplaysRawValue() {
        #expect(SettingsURIHandler.PerDisplayScope.allEnabledDisplays.rawValue == "allEnabled")
    }

    @Test("The all-non-Ice-Bar scope spells itself \"allNonIceBar\"")
    func perDisplayScopeAllNonIceBarDisplaysRawValue() {
        #expect(SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays.rawValue == "allNonIceBar")
    }

    @Test("A specific display scope embeds its UUID in the raw value")
    func perDisplayScopeSpecificDisplayRawValue() {
        let scope = SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "ABC-123-DEF")
        #expect(scope.rawValue == "specific:ABC-123-DEF")
    }

    @Test("A non-specific scope has no specific UUID")
    func perDisplayScopeSpecificUUIDReturnsNilForNonSpecific() {
        #expect(SettingsURIHandler.PerDisplayScope.activeDisplay.specificUUID == nil)
        #expect(SettingsURIHandler.PerDisplayScope.allEnabledDisplays.specificUUID == nil)
        #expect(SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays.specificUUID == nil)
    }

    @Test("A specific scope hands back the UUID it was built with")
    func perDisplayScopeSpecificUUIDReturnsUUIDForSpecific() {
        let uuid = "ABC-123-DEF-456"
        let scope = SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: uuid)
        #expect(scope.specificUUID == uuid)
    }

    @Test("Identical scope cases are equal")
    func perDisplayScopeEquatableSameCases() {
        #expect(
            SettingsURIHandler.PerDisplayScope.activeDisplay
                == SettingsURIHandler.PerDisplayScope.activeDisplay
        )
        #expect(
            SettingsURIHandler.PerDisplayScope.allEnabledDisplays
                == SettingsURIHandler.PerDisplayScope.allEnabledDisplays
        )
        #expect(
            SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays
                == SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays
        )
    }

    @Test("Different scope cases are not equal")
    func perDisplayScopeEquatableDifferentCases() {
        #expect(
            SettingsURIHandler.PerDisplayScope.activeDisplay
                != SettingsURIHandler.PerDisplayScope.allEnabledDisplays
        )
        #expect(
            SettingsURIHandler.PerDisplayScope.activeDisplay
                != SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays
        )
        #expect(
            SettingsURIHandler.PerDisplayScope.allEnabledDisplays
                != SettingsURIHandler.PerDisplayScope.allNonIceBarDisplays
        )
    }

    @Test("Two specific scopes with the same UUID are equal")
    func perDisplayScopeEquatableSpecificSameUUID() {
        let uuid = "SAME-UUID-123"
        #expect(
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: uuid)
                == SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: uuid)
        )
    }

    @Test("Two specific scopes with different UUIDs are not equal")
    func perDisplayScopeEquatableSpecificDifferentUUID() {
        #expect(
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "UUID-1")
                != SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "UUID-2")
        )
    }

    @Test("A specific scope is not equal to a non-specific one")
    func perDisplayScopeEquatableSpecificVsOther() {
        #expect(
            SettingsURIHandler.PerDisplayScope.specificDisplay(uuid: "UUID-1")
                != SettingsURIHandler.PerDisplayScope.activeDisplay
        )
    }
}
