//
//  UISmallTypesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@Suite("Small UI types")
@MainActor
struct UISmallTypesTests {
    @Test("Zoom steps through the fixed levels and stops at either end")
    func zoomSteps() {
        #expect(AppUIZoom.next(100, increasing: true) == 110)
        #expect(AppUIZoom.next(100, increasing: false) == 90)
        #expect(AppUIZoom.next(200, increasing: true) == 200)
        #expect(AppUIZoom.next(75, increasing: false) == 75)
        #expect(AppUIZoom.next(42, increasing: true) == 110, "an unknown level counts as 100")
        #expect(AppUIZoom.normalized(125) == 125)
        #expect(AppUIZoom.normalized(130) == 100)
    }

    @Test("Every HUD placement has a picker label")
    func placementLabels() {
        let labels = ThawHUDPlacement.allCases.map(\.localized)
        #expect(labels.count == 3)
        #expect(labels == [LocalizedStringKey("Top left"), "Top center", "Top right"])
    }

    @Test("A unit with more than one member is a group")
    func unitIsGroup() {
        #expect(!LayoutEditorOrder.Unit(id: "a", memberIDs: ["a"]).isGroup)
        #expect(LayoutEditorOrder.Unit(id: "g", memberIDs: ["a", "b"]).isGroup)
    }
}
