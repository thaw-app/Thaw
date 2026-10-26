//
//  SectionNameLocalizationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Section names in strings, menus and VoiceOver come from the same catalog entries as the section headings.
@MainActor
@Suite("Translated section names")
struct SectionNameLocalizationTests {
    private static func languageBundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test("Each section name reads the translation its heading uses")
    func namesAreTranslated() throws {
        let chinese = try Self.languageBundle("zh-Hans")
        #expect(MenuBarSectionName.visible.localizedName(in: chinese) == "显示")
        #expect(MenuBarSectionName.hidden.localizedName(in: chinese) == "隐藏")
        #expect(MenuBarSectionName.alwaysHidden.localizedName(in: chinese) == "永久隐藏")
    }

    @Test("Menus use the same name as the headings", arguments: MenuBarSectionName.allCases)
    func menuTitleMatches(section: MenuBarSectionName) {
        #expect(MenuBarSearchItemActions.title(for: section) == section.localizedName)
    }

    @Test("A Layout tile's VoiceOver value names its section as the heading does", arguments: MenuBarSectionName.allCases)
    func accessibilityValueUsesTheTranslation(section: MenuBarSectionName) {
        #expect(LayoutSelectionHighlight.accessibilityValue(section: section, isSelected: false) == section.localizedName)
    }
}
