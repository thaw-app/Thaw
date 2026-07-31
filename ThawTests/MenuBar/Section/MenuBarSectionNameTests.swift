//
//  MenuBarSectionNameTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import SwiftUI
import Testing
@testable import Thaw

// MARK: - MenuBarSection.Name Tests

@Suite("Menu bar section names")
struct MenuBarSectionNameTests {
    // MARK: - CaseIterable

    @Test("There are three section names")
    func allCasesCount() {
        #expect(MenuBarSection.Name.allCases.count == 3)
    }

    @Test("The cases include visible")
    func allCasesContainsVisible() {
        #expect(MenuBarSection.Name.allCases.contains(.visible))
    }

    @Test("The cases include hidden")
    func allCasesContainsHidden() {
        #expect(MenuBarSection.Name.allCases.contains(.hidden))
    }

    @Test("The cases include alwaysHidden")
    func allCasesContainsAlwaysHidden() {
        #expect(MenuBarSection.Name.allCases.contains(.alwaysHidden))
    }

    // MARK: - displayString

    @Test("visible displays as \"Visible\"")
    func displayStringVisible() {
        #expect(MenuBarSection.Name.visible.displayString == "Visible")
    }

    @Test("hidden displays as \"Hidden\"")
    func displayStringHidden() {
        #expect(MenuBarSection.Name.hidden.displayString == "Hidden")
    }

    @Test("alwaysHidden displays as \"Always-Hidden\"")
    func displayStringAlwaysHidden() {
        #expect(MenuBarSection.Name.alwaysHidden.displayString == "Always-Hidden")
    }

    @Test("Every case has a non-empty display string")
    func allDisplayStringsNonEmpty() {
        for name in MenuBarSection.Name.allCases {
            #expect(!name.displayString.isEmpty, "\(name) should have non-empty displayString")
        }
    }

    // MARK: - logString

    @Test("visible logs as \"visible section\"")
    func logStringVisible() {
        #expect(MenuBarSection.Name.visible.logString == "visible section")
    }

    @Test("hidden logs as \"hidden section\"")
    func logStringHidden() {
        #expect(MenuBarSection.Name.hidden.logString == "hidden section")
    }

    @Test("alwaysHidden logs as \"always-hidden section\"")
    func logStringAlwaysHidden() {
        #expect(MenuBarSection.Name.alwaysHidden.logString == "always-hidden section")
    }

    @Test("Every log string names a section")
    func allLogStringsContainSection() {
        for name in MenuBarSection.Name.allCases {
            #expect(name.logString.contains("section"), "\(name).logString should contain 'section'")
        }
    }

    // MARK: - localized

    // LocalizedStringKey is not Equatable and doesn't expose its key
    // directly; comparing `String(describing:)` against a key built from
    // the expected string is the closest meaningful check of which key
    // `localized` actually returns.

    @Test("visible exposes the \"Visible\" localized key")
    func localizedVisible() {
        let localized = MenuBarSection.Name.visible.localized
        #expect(String(describing: localized) == String(describing: LocalizedStringKey("Visible")))
    }

    @Test("hidden exposes the \"Hidden\" localized key")
    func localizedHidden() {
        let localized = MenuBarSection.Name.hidden.localized
        #expect(String(describing: localized) == String(describing: LocalizedStringKey("Hidden")))
    }

    @Test("alwaysHidden exposes the \"Always-Hidden\" localized key")
    func localizedAlwaysHidden() {
        let localized = MenuBarSection.Name.alwaysHidden.localized
        #expect(String(describing: localized) == String(describing: LocalizedStringKey("Always-Hidden")))
    }

    // MARK: - notchGap Static Constant

    @Test("The notch gap is 24 points")
    func notchGapValue() {
        #expect(MenuBarSection.notchGap == 24)
    }

    @Test("The notch gap is positive")
    func notchGapIsPositive() {
        #expect(MenuBarSection.notchGap > 0)
    }

    // MARK: - Presentation Mode

    @Test("Items that already fit are presented inline")
    func presentationModeUsesInlineWhenItemsAlreadyFit() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 300,
            appMenuRightEdge: 250,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: false
        )

        #expect(mode == .inline)
    }

    @Test("Items that do not fit fall back to the Thaw Bar when hiding menus is disabled")
    func presentationModeFallsBackToIceBarWhenItemsDoNotFitAndHidingMenusIsDisabled() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1000,
            appMenuRightEdge: 350,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: false
        )

        #expect(mode == .iceBar)
    }

    @Test("Application menus are hidden before falling back to the Thaw Bar")
    func presentationModeHidesApplicationMenusBeforeUsingIceBar() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1000,
            appMenuRightEdge: 350,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: true
        )

        #expect(mode == .inlineHidingApplicationMenus)
    }

    @Test("Items that cannot fit even without the application menus use the Thaw Bar")
    func presentationModeStillUsesIceBarWhenItemsCannotFitEvenAfterHidingMenus() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1400,
            appMenuRightEdge: 350,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: true
        )

        #expect(mode == .iceBar)
    }

    @Test("The usable inline width subtracts the notch gap on both sides")
    func usableInlineWidthAccountsForNotchGapOnBothSides() {
        let width = MenuBarSection.usableInlineWidth(
            from: 200,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1600,
            notchFrame: CGRect(x: 700, y: 0, width: 200, height: 30)
        )

        #expect(width == 1152)
    }
}
