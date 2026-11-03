//
//  IgnoredPreferredWritesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("A reveal skips an item whose preferred-position write was ignored, until something changes")
struct IgnoredPreferredWritesTests {
    private let item = "at.obdev.littlesnitch.agent:Item-0"
    private let circumstances = IgnoredPreferredWrites.Circumstances(
        layout: [.hidden: ["at.obdev.littlesnitch.agent:Item-0", "cc.ffitch.shottr:Item-0"]],
        frame: CGRect(x: 1927, y: 0, width: 30, height: 24),
        displayID: 1
    )

    @Test("After an ignored write, the next reveal skips the item")
    func ignoredWriteIsSkipped() {
        var memory = IgnoredPreferredWrites()
        memory.noteIgnored(item, under: circumstances)
        let skipped = memory.skips(item, under: circumstances)

        #expect(skipped)
    }

    @Test("A layout change clears it, so the item is tried again")
    func layoutChangeClears() {
        var memory = IgnoredPreferredWrites()
        memory.noteIgnored(item, under: circumstances)
        let reordered = IgnoredPreferredWrites.Circumstances(
            layout: [.hidden: ["cc.ffitch.shottr:Item-0", "at.obdev.littlesnitch.agent:Item-0"]],
            frame: CGRect(x: 1927, y: 0, width: 30, height: 24),
            displayID: 1
        )
        let skippedAfterChange = memory.skips(item, under: reordered)
        let skippedOnReturn = memory.skips(item, under: circumstances)

        #expect(!skippedAfterChange)
        #expect(!skippedOnReturn)
    }

    @Test("A frame change clears it, so the item is tried again")
    func frameChangeClears() {
        var memory = IgnoredPreferredWrites()
        memory.noteIgnored(item, under: circumstances)
        let moved = IgnoredPreferredWrites.Circumstances(
            layout: [.hidden: ["at.obdev.littlesnitch.agent:Item-0", "cc.ffitch.shottr:Item-0"]],
            frame: CGRect(x: 2034, y: 0, width: 30, height: 24),
            displayID: 1
        )
        let skippedAfterChange = memory.skips(item, under: moved)
        let skippedOnReturn = memory.skips(item, under: circumstances)

        #expect(!skippedAfterChange)
        #expect(!skippedOnReturn)
    }

    @Test("A display change clears it, so the item is tried again")
    func displayChangeClears() {
        var memory = IgnoredPreferredWrites()
        memory.noteIgnored(item, under: circumstances)
        let otherDisplay = IgnoredPreferredWrites.Circumstances(
            layout: [.hidden: ["at.obdev.littlesnitch.agent:Item-0", "cc.ffitch.shottr:Item-0"]],
            frame: CGRect(x: 1927, y: 0, width: 30, height: 24),
            displayID: 2
        )
        let skippedAfterChange = memory.skips(item, under: otherDisplay)
        let skippedOnReturn = memory.skips(item, under: circumstances)

        #expect(!skippedAfterChange)
        #expect(!skippedOnReturn)
    }
}
