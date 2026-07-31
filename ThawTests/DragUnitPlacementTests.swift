//
//  DragUnitPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
@testable import Thaw
import XCTest

/// `LayoutBarContainer.updateArrangedViewsForDrag` used to reorder with
/// `move(fromOffsets:toOffset:)`, which can only move one element. It now uses
/// `MenuBarItemGroupResolver.placeBlock` so a whole group travels as one block.
///
/// The single-item path is by far the most-used drag in the app, so the
/// replacement has to be *exactly* equivalent there. These tests prove that
/// rather than asserting it in a comment.
final class DragUnitPlacementTests: XCTestCase {
    /// The index translation `updateArrangedViewsForDrag` performs before the
    /// move — reproduced here so the comparison covers the real call shape.
    private func targetIndex(source: Int, destination: Int) -> Int {
        destination > source ? destination + 1 : destination
    }

    func testPlaceBlockMatchesMoveForEverySingleItemReorder() {
        let base = ["a", "b", "c", "d", "e"]

        for source in base.indices {
            for destination in base.indices where destination != source {
                let target = targetIndex(source: source, destination: destination)

                var viaMove = base
                viaMove.move(fromOffsets: [source], toOffset: target)

                let viaPlaceBlock = MenuBarItemGroupResolver.placeBlock(
                    base,
                    memberIndices: [source],
                    toIndexInOriginal: target
                )

                XCTAssertEqual(
                    viaPlaceBlock,
                    viaMove,
                    "diverged moving index \(source) to \(destination) (target \(target))"
                )
            }
        }
    }

    /// A one-element array and a no-op move are the degenerate cases the drag
    /// code hits constantly while the cursor sits still.
    func testPlaceBlockHandlesDegenerateReorders() {
        XCTAssertEqual(
            MenuBarItemGroupResolver.placeBlock(["a"], memberIndices: [0], toIndexInOriginal: 0),
            ["a"]
        )
        XCTAssertEqual(
            MenuBarItemGroupResolver.placeBlock(["a", "b"], memberIndices: [0], toIndexInOriginal: 0),
            ["a", "b"]
        )
    }

    /// The behaviour `move(fromOffsets:toOffset:)` could not express at all:
    /// several members, not adjacent, relocating together.
    func testScatteredUnitTravelsAsOneBlock() {
        let base = ["g1", "x", "g2", "y", "g3"]

        let result = MenuBarItemGroupResolver.placeBlock(
            base,
            memberIndices: [0, 2, 4],
            toIndexInOriginal: 5
        )

        XCTAssertEqual(result, ["x", "y", "g1", "g2", "g3"])
    }

    /// Whatever the drop position, the preview must never gain or lose a view —
    /// an arranged view dropped on the floor is an item missing from the bar.
    func testNoViewIsEverLostOrDuplicated() {
        let base = ["g1", "x", "g2", "y", "g3", "z"]

        for destination in 0 ... base.count {
            let result = MenuBarItemGroupResolver.placeBlock(
                base,
                memberIndices: [0, 2, 4],
                toIndexInOriginal: destination
            )
            XCTAssertEqual(result.sorted(), base.sorted(), "destination \(destination) changed the view set")
        }
    }
}
