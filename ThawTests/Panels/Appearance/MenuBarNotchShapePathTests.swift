//
//  MenuBarNotchShapePathTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// A screen that reports a notch whatever display the tests run on: 1512 points wide, with the
/// notch between x 656 and 856 measured from the screen's own left edge.
private final class NotchedScreen: NSScreen {
    private let originX: CGFloat

    init(originX: CGFloat = 0) {
        self.originX = originX
        super.init()
    }

    override var frame: NSRect {
        NSRect(x: originX, y: 0, width: 1512, height: 982)
    }

    override var __auxiliaryTopLeftArea: NSRect {
        NSRect(x: originX, y: 950, width: 656, height: 32)
    }

    override var __auxiliaryTopRightArea: NSRect {
        NSRect(x: originX + 856, y: 950, width: 656, height: 32)
    }
}

/// The overlay's shape paths on a notched display.
@Suite("Menu bar shape paths on a notched display")
@MainActor
struct MenuBarNotchShapePathTests {
    private let round = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
    private let square = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
    private let bar = CGRect(x: 0, y: 0, width: 1512, height: 24)

    private func notchPath(
        on screen: NSScreen = NotchedScreen(),
        isInset: Bool = false,
        margins: MenuBarShapePathBuilder.Margins
    ) -> NSBezierPath {
        MenuBarShapePathBuilder.notchShapePath(
            in: bar,
            info: MenuBarNotchShapeInfo(leading: square, trailing: square),
            isInset: isInset,
            screen: screen,
            margins: margins,
            insetAmount: 2
        )
    }

    /// Whether path is exactly the one full-width shape for the margins, not two pills that happen to touch.
    private func isFullShape(_ path: NSBezierPath, margins: MenuBarShapePathBuilder.Margins) -> Bool {
        let full = MenuBarShapePathBuilder.fullShapePath(
            in: bar,
            info: square,
            isInset: false,
            screen: NotchedScreen(),
            leftMargin: margins.left,
            rightMargin: margins.right,
            insetAmount: 2
        )
        return path.elementCount == full.elementCount && path.bounds == full.bounds
    }

    @Test("An inset shape comes in top and bottom, and at each rounded end only")
    func insetMovesRoundedEnds() {
        let screen = NotchedScreen()
        let rect = CGRect(x: 0, y: 0, width: 800, height: 24)
        let rounded = MenuBarShapePathBuilder.insetForNotch(rect, outerCaps: round, isInset: true, screen: screen, amount: 4)
        #expect(rounded == CGRect(x: 4, y: 4, width: 792, height: 16))

        let leadingOnly = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square)
        let mixed = MenuBarShapePathBuilder.insetForNotch(rect, outerCaps: leadingOnly, isInset: true, screen: screen, amount: 4)
        #expect(mixed == CGRect(x: 4, y: 4, width: 796, height: 16))

        let squared = MenuBarShapePathBuilder.insetForNotch(rect, outerCaps: square, isInset: true, screen: screen, amount: 4)
        #expect(squared == CGRect(x: 0, y: 4, width: 800, height: 16))
    }

    @Test("On a notched display a shape fills its rect exactly")
    func shapeFillsRect() {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 24)
        let bounds = MenuBarShapePathBuilder.shapePath(in: rect, caps: round, screen: NotchedScreen()).bounds
        #expect(bounds == rect)
    }

    @Test("A notch shape splits into two pills that stop the notch margin short of the notch")
    func splitsAtNotch() {
        let path = notchPath(margins: .init(left: 10, right: 20, notch: 4))
        #expect(path.bounds == CGRect(x: 10, y: 0, width: 1482, height: 24))
        #expect(path.contains(CGPoint(x: 651, y: 12)), "the leading pill reaches the notch margin")
        #expect(!path.contains(CGPoint(x: 653, y: 12)))
        #expect(!path.contains(CGPoint(x: 756, y: 12)), "the notch itself stays uncovered")
        #expect(!path.contains(CGPoint(x: 859, y: 12)))
        #expect(path.contains(CGPoint(x: 861, y: 12)), "the trailing pill starts past the notch margin")
    }

    @Test("The notch is found relative to the screen's own left edge")
    func notchOnSecondDisplay() {
        let path = notchPath(on: NotchedScreen(originX: 1512), margins: .init(left: 0, right: 0, notch: 0))
        #expect(path.contains(CGPoint(x: 600, y: 12)))
        #expect(!path.contains(CGPoint(x: 756, y: 12)))
        #expect(path.contains(CGPoint(x: 900, y: 12)))
    }

    @Test("An inset notch shape keeps both pills inside the inset bar")
    func insetPills() {
        let path = notchPath(isInset: true, margins: .init(left: 0, right: 0, notch: 0))
        #expect(path.bounds.minY == 2)
        #expect(path.bounds.height == 20)
        #expect(!path.contains(CGPoint(x: 756, y: 12)))
    }

    @Test("A margin that leaves no room for the leading pill draws one full shape instead")
    func noRoomFallsBackToFull() {
        let margins = MenuBarShapePathBuilder.Margins(left: 700, right: 20, notch: 4)
        let path = notchPath(margins: margins)
        #expect(isFullShape(path, margins: margins))
        #expect(path.contains(CGPoint(x: 756, y: 12)), "one shape runs across the notch")
        #expect(path.bounds.minX == 700)
        #expect(path.bounds.maxX == 1492)
    }

    @Test("A margin that leaves no room for the trailing pill draws one full shape instead")
    func noTrailingRoomFallsBackToFull() {
        let margins = MenuBarShapePathBuilder.Margins(left: 0, right: 700, notch: 0)
        let path = notchPath(margins: margins)
        #expect(isFullShape(path, margins: margins))
        #expect(path.contains(CGPoint(x: 756, y: 12)))
        #expect(path.bounds.maxX == 812)
    }

    @Test("Pills that would overlap across the notch draw one full shape instead")
    func overlappingPillsFallBackToFull() {
        let margins = MenuBarShapePathBuilder.Margins(left: 0, right: 0, notch: -150)
        let path = notchPath(margins: margins)
        #expect(isFullShape(path, margins: margins))
        #expect(path.contains(CGPoint(x: 756, y: 12)))
        #expect(path.bounds == bar)
    }
}
