//
//  LayoutSuggestionNamesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Suggestion texts name a few items and count the rest", .scratchDefaults)
struct LayoutSuggestionNamesTests {
    private func named(_ name: String) -> MenuBarItem {
        var item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.suggest.\(name)"), title: name, instanceIndex: 0),
            windowID: 5,
            ownerPID: 999_972,
            sourcePID: 999_972,
            bounds: CGRect(x: 0, y: 0, width: 22, height: 24),
            title: name,
            isOnScreen: true
        )
        item.customName = name
        return item
    }

    @Test("Up to three names are joined as a list")
    func shortList() {
        let names = LayoutSuggestions.names(of: ["Alpha", "Beta", "Gamma"].map(named))
        #expect(names == ["Alpha", "Beta", "Gamma"].formatted(.list(type: .and)))
    }

    @Test("Past three names, the rest are counted")
    func longListIsShortened() {
        let names = LayoutSuggestions.names(of: ["A", "B", "C", "D", "E"].map(named))
        let more = String(localized: "\(2) more", comment: "Last entry of a shortened list of menu bar item names")
        #expect(names == ["A", "B", "C", more].formatted(.list(type: .and)))
        #expect(!names.contains("D"))
    }
}
