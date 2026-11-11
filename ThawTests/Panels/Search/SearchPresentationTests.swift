//
//  SearchPresentationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw
import ThawUI

/// The search panel's two layouts and the window they share.
@Suite("Search panel layouts")
struct SearchPresentationTests {
    @Test("Raw values are the stored names")
    func rawValuesAreStorage() {
        #expect(SearchPresentation.allCases.map(\.rawValue) == ["extended", "compact"])
        #expect(SearchPresentation(rawValue: "spotlight") == nil)
    }

    @Test("The three panel styles before the launcher migrate to a layout", arguments: [
        ("inspector", SearchPresentation.extended),
        ("assisted", .extended),
        ("launcher", .compact),
        ("extended", .extended),
        ("compact", .compact),
    ])
    func storedValuesMigrate(stored: String, layout: SearchPresentation) {
        #expect(SearchPresentation(storedValue: stored) == layout)
    }

    @Test("An unknown stored value reads as nothing, so the default stands")
    func unknownStoredValue() {
        #expect(SearchPresentation(storedValue: "spotlight") == nil)
    }

    @Test("Only Compact with nothing typed collapses to the field")
    func collapsing() {
        #expect(SearchPresentation.compact.isCollapsed(query: ""))
        #expect(SearchPresentation.compact.isCollapsed(query: "  "))
        #expect(!SearchPresentation.compact.isCollapsed(query: "wi"))
        #expect(!SearchPresentation.extended.isCollapsed(query: ""))
    }

    @Test("The panel is Floe's launcher: 750 by 474 open, the field's piece alone collapsed")
    func geometry() {
        #expect(SearchPanelGeometry.contentSize(isCollapsed: false) == CGSize(width: 750, height: 474))
        #expect(SearchPanelGeometry.contentSize(isCollapsed: true).height == PanelPieceHeights.launcherField)
        let open = SearchPanelGeometry.windowSize(isCollapsed: false)
        #expect(open.width == 750 + SearchPanelGeometry.margin * 2)
        #expect(open.height == 474 + SearchPanelGeometry.margin * 2)
    }

    @Test("Collapsing keeps the field where it is: the window's top stays put")
    func collapsingKeepsTheTop() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let open = SearchPanelGeometry.frame(isCollapsed: false, in: visible)
        let collapsed = SearchPanelGeometry.frame(isCollapsed: true, in: visible)
        #expect(open.maxY == collapsed.maxY)
        #expect(open.midX == visible.midX)
        #expect(collapsed.height < open.height)
    }
}
