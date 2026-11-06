//
//  NotchOverflowDividerOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
import ThawLayout

@Suite("Notch overflow with dividers out of order")
struct NotchOverflowDividerOrderTests {
    @Test("Always Hidden ahead of Hidden leaves the layout as it is instead of crashing")
    func reversedDividersChangeNothing() {
        let order = ["a", "b", "AH", "x", "H", "y"]
        let sections = ["a": "visible", "b": "visible", "x": "alwaysHidden", "y": "hidden"]
        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: order,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: nil, hidden: "H", alwaysHidden: "AH"),
            sectionMap: sections,
            uidWidths: ["a": 40, "b": 40, "x": 40, "y": 40],
            availableWidth: 50
        )
        #expect(result.overflowUIDs.isEmpty)
        #expect(result.updatedDesiredFiltered == order)
        #expect(result.updatedSectionMap == sections)
    }
}
