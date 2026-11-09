//
//  LayoutMicroInteractionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct LayoutMicroInteractionTests {
    @Test("A drag taps on entering another section, not on re-entering its own or on its first entry")
    func sectionCrossing() {
        var crossing = SectionCrossing(startingIn: .visible)
        let entries = [.visible, .hidden, .hidden, .visible].map { crossing.enter($0) }
        #expect(entries == [false, true, false, true])

        var fromOutside = SectionCrossing()
        let outside = [.hidden, .alwaysHidden].map { fromOutside.enter($0) }
        #expect(outside == [false, true])
    }

    @Test("A slider taps when it lands on its detent, and not again while it stays there")
    func sliderDetent() {
        #expect(SliderDetent.reached(0, from: -2, to: 0, tolerance: 0.0001))
        #expect(!SliderDetent.reached(0, from: 0, to: 0, tolerance: 0.0001))
        #expect(!SliderDetent.reached(0, from: 0, to: 2, tolerance: 0.0001))
        #expect(SliderDetent.reached(1, from: 0.9, to: 0.999_999, tolerance: 0.05))
    }

    @Test("The list scrolls only near its edges, faster the deeper the pointer is")
    func autoscrollStep() {
        let height: CGFloat = 400
        #expect(LayoutListAutoscroll.step(pointerY: 200, viewportHeight: height) == 0)
        #expect(LayoutListAutoscroll.step(pointerY: 30, viewportHeight: height) < 0)
        #expect(LayoutListAutoscroll.step(pointerY: 0, viewportHeight: height) < LayoutListAutoscroll.step(pointerY: 30, viewportHeight: height))
        #expect(LayoutListAutoscroll.step(pointerY: -50, viewportHeight: height) == -LayoutListAutoscroll.maxStep)
        #expect(LayoutListAutoscroll.step(pointerY: 390, viewportHeight: height) > 0)
        #expect(LayoutListAutoscroll.step(pointerY: 30, viewportHeight: 60) == 0)
    }

    @Test("Autoscroll stays inside the content")
    func autoscrollClamp() {
        #expect(LayoutListAutoscroll.offset(5, by: -18, contentHeight: 1000, viewportHeight: 400) == 0)
        #expect(LayoutListAutoscroll.offset(590, by: 18, contentHeight: 1000, viewportHeight: 400) == 600)
        #expect(LayoutListAutoscroll.offset(0, by: 18, contentHeight: 300, viewportHeight: 400) == 0)
    }

    @Test("Only moves flash the list's rows")
    func movesSelection() {
        #expect(LayoutItemListCommand.sectionNumber(2).movesSelection)
        #expect(LayoutItemListCommand.nudge(left: true).movesSelection)
        #expect(LayoutItemListCommand.adjacentSection(up: false).movesSelection)
        #expect(!LayoutItemListCommand.undo.movesSelection)
        #expect(!LayoutItemListCommand.step(1).movesSelection)
    }
}

@MainActor
struct SearchRearrangementTests {
    private func placement(_ title: String, _ section: String?) -> MenuBarSearchResult.Placement {
        let tag = MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0)
        return MenuBarSearchResult.Placement(id: MenuBarSearchModel.ItemID(tag: tag, windowID: nil), section: section)
    }

    @Test("The same rows under other headings are a move; a new query or a changed set is not")
    func rearrangement() {
        let before = [placement("a", "Visible"), placement("b", "Visible"), placement("c", "Hidden")]
        let moved = [placement("a", "Visible"), placement("c", "Visible"), placement("b", "Hidden")]
        #expect(MenuBarSearchModel.isRearrangement(from: before, to: moved))
        #expect(!MenuBarSearchModel.isRearrangement(from: before, to: before))
        #expect(!MenuBarSearchModel.isRearrangement(from: before, to: Array(before.prefix(2))))
        #expect(!MenuBarSearchModel.isRearrangement(from: before, to: [placement("a", nil), placement("b", nil), placement("d", nil)]))
    }
}
