//
//  GroupBlockPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct GroupBlockPlacementTests {
    private static func tag(_ title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string("test.group"), title: title, instanceIndex: 0)
    }

    private static func tags(_ titles: String...) -> [MenuBarItemTag] {
        titles.map(tag)
    }

    private let block = GroupBlockPlacement(
        members: GroupBlockPlacementTests.tags("a", "b", "c"),
        anchor: GroupBlockPlacementTests.tag("x"),
        insertsLeftOfAnchor: true
    )

    @Test("Members in order immediately left of the anchor are placed")
    func placedLeftOfAnchor() {
        #expect(block.isPlaced(in: Self.tags("a", "b", "c", "x", "y")))
        #expect(!block.isPlaced(in: Self.tags("a", "c", "b", "x", "y")))
        #expect(!block.isPlaced(in: Self.tags("a", "b", "x", "c", "y")))
    }

    @Test("Members in order immediately right of the anchor are placed")
    func placedRightOfAnchor() {
        let block = GroupBlockPlacement(members: Self.tags("a", "b"), anchor: Self.tag("x"), insertsLeftOfAnchor: false)
        #expect(block.isPlaced(in: Self.tags("y", "x", "a", "b")))
        #expect(!block.isPlaced(in: Self.tags("a", "b", "y", "x")))
    }

    @Test("A slot off the section's edge is clamped, as on 2026-10-10 with the anchor first")
    func slotClampsToTheSection() {
        let slot = block.slot(in: Self.tags("x", "y", "a", "b", "c"))
        #expect(slot?.raw == -3)
        #expect(slot?.clamped == 0)
        #expect(!block.isPlaced(in: Self.tags("x", "y", "a", "b", "c")))
    }

    @Test("A missing anchor is never placed")
    func missingAnchor() {
        #expect(block.slot(in: Self.tags("a", "b", "c")) == nil)
        #expect(!block.isPlaced(in: Self.tags("a", "b", "c")))
    }

    @Test("A pass that moved nothing ends the attempt; one that moved something earns another", arguments: [
        (pass: 1, moved: 0, again: false),
        (pass: 1, moved: 2, again: true),
        (pass: GroupBlockPlacement.maxPasses, moved: 3, again: false),
    ])
    func passes(pass: Int, moved: Int, again: Bool) {
        #expect(GroupBlockPlacement.shouldRunAnotherPass(after: pass, membersMoved: moved) == again)
    }
}
