//
//  SearchPresentationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// The contract between the three search panel faces.
@MainActor
@Suite("Search presentation traits")
struct SearchPresentationTests {
    @Test("Raw values are the stored names and never change")
    func rawValuesAreStorage() {
        #expect(SearchPresentation.allCases.map(\.rawValue) == ["inspector", "launcher", "assisted"])
        #expect(SearchPresentation.allCases.map(\.id) == ["inspector", "launcher", "assisted"])
        #expect(SearchPresentation(rawValue: "launcher") == .launcher)
        #expect(SearchPresentation(rawValue: "spotlight") == nil)
    }

    @Test("Each face names where it opens, and the names differ")
    func localizedNamesDiffer() {
        let names = SearchPresentation.allCases.map { "\($0.localized)" }
        #expect(Set(names).count == 3)
    }

    @Test("Only the inspector remembers, previews, renames and manages items")
    func inspectorOnlyTraits() {
        for presentation in SearchPresentation.allCases {
            let isInspector = presentation == .inspector
            #expect(presentation.persistsFrame == isInspector)
            #expect(presentation.warmsCachesOnShow == isInspector)
            #expect(presentation.samplesMenuBarColor == isInspector)
            #expect(presentation.spotlightsSelection == isInspector)
            #expect(presentation.allowsRename == isInspector)
            #expect(presentation.allowsItemManagement == isInspector)
            #expect(presentation.honorsKeepSearchToggle == isInspector)
        }
    }

    @Test("Each face has its own size, placement and log label")
    func sizesAndPlacements() {
        #expect(SearchPresentation.inspector.contentSize == CGSize(width: 600, height: 400))
        #expect(SearchPresentation.launcher.contentSize == CGSize(width: 620, height: 420))
        #expect(SearchPresentation.assisted.contentSize == CGSize(width: 680, height: 560))
        #expect(SearchPresentation.inspector.placement == .remembered)
        #expect(SearchPresentation.launcher.placement == .centered)
        #expect(SearchPresentation.assisted.placement == .nearPointer)
        #expect(SearchPresentation.inspector.logLabel == "search panel")
        #expect(SearchPresentation.launcher.logLabel == "item palette")
        #expect(SearchPresentation.assisted.logLabel == "assisted palette")
    }

    @Test("Only the inspector's query field is a capsule with a trailing gap")
    func queryFieldMetrics() {
        let inspector = SearchPresentation.inspector.queryFieldMetrics
        #expect(inspector.isCapsule)
        #expect(inspector.hasTrailingSpacer)
        #expect(inspector.padding.leading == 14)
        for presentation in [SearchPresentation.launcher, .assisted] {
            let metrics = presentation.queryFieldMetrics
            #expect(!metrics.isCapsule)
            #expect(!metrics.hasTrailingSpacer)
            #expect(metrics.padding.leading == 18)
        }
        #expect(SearchPresentation.assisted.queryFieldMetrics.padding.top > SearchPresentation.launcher.queryFieldMetrics.padding.top)
    }

    @Test("The inspector draws no launcher row, and the assisted row is the larger one")
    func rowMetrics() throws {
        #expect(SearchPresentation.inspector.rowMetrics == nil)
        let launcher = try #require(SearchPresentation.launcher.rowMetrics)
        let assisted = try #require(SearchPresentation.assisted.rowMetrics)
        #expect(assisted.iconLength > launcher.iconLength)
        #expect(assisted.iconSpacing > launcher.iconSpacing)
        #expect(assisted.nameLineLimit == 2)
        #expect(launcher.nameLineLimit == 1)
        #expect(assisted.minHeight == 44, "the assisted row keeps the smallest comfortable target")
        #expect(launcher.minHeight == 0)
        #expect(assisted.combinesAccessibilityChildren)
        #expect(!launcher.combinesAccessibilityChildren)
    }
}
