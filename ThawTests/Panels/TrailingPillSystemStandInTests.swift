//
//  TrailingPillSystemStandInTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// The stand-in that keeps the split trailing pill at the display's trailing
/// edge when the walk came back without any MenuBarAgent-published frame.
struct TrailingPillSystemStandInTests {
    private let context = MenuBarSplitPillGeometry.TrailingPillContext(
        revealedSection: nil,
        section: { _ in .visible }
    )

    private let screenFrame = CGRect(x: 0, y: 0, width: 2177, height: 1407)

    private func thirdPartyItem(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .string("com.example.\(title)"),
                title: title,
                instanceIndex: 0
            ),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private func systemItem(title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .menuBarAgent,
                title: title,
                instanceIndex: 0
            ),
            windowID: UInt32(x) + 100,
            ownerPID: 655,
            sourcePID: 655,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A walk with system items adds no stand-in")
    func systemItemsPresentAddsNothing() {
        let items = [
            thirdPartyItem("Alfred", x: 800),
            thirdPartyItem("Stats", x: 1800),
            systemItem(title: "com.apple.menuextra.clock", x: 2050),
        ]

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            screenFrame: screenFrame,
            context: context
        )

        #expect(bounds.count == 3)
    }

    /// At high resolutions macOS 27 drops the system modules from the walk;
    /// the pill must still reach the trailing edge, not the last third-party icon.
    @Test("A walk without system items gets a trailing stand-in")
    func systemItemsMissingAddsStandIn() {
        let items = [
            thirdPartyItem("Alfred", x: 800),
            thirdPartyItem("Stats", x: 1800),
        ]

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            screenFrame: screenFrame,
            context: context
        )

        #expect(bounds.count == 3)
        let standIn = bounds.last
        #expect(standIn?.maxX == screenFrame.maxX)
        #expect(standIn?.width == 1)
    }

    @Test("An empty pill gets no stand-in")
    func emptyPillGetsNothing() {
        // No visible items means empty base bounds, so there is nothing to extend.
        let items = [thirdPartyItem("Alfred", x: 800)]
        let hiddenContext = MenuBarSplitPillGeometry.TrailingPillContext(
            revealedSection: nil,
            section: { _ in .hidden }
        )

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            screenFrame: screenFrame,
            context: hiddenContext
        )

        #expect(bounds.isEmpty)
    }

    /// The stand-in actually moves the pill's right edge to the display's
    /// trailing boundary once the outset is applied.
    @Test("The stand-in extends the pill's right edge")
    func standInExtendsPillRightEdge() {
        let items = [thirdPartyItem("Stats", x: 1800)]

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            screenFrame: screenFrame,
            context: context
        )
        let pill = MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: bounds,
            in: CGRect(x: 0, y: 0, width: 2177, height: 38),
            screenFrame: screenFrame,
            leadingOutset: 6,
            trailingOutset: 6,
            notchFrame: nil,
            notchMargin: 0
        )

        #expect(pill != .zero)
        #expect(pill.maxX >= screenFrame.maxX - 6)
    }
}
