//
//  UISmallTypesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawUI

@Suite("Small UI types")
@MainActor
struct UISmallTypesTests {
    @Test("Every HUD placement has a picker label")
    func placementLabels() {
        let labels = ThawHUDPlacement.allCases.map(\.localized)
        #expect(labels.count == 3)
        #expect(labels == ["Top left", "Top center", "Top right"])
    }

    @Test("A unit with more than one member is a group")
    func unitIsGroup() {
        #expect(!LayoutEditorOrder.Unit(id: "a", memberIDs: ["a"]).isGroup)
        #expect(LayoutEditorOrder.Unit(id: "g", memberIDs: ["a", "b"]).isGroup)
    }
}
