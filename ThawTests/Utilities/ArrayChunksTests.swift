//
//  ArrayChunksTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Array chunks")
struct ArrayChunksTests {
    @Test("Runs keep their order and the last one holds what's left")
    func chunks() {
        #expect([1, 2, 3, 4, 5].chunks(ofCount: 2) == [[1, 2], [3, 4], [5]])
        #expect([1, 2, 3, 4].chunks(ofCount: 2) == [[1, 2], [3, 4]])
        #expect([1, 2].chunks(ofCount: 5) == [[1, 2]])
        #expect([Int]().chunks(ofCount: 3).isEmpty)
    }
}
