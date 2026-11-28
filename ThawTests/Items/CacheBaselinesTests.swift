//
//  CacheBaselinesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Cache baselines advance with a pass and go back when it publishes nothing")
struct CacheBaselinesTests {
    /// Baselines a first pass published, then advanced by a second pass that saw one more item.
    private func advancedByASecondPass() -> (published: CacheBaselines.Reading, baselines: CacheBaselines) {
        var baselines = CacheBaselines()
        baselines.beginPass()
        baselines.advance(itemWindowIDs: [1, 2], cloneWindowIDs: [9])
        baselines.advance(itemSignature: ["a", "b"])
        let published = baselines.current
        baselines.beginPass()
        baselines.advance(itemWindowIDs: [1, 2, 3], cloneWindowIDs: [])
        baselines.advance(itemSignature: ["a", "b", "c"])
        return (published, baselines)
    }

    @Test("A pass that publishes nothing leaves the baselines of the last published pass")
    func discardedPassPutsBaselinesBack() {
        let pass = advancedByASecondPass()
        var baselines = pass.baselines
        baselines.putBack()
        #expect(baselines.current == pass.published)
    }

    @Test("Putting back undoes only the running pass")
    func putBackUndoesOnlyTheRunningPass() {
        var baselines = advancedByASecondPass().baselines
        let published = baselines.current
        baselines.beginPass()
        baselines.advance(itemWindowIDs: [1], cloneWindowIDs: [7])
        baselines.advance(itemSignature: ["a"])
        baselines.putBack()
        #expect(baselines.current == published)
    }
}
