//
//  ChoiceLabelsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The names and symbols the settings pickers show for their choices.
@MainActor
@Suite("Choice labels")
struct ChoiceLabelsTests {
    @Test("Each Thaw Bar arrangement has a symbol of its own that the system draws")
    func thawBarLayoutSymbols() {
        let symbols = ThawBarLayout.allCases.map(\.systemImage)
        #expect(Set(symbols).count == ThawBarLayout.allCases.count)
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) is a system symbol")
        }
    }

    @Test("Each glass finish has a plain name of its own")
    func glassStyleNames() {
        #expect(MenuBarGlassStyle.regular.localized == "Glass")
        #expect(MenuBarGlassStyle.dynamic.localized == "Dynamic Glass")
        #expect(MenuBarGlassStyle.solid.localized == "Invert")
        #expect(MenuBarGlassStyle.edge.localized == "Edge")
        #expect(MenuBarGlassStyle.sheer.localized == "Sheer")
        #expect(MenuBarGlassStyle.dim.localized == "Dim")
        let names = MenuBarGlassStyle.allCases.map(\.localized)
        #expect(names.count == MenuBarGlassStyle.allCases.count)
        for (index, name) in names.enumerated() {
            #expect(!names[(index + 1)...].contains(name), "each finish has its own name")
        }
    }

    @Test("The Effect menu lists plain glass under Glass, then every other finish under Liquid Glass")
    func glassStyleGroups() {
        #expect(MenuBarGlassStyle.glassFinishes == [.regular])
        #expect(MenuBarGlassStyle.liquidGlassFinishes == [.edge, .sheer, .dim, .solid, .dynamic])
        let listed = MenuBarGlassStyle.glassFinishes + MenuBarGlassStyle.liquidGlassFinishes
        #expect(Set(listed) == Set(MenuBarGlassStyle.allCases) && listed.count == MenuBarGlassStyle.allCases.count)
        #expect(MenuBarGlassStyle.liquidGlassFinishes.filter(\.isExperimental) == [.edge, .sheer, .dim, .solid], "only Dynamic Glass is not Alpha")
    }

    @Test("Saved glass finishes keep their stored numbers", arguments: [
        (MenuBarGlassStyle.regular, 0), (.dynamic, 3),
        (.solid, 4), (.edge, 5), (.sheer, 6), (.dim, 7),
    ])
    func glassStyleRawValues(style: MenuBarGlassStyle, rawValue: Int) throws {
        #expect(style.rawValue == rawValue)
        let decoded = try JSONDecoder().decode(MenuBarGlassStyle.self, from: Data("\(rawValue)".utf8))
        #expect(decoded == style)
        #expect(try JSONEncoder().encode(style) == Data("\(rawValue)".utf8))
    }

    @Test("Retired and unknown finish numbers read as plain glass", arguments: [1, 2, 99])
    func retiredGlassStyleRawValues(rawValue: Int) throws {
        let decoded = try JSONDecoder().decode(MenuBarGlassStyle.self, from: Data("\(rawValue)".utf8))
        #expect(decoded == .regular)
    }

    @Test("Each divider style has its own name")
    func dividerStyleNames() {
        #expect(SectionDividerStyle.line.localized == "Line")
        #expect(SectionDividerStyle.dot.localized == "Dot")
        #expect(SectionDividerStyle.slash.localized == "Slash")
        #expect(SectionDividerStyle.custom.localized == "Custom")
        #expect(SectionDividerStyle.noDivider.localized == "None")
    }

    @Test("A Custom divider's mark carries the chosen image and its template switch", .scratchDefaults)
    func customDividerMark() {
        let settings = AppSettings()
        settings.layout.customSectionDividerImage = nil
        #expect(settings.customSectionDividerMark == nil)
        settings.layout.customSectionDividerImage = Data([4, 5, 6])
        settings.layout.customSectionDividerIsTemplate = false
        #expect(settings.customSectionDividerMark == SectionDividerCustomMark(data: Data([4, 5, 6]), isTemplate: false))
        settings.layout.customSectionDividerIsTemplate = true
        #expect(settings.customSectionDividerMark?.isTemplate == true)
    }

    @Test("A file that isn't an image says why in words")
    func unreadableImageMessage() {
        let message = StoredImageData.Failure.unreadable.errorDescription
        #expect(message?.isEmpty == false)
        #expect(StoredImageData.Failure.unreadable.localizedDescription == message)
    }
}
