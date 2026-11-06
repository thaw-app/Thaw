//
//  PublisherTransformsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Testing
@testable import Thaw

@MainActor
@Suite("Publisher transforms")
struct PublisherTransformsTests {
    @Test("Each element is replaced by the given one")
    func replace() {
        var received: [String] = []
        _ = [1, 2, 3].publisher.replace(with: "x").sink { received.append($0) }
        #expect(received == ["x", "x", "x"])
    }

    @Test("Nil elements are dropped and the rest arrive unwrapped")
    func removeNil() {
        var received: [Int] = []
        _ = [1, nil, 2, nil, nil, 3].publisher.removeNil().sink { received.append($0) }
        #expect(received == [1, 2, 3])
    }

    @Test("A tuple equal to the one before it is dropped, one differing in any element is kept")
    func removeDuplicateTuples() {
        let input: [(Int, String)] = [(1, "a"), (1, "a"), (1, "b"), (2, "b"), (2, "b"), (1, "a")]
        var received: [String] = []
        _ = input.publisher.removeDuplicates().sink { received.append("\($0.0)\($0.1)") }
        #expect(received == ["1a", "1b", "2b", "1a"])
    }

    @Test("Three-element tuples compare every element")
    func removeDuplicateTriples() {
        let input: [(Int, Int, Bool)] = [(0, 0, true), (0, 0, true), (0, 0, false)]
        var count = 0
        _ = input.publisher.removeDuplicates().sink { _ in count += 1 }
        #expect(count == 2)
    }
}
