//
//  MenuBarShapeKindTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
struct MenuBarShapeKindTests {
    @Test
    func `only the split shape is drawn around the items`() {
        #expect(MenuBarShapeKind.split.followsItems)
        for shape in MenuBarShapeKind.allCases where shape != .split {
            #expect(!shape.followsItems, "\(shape) spans the bar and must not ask where the items are")
        }
    }
}
