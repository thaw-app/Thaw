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

    @Test("The experimental glass finishes say so in their names")
    func glassStyleNames() {
        #expect(MenuBarGlassStyle.solid.localized == "Invert (Experimental)")
        #expect(MenuBarGlassStyle.edge.localized == "Edge (Experimental)")
        #expect(MenuBarGlassStyle.sheer.localized == "Sheer (Experimental)")
        #expect(MenuBarGlassStyle.dim.localized == "Dim (Experimental)")
        #expect(MenuBarGlassStyle.liquid.localized == "Liquid Glass")
        let names = MenuBarGlassStyle.allCases.map(\.localized)
        #expect(names.count == MenuBarGlassStyle.allCases.count)
        for (index, name) in names.enumerated() {
            #expect(!names[(index + 1)...].contains(name), "each finish has its own name")
        }
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
        settings.advanced.customSectionDividerImage = nil
        #expect(settings.customSectionDividerMark == nil)
        settings.advanced.customSectionDividerImage = Data([4, 5, 6])
        settings.advanced.customSectionDividerIsTemplate = false
        #expect(settings.customSectionDividerMark == SectionDividerCustomMark(data: Data([4, 5, 6]), isTemplate: false))
        settings.advanced.customSectionDividerIsTemplate = true
        #expect(settings.customSectionDividerMark?.isTemplate == true)
    }

    @Test("A file that isn't an image says why in words")
    func unreadableImageMessage() {
        let message = StoredImageData.Failure.unreadable.errorDescription
        #expect(message?.isEmpty == false)
        #expect(StoredImageData.Failure.unreadable.localizedDescription == message)
    }
}
