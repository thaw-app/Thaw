//
//  MenuBarOverlayGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Overlay geometry")
struct MenuBarOverlayGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let bar = CGRect(x: 0, y: 0, width: 1512, height: 37)

    @Test("Each subpath of a path is measured on its own")
    func componentBounds() {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        path.addEllipse(in: CGRect(x: 20, y: 0, width: 10, height: 10))
        path.move(to: CGPoint(x: 40, y: 0))
        path.addQuadCurve(to: CGPoint(x: 50, y: 0), control: CGPoint(x: 45, y: 10))
        path.addLine(to: CGPoint(x: 40, y: 0))
        let bounds = MenuBarLiquidGlassGeometry.componentBounds(of: path)
        #expect(bounds.count == 3)
        #expect(bounds[0] == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(abs(bounds[1].minX - 20) < 0.01)
        #expect(abs(bounds[2].maxX - 50) < 0.01)
        #expect(MenuBarLiquidGlassGeometry.componentBounds(of: CGMutablePath()).isEmpty)
    }

    @Test("The leading pill runs from the margin to the application menu, stopping short of the notch and the items")
    func leadingBounds() {
        let menu = CGRect(x: 0, y: 0, width: 300, height: 37)
        let plain = MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: menu, trailingContentMinX: nil, in: bar, screenFrame: screen,
            trailingPadding: 8, leadingMargin: 4, notch: .init(frame: nil, margin: 6)
        )
        #expect(plain == CGRect(x: 4, y: 0, width: 304, height: 37))

        let notched = MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: CGRect(x: 0, y: 0, width: 900, height: 37), trailingContentMinX: nil, in: bar,
            screenFrame: screen, trailingPadding: 8, leadingMargin: 4,
            notch: .init(frame: CGRect(x: 656, y: 945, width: 200, height: 37), margin: 6)
        )
        #expect(notched.maxX == 650)

        let crowded = MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: menu, trailingContentMinX: 200, in: bar, screenFrame: screen,
            trailingPadding: 8, leadingMargin: 4, notch: .init(frame: nil, margin: 6)
        )
        #expect(crowded.maxX == 196)

        let noMenu = MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: .zero, trailingContentMinX: nil, in: bar, screenFrame: screen,
            trailingPadding: 8, leadingMargin: 4, notch: .init(frame: nil, margin: 6)
        )
        #expect(noMenu.maxX == bar.maxX, "without a menu frame the pill reaches the bar's end")

        let collapsed = MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: menu, trailingContentMinX: -100, in: bar, screenFrame: screen,
            trailingPadding: 8, leadingMargin: 4, notch: .init(frame: nil, margin: 6)
        )
        #expect(collapsed.width == 0)
    }

    @Test("The trailing pill starts at the first item on this display, clear of the notch")
    func trailingBounds() {
        let items = [
            CGRect(x: 1200, y: 0, width: 30, height: 37),
            CGRect(x: 1400, y: 0, width: 30, height: 37),
            CGRect(x: 2000, y: 0, width: 30, height: 37),
        ]
        let pill = MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: items, in: bar, screenFrame: screen,
            leadingOutset: 6, trailingMargin: 4, notch: .init(frame: nil, margin: 6)
        )
        #expect(pill == CGRect(x: 1194, y: 0, width: 314, height: 37))

        let clearOfNotch = MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: [CGRect(x: 800, y: 0, width: 30, height: 37), CGRect(x: 1400, y: 0, width: 30, height: 37)],
            in: bar, screenFrame: screen, leadingOutset: 6, trailingMargin: 4,
            notch: .init(frame: CGRect(x: 656, y: 945, width: 200, height: 37), margin: 6)
        )
        #expect(clearOfNotch.minX == 862)

        #expect(MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: [CGRect(x: 3000, y: 0, width: 30, height: 37)], in: bar, screenFrame: screen,
            leadingOutset: 6, trailingMargin: 4, notch: .init(frame: nil, margin: 6)
        ) == .zero)
    }

    @Test("The right margin places the trailing pill's end from the screen edge, like the left margin")
    func trailingMarginFromScreenEdge() {
        // The Clock ends 22 pt short of the edge, as on macOS 27.2.
        let items = [CGRect(x: 1200, y: 0, width: 30, height: 37), CGRect(x: 1434, y: 0, width: 56, height: 37)]
        func pill(margin: CGFloat) -> CGRect {
            MenuBarSplitPillGeometry.trailingBounds(
                itemBounds: items, in: bar, screenFrame: screen,
                leadingOutset: 6, trailingMargin: margin, notch: .init(frame: nil, margin: 6)
            )
        }
        #expect(pill(margin: 0).maxX == bar.maxX)
        #expect(pill(margin: 15).maxX == bar.maxX - 15)
        #expect(pill(margin: 15).minX == 1194, "the margin moves only the outer end")
        #expect(pill(margin: 40).maxX == 1490, "never ends inside the last item")
    }

    @Test("Frozen geometry keeps the last stable pair")
    func frozenKeepsStable() {
        let lastLeading = CGRect(x: 0, y: 0, width: 100, height: 24)
        let lastTrailing = CGRect(x: 500, y: 0, width: 100, height: 24)
        let result = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: CGRect(x: 0, y: 0, width: 50, height: 24), trailing: .zero, geometryFrozen: true,
            lastStableLeading: lastLeading, lastStableTrailing: lastTrailing
        )
        #expect(result.leading == lastLeading)
        #expect(result.trailing == lastTrailing)
    }

    @Test("A fresh pair is used and remembered; a lone leading half replaces the stable pair")
    func freshPairs() {
        let leading = CGRect(x: 0, y: 0, width: 100, height: 24)
        let trailing = CGRect(x: 500, y: 0, width: 100, height: 24)
        let fresh = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: leading, trailing: trailing, geometryFrozen: false, lastStableLeading: .zero, lastStableTrailing: .zero
        )
        #expect(fresh.nextStableLeading == leading)
        #expect(fresh.nextStableTrailing == trailing)

        let lone = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: leading, trailing: .zero, geometryFrozen: false, lastStableLeading: leading, lastStableTrailing: trailing
        )
        #expect(lone.trailing == .zero)
        #expect(lone.nextStableTrailing == .zero)
    }

    @Test("An empty read falls back to the last stable pair, or to its lone leading half")
    func emptyReadFallsBack() {
        let leading = CGRect(x: 0, y: 0, width: 100, height: 24)
        let trailing = CGRect(x: 500, y: 0, width: 100, height: 24)
        let pair = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: .zero, trailing: .zero, geometryFrozen: false, lastStableLeading: leading, lastStableTrailing: trailing
        )
        #expect(pair.leading == leading)
        #expect(pair.trailing == trailing)

        let half = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: .zero, trailing: .zero, geometryFrozen: false, lastStableLeading: leading, lastStableTrailing: .zero
        )
        #expect(half.leading == leading)
        #expect(half.trailing == .zero)

        let nothing = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: .zero, trailing: trailing, geometryFrozen: false, lastStableLeading: .zero, lastStableTrailing: .zero
        )
        #expect(nothing.leading == .zero)
        #expect(nothing.trailing == trailing)
        #expect(nothing.nextStableTrailing == .zero, "a lone trailing half is not remembered")
    }

    @Test("Following the visible edge left of the items grows the pill to meet it")
    func edgeGrowsPill() {
        let items = [CGRect(x: 1300, y: 0, width: 30, height: 24)]
        let stable = CGRect(x: 1294, y: 0, width: 200, height: 24)
        let result = MenuBarSplitPillGeometry.followingVisibleEdge(
            MenuBarLeadingEdgeSample(x: 1200, screenFrame: screen),
            itemBounds: items,
            stableTrailingBounds: stable,
            screenFrame: screen,
            revealedSection: nil
        )
        #expect(result.itemBounds.count == 2)
        #expect(result.itemBounds.last == CGRect(x: 1200, y: 0, width: 100, height: 24))
        #expect(result.stableTrailingBounds.minX == 1194)

        let unchanged = MenuBarSplitPillGeometry.followingVisibleEdge(
            MenuBarLeadingEdgeSample(x: 1300.5, screenFrame: screen),
            itemBounds: items,
            stableTrailingBounds: stable,
            screenFrame: screen,
            revealedSection: nil
        )
        #expect(unchanged.itemBounds == items, "a sub-point drift changes nothing")
    }
}

