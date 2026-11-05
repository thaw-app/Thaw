//
//  CGRectNaturalFitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Centering content at its natural size")
struct CGRectNaturalFitTests {
    private let bounds = CGRect(x: 0, y: 0, width: 28, height: 28)

    @Test("Content that fits keeps its size and is centered")
    func smallContentKeepsItsSize() {
        #expect(bounds.centeredRect(forNaturalSize: CGSize(width: 10, height: 20)) == CGRect(x: 9, y: 4, width: 10, height: 20))
    }

    @Test("Content that is too big shrinks to fit and keeps its shape")
    func largeContentShrinks() {
        #expect(bounds.centeredRect(forNaturalSize: CGSize(width: 56, height: 28)) == CGRect(x: 0, y: 7, width: 28, height: 14))
        #expect(bounds.centeredRect(forNaturalSize: CGSize(width: 14, height: 56)) == CGRect(x: 10.5, y: 0, width: 7, height: 28))
    }

    @Test("Content with no area fills the rect")
    func emptyContentFills() {
        #expect(bounds.centeredRect(forNaturalSize: .zero) == bounds)
        #expect(bounds.centeredRect(forNaturalSize: CGSize(width: 10, height: 0)) == bounds)
    }
}
