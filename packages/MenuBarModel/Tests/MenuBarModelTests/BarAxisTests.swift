//
//  BarAxisTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing

@Suite("Shared bar axis")
struct BarAxisTests {
    private static var arrangements: [[CGRect]] {
        [
            [
                CGRect(x: 0, y: 0, width: 2560, height: 1440),
                CGRect(x: 2560, y: 290, width: 1710, height: 1107),
            ],
            [
                CGRect(x: 0, y: 0, width: 2560, height: 1440),
                CGRect(x: 2560, y: 0, width: 1710, height: 1107),
            ],
            [
                CGRect(x: 0, y: 0, width: 1710, height: 1107),
                CGRect(x: -400, y: -1440, width: 2560, height: 1440),
            ],
        ]
    }

    private func items(on displays: [CGRect]) -> [MenuBarItem] {
        let positions: [(CGWindowID, CGFloat, CGFloat)] = [
            (9, 250, 20), (7, 400, 20), (5, 300, 200), (3, 300, 20), (1, 310, 40),
        ]
        return positions.enumerated().map { index, position in
            let display = displays[index % displays.count]
            let (id, leadingDistance, width) = position
            return MenuBarItem(
                tag: MenuBarItemTag(namespace: .string("com.example.axis"), title: "Item-\(id)"),
                windowID: id,
                ownerPID: 700,
                sourcePID: 700,
                bounds: CGRect(x: display.maxX - leadingDistance, y: display.minY + 5, width: width, height: 24),
                title: nil,
                isOnScreen: true
            )
        }
    }

    @Test("Mixed-bar ordering matches one bar and preserves input order for ties", arguments: arrangements)
    func mixedOrderingMatchesReference(displays: [CGRect]) throws {
        let mixed = items(on: displays)
        let reference = items(on: [displays[0]])
        let leading = try #require(MenuBarItem.sortByLeadingEdge(mixed, displayBounds: displays))
        let center = try #require(MenuBarItem.sortByVisualCenter(mixed, displayBounds: displays))
        #expect(leading.map(\.windowID) == [7, 1, 5, 3, 9])
        #expect(center.map(\.windowID) == [7, 3, 1, 9, 5])
        #expect(leading.map(\.windowID) == MenuBarItem.sortByLeadingEdge(reference).map(\.windowID))
        #expect(center.map(\.windowID) == MenuBarItem.sortByVisualCenter(reference).map(\.windowID))
        #expect(leading.allSatisfy { sorted in mixed.contains { $0.windowID == sorted.windowID && $0.bounds == sorted.bounds } })
        #expect(center.allSatisfy { sorted in mixed.contains { $0.windowID == sorted.windowID && $0.bounds == sorted.bounds } })
    }

    @Test("Reference frames stay unchanged and single-display sorts match the original APIs", arguments: arrangements)
    func referenceAndSingleDisplayAreUnchanged(displays: [CGRect]) {
        let referenceItems = items(on: [displays[0]])
        for item in referenceItems {
            #expect(MirroredBarGeometry.referenceAligned(item.bounds, displayBounds: displays.reversed()) == item.bounds)
        }
        for display in displays {
            let single = items(on: [display])
            #expect(MenuBarItem.sortByLeadingEdge(single, displayBounds: [display])?.map(\.windowID) == MenuBarItem.sortByLeadingEdge(single).map(\.windowID))
            #expect(MenuBarItem.sortByVisualCenter(single, displayBounds: [display])?.map(\.windowID) == MenuBarItem.sortByVisualCenter(single).map(\.windowID))
        }
    }

    @Test("An unlocatable midpoint makes alignment and both sorts undecidable", arguments: arrangements)
    func unknownDisplayIsUndecidable(displays: [CGRect]) {
        let frame = CGRect(x: 10000, y: 10000, width: 30, height: 24)
        let unknown = MenuBarItem(
            tag: .visibleControlItem,
            windowID: 11,
            ownerPID: 700,
            sourcePID: 700,
            bounds: frame,
            title: nil,
            isOnScreen: true
        )
        let mixed = items(on: displays) + [unknown]
        #expect(MirroredBarGeometry.referenceAligned(frame, displayBounds: displays) == nil)
        #expect(MenuBarItem.sortByLeadingEdge(mixed, displayBounds: displays) == nil)
        #expect(MenuBarItem.sortByVisualCenter(mixed, displayBounds: displays) == nil)
        #expect(MirroredBarGeometry.referenceAligned(mixed[0].bounds, displayBounds: []) == nil)
        #expect(MenuBarItem.sortByLeadingEdge(mixed, displayBounds: []) == nil)
        #expect(MenuBarItem.sortByVisualCenter(mixed, displayBounds: []) == nil)
        #expect(MenuBarItem.sortByLeadingEdge([], displayBounds: displays)?.isEmpty == true)
        #expect(MenuBarItem.sortByVisualCenter([], displayBounds: [])?.isEmpty == true)
    }

    @Test("The midpoint selects the source even when the leading edge is outside it", arguments: arrangements)
    func sourceMembershipUsesMidpoint(displays: [CGRect]) {
        let source = displays[1]
        let frame = CGRect(x: source.minX - 10, y: source.minY + 5, width: 30, height: 24)
        #expect(MirroredBarGeometry.referenceAligned(frame, displayBounds: displays) == CGRect(
            x: displays[0].maxX - source.width - 10, y: 5, width: 30, height: 24
        ))
    }

    @Test("Without an origin display, minY then minX chooses the reference", arguments: [false, true])
    func fallbackReferenceIsIndependentOfInputOrder(reverse: Bool) {
        let displays = [
            CGRect(x: 1200, y: 200, width: 1000, height: 800),
            CGRect(x: 600, y: 100, width: 1000, height: 800),
            CGRect(x: -600, y: 100, width: 1000, height: 800),
            CGRect(x: -1800, y: 300, width: 1000, height: 800),
        ]
        let bounds = reverse ? Array(displays.reversed()) : displays
        let frame = CGRect(x: 2160, y: 205, width: 20, height: 24)
        let expected = CGRect(x: 360, y: 105, width: 20, height: 24)
        #expect(MirroredBarGeometry.referenceAligned(frame, displayBounds: bounds) == expected)
        #expect(MirroredBarGeometry.referenceAligned(expected, displayBounds: bounds) == expected)
    }

    @Test("Active display bounds can be read off the main actor")
    func liveBoundsAreAvailableOffMainActor() async {
        let bounds = await Task.detached { BarAxis.liveDisplayBounds() }.value
        #expect(bounds.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test("Alignment preserves trailing distance and lands on the origin display's bar", arguments: arrangements)
    func alignmentPreservesTrailingDistance(displays: [CGRect]) throws {
        let source = displays[1]
        let frame = CGRect(x: source.maxX - 330, y: source.minY + 5, width: 30, height: 24)
        let aligned = try #require(MirroredBarGeometry.referenceAligned(frame, displayBounds: displays.reversed()))
        #expect(aligned == CGRect(x: displays[0].maxX - 330, y: 5, width: 30, height: 24))
        #expect(displays[0].maxX - aligned.maxX == 300)
        #expect(source.maxX - frame.maxX == 300)
    }
}