@Suite("Trailing pill membership")
@MainActor
struct TrailingPillMembershipTests {
    private static func item(_ title: String, x: CGFloat, isOnScreen: Bool = true) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example"), title: title, instanceIndex: 0),
            windowID: CGWindowID(x),
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: isOnScreen
        )
    }

    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test("While Hidden is revealed, Always Hidden items stay out unless it is the one revealed")
    func revealingKeepsAlwaysHiddenOut() {
        let visible = Self.item("V", x: 1400)
        let hidden = Self.item("H", x: 1300)
        let always = Self.item("A", x: 1200)
        let items = [always, hidden, visible]
        func sections(_ item: MenuBarItem) -> MenuBarSection.Name {
            switch item.tag.title {
            case "V": .visible
            case "H": .hidden
            default: .alwaysHidden
            }
        }
        let revealingHidden = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            context: .init(revealedSection: .hidden, section: sections, displayBounds: [display])
        )
        #expect(revealingHidden == [hidden.bounds, visible.bounds])

        let revealingAlways = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            context: .init(revealedSection: .alwaysHidden, section: sections, displayBounds: [display])
        )
        #expect(revealingAlways.count == 3)

        let atRest = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            context: .init(revealedSection: nil, section: sections, displayBounds: [display])
        )
        #expect(atRest == [visible.bounds])
    }

    @Test("Off-screen and empty items never join the pill")
    func offScreenItemsExcluded() {
        let offScreen = Self.item("O", x: 1300, isOnScreen: false)
        let empty = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example"), title: "E", instanceIndex: 0),
            windowID: 77,
            ownerPID: 1,
            sourcePID: 1,
            bounds: .zero,
            title: "E",
            isOnScreen: true
        )
        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: [offScreen, empty],
            context: .init(revealedSection: .hidden, section: { _ in .visible }, displayBounds: [display])
        )
        #expect(bounds.isEmpty)
    }
}
