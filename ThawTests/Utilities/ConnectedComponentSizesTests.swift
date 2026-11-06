//
//  ConnectedComponentSizesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Four-connected component sizes determine the knock-out's glyph criterion.
@Suite("Connected component sizes")
struct ConnectedComponentSizesTests {
    private static func sizes(width: Int, height: Int, kept: Set<Int>) -> [Int] {
        CGImage.connectedComponentSizes(width: width, height: height) { x, y in
            kept.contains(y * width + x)
        }
    }

    @Test("a solid block is one component")
    func solidBlock() {
        var kept = Set<Int>()
        for y in 1 ... 3 {
            for x in 1 ... 3 {
                kept.insert(y * 5 + x)
            }
        }
        #expect(Self.sizes(width: 5, height: 5, kept: kept) == [9])
    }

    @Test("separated blocks are counted in scan order")
    func separatedBlocks() {
        // A 2x2 block at the top-left and a single pixel at the bottom-right.
        let kept: Set = [0, 1, 5, 6, 24]
        #expect(Self.sizes(width: 5, height: 5, kept: kept) == [4, 1])
    }

    @Test("diagonal neighbours are not connected")
    func diagonalNeighbours() {
        // (0,0) and (1,1) touch only at a corner.
        let kept: Set = [0, 5]
        #expect(Self.sizes(width: 4, height: 4, kept: kept) == [1, 1])
    }
}
