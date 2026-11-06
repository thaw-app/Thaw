//
//  RestrictionReflowLayoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A restriction reflow moves every item for a moment, so the saved layout is not laid back over it.
@MainActor
@Suite("Saved layout during a restriction reflow", .scratchDefaults)
struct RestrictionReflowLayoutTests {
    private static let hidden = MenuBarItem(
        tag: .hiddenControlItem,
        windowID: 9,
        ownerPID: 501,
        sourcePID: 501,
        bounds: CGRect(x: 1500, y: 4.5, width: 2, height: 24),
        title: ControlItemIdentifier.hidden.rawValue,
        isOnScreen: true
    )

    @Test("The saved layout stands down inside the reflow window and asks to be tried again")
    func savedLayoutWaitsOutTheReflow() async {
        let manager = MenuBarItemManager()
        defer { manager.postRestrictionRepairTask?.cancel() }
        manager.savedSectionOrder = [MenuBarSectionName.visible.rawValue: ["com.example.one"]]

        manager.noteRestrictionChange()
        let applied = await manager.applySavedLayout(
            items: [],
            previousWindowIDs: [],
            controlItems: ControlItemPair(hidden: Self.hidden, alwaysHidden: nil)
        )

        #expect(!applied)
        #expect(manager.repairs.ledger.causesWaiting(for: .deferredLayoutReconcile) == [.layoutApplyBlocked])
    }
}
