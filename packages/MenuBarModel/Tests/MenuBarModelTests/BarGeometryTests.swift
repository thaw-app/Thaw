//
//  BarGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
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

/// macOS 27 draws Thaw's icon on every bar but reports its frame in one
/// display's space. Display values are a measured two-display arrangement.
@Suite("Mirrored bar geometry")
struct MirroredBarGeometryTests {
    /// Main display: 1920×1080 at the origin, as measured.
    private static let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    /// Secondary: 2560×1440 to the left, as measured.
    private static let secondary = CGRect(x: -2560, y: 0, width: 2560, height: 1440)

    @Test("A frame on the display it was reported from is unchanged")
    func sameDisplayIsIdentity() {
        let frame = CGRect(x: 1588, y: 0, width: 35, height: 30)
        #expect(MirroredBarGeometry.rebasedFrame(frame, from: Self.main, to: Self.main) == frame)
    }

    @Test("A frame keeps its distance from the trailing edge across a mirror")
    func trailingDistanceSurvives() {
        // Visible control item on the 1920-wide main display: trailing edge at
        // 1623, i.e. 297 pt from the display's right edge.
        let reported = CGRect(x: 1588, y: 0, width: 35, height: 30)
        let rebased = MirroredBarGeometry.rebasedFrame(reported, from: Self.main, to: Self.secondary)
        // On the 2560-wide secondary the same 297 pt from its trailing edge.
        #expect(Self.secondary.maxX - rebased.maxX == Self.main.maxX - reported.maxX)
        #expect(rebased.maxX == Self.secondary.maxX - 297)
        #expect(rebased.width == reported.width)
    }

    @Test("The rebased frame contains a click where the icon is drawn")
    func rebasedFrameContainsTheMirroredClick() {
        let reported = CGRect(x: 1588, y: 0, width: 35, height: 30)
        let rebased = MirroredBarGeometry.rebasedFrame(reported, from: Self.main, to: Self.secondary)
        // Pointer at the icon's centre on the secondary bar, far from the
        // reported frame (x≈1588).
        let mirroredClick = CGPoint(x: rebased.midX, y: rebased.midY)
        #expect(rebased.contains(mirroredClick))
        #expect(!reported.contains(mirroredClick))
    }

    @Test("A display below another shifts the frame vertically")
    func verticalArrangementOffsets() {
        let lower = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let reported = CGRect(x: 100, y: 0, width: 30, height: 30)
        let rebased = MirroredBarGeometry.rebasedFrame(reported, from: Self.main, to: lower)
        #expect(rebased.minY == -1080)
    }

    /// A notched built-in display whose bar overflowed, below an external one
    /// with room to spare, as measured.
    private static let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private static let external = CGRect(x: 56, y: -1080, width: 1920, height: 1080)
    private static let displays = [builtIn, external]
    private static let chevronMinX: CGFloat = 1057.5
    private static let notchMaxX: CGFloat = 956.5

    @Test("A frame mirrored to the leading side of the lane is not drawn there", arguments: [chevronMinX, notchMaxX])
    func overflowedMirrorIsNotDrawn(laneMinX: CGFloat) {
        // A 179 pt text item on the external bar mirrors to x≈903 on the built-in one.
        let reported = CGRect(x: 1151, y: -1076.5, width: 179, height: 24)
        #expect(MirroredBarGeometry.frame(reported, on: Self.builtIn, displayBounds: Self.displays).minX == 903)
        #expect(MirroredBarGeometry.drawnFrame(
            reported, on: Self.builtIn, displayBounds: Self.displays, laneMinX: laneMinX
        ) == nil)
    }

    @Test("An overflowed item's own frame is not drawn either")
    func overflowedNativeFrameIsNotDrawn() {
        // Reported by the built-in bar itself, starting behind the notch and
        // running under the chevron.
        let reported = CGRect(x: 887, y: 4.5, width: 188, height: 24)
        #expect(MirroredBarGeometry.drawnFrame(
            reported, on: Self.builtIn, displayBounds: Self.displays, laneMinX: Self.chevronMinX
        ) == nil)
    }

    @Test("Frames inside the lane, and every frame without one, are kept")
    func drawnFramesAreKept() {
        let trailingChevron = CGRect(x: 1075, y: 4.5, width: 30, height: 24)
        #expect(MirroredBarGeometry.drawnFrame(
            trailingChevron, on: Self.builtIn, displayBounds: Self.displays, laneMinX: Self.chevronMinX
        ) == trailingChevron)
        let mirrored = CGRect(x: 1500, y: -1076.5, width: 30, height: 24)
        #expect(MirroredBarGeometry.drawnFrame(
            mirrored, on: Self.builtIn, displayBounds: Self.displays, laneMinX: Self.chevronMinX
        ) == MirroredBarGeometry.frame(mirrored, on: Self.builtIn, displayBounds: Self.displays))
        let wide = CGRect(x: 1151, y: -1076.5, width: 179, height: 24)
        #expect(MirroredBarGeometry.drawnFrame(
            wide, on: Self.external, displayBounds: Self.displays, laneMinX: nil
        ) == wide)
    }

    @Test("Equal-width displays reduce to the display origin offset")
    func equalWidthsOffsetByOrigin() {
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let reported = CGRect(x: 1588, y: 0, width: 35, height: 30)
        let rebased = MirroredBarGeometry.rebasedFrame(reported, from: Self.main, to: right)
        #expect(rebased.minX == right.minX + 1588)
    }
}

/// MenuBarItem.isParkedOffMenuBarBand(among:): the host parks an item it
/// cannot seat at origin.x == -1, in the bar's own Y band, which the Y-only
/// checks used to miss (a notched, overflowed bar parks the control item there).
@Suite("Parked off the menu bar band")
struct ParkedOffMenuBarBandTests {
    private static let screens = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 2560, y: 290, width: 1710, height: 1107),
    ]

    private func item(
        _ bounds: CGRect,
        tag: MenuBarItemTag = MenuBarItemTag(namespace: .string("com.example.app"), title: "Item-0")
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 1,
            ownerPID: 700,
            sourcePID: 700,
            bounds: bounds,
            title: tag.title,
            isOnScreen: true
        )
    }

    @Test("A lower bar is seated with its own reference or with only a main-display reference", arguments: [false, true])
    func lowerDisplayBarIsSeated(ownReference: Bool) {
        let lowerControl = item(CGRect(x: 3722.5, y: 295, width: 2, height: 24), tag: .visibleControlItem)
        let seated = item(CGRect(x: 3600, y: 295, width: 24, height: 24))
        let peers = ownReference ? [control, lowerControl, seated] : [control, seated]
        #expect(!seated.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(seated.isParkedOffMenuBarBand(among: peers, screens: []))
    }

    @Test("Distance is checked against a seated reference on the same display")
    func referenceIsPerScreen() {
        let lowerControl = item(CGRect(x: 3722.5, y: 295, width: 2, height: 24), tag: .visibleControlItem)
        let seated = item(CGRect(x: 3600, y: 295, width: 24, height: 24))
        let displaced = item(CGRect(x: 3600, y: 350, width: 24, height: 24))
        let farBelow = item(CGRect(x: 3600, y: 1068, width: 24, height: 24))
        let peers = [control, lowerControl, seated, displaced, farBelow]
        #expect(!seated.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(displaced.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(farBelow.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(!displaced.isParkedOffMenuBarBand(among: [control], screens: Self.screens))
    }

    @Test("A seated wide control is the fallback when the visible control is parked")
    func fallbackReferenceIsSeated() {
        let parkedControl = item(CGRect(x: 3722.5, y: 1068, width: 2, height: 24), tag: .visibleControlItem)
        let hidden = item(CGRect(x: 3700, y: 295, width: 24, height: 24), tag: .hiddenControlItem)
        let seated = item(CGRect(x: 3600, y: 295, width: 24, height: 24))
        let displaced = item(CGRect(x: 3600, y: 350, width: 24, height: 24))
        let peers = [parkedControl, hidden, seated, displaced]
        #expect(!seated.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(displaced.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
    }

    @Test("Screen membership uses the frame centre")
    func frameCentreSelectsScreen() {
        let straddling = item(CGRect(x: 2555, y: 285, width: 24, height: 24))
        #expect(!straddling.isParkedOffMenuBarBand(among: [control], screens: Self.screens))
        let offScreen = item(CGRect(x: 4500, y: 295, width: 24, height: 24))
        #expect(offScreen.isParkedOffMenuBarBand(among: [], screens: Self.screens))
    }

    @Test("Empty screens preserve negative-Y and peer-distance legacy readings")
    func emptyScreensPreserveLegacyBand() {
        let negativeY = item(CGRect(x: 1200, y: -20, width: 24, height: 24))
        let displaced = item(CGRect(x: 1200, y: 60, width: 24, height: 24))
        #expect(!negativeY.isParkedOffMenuBarBand(among: [control], screens: []))
        #expect(displaced.isParkedOffMenuBarBand(among: [control], screens: []))
        #expect(!displaced.isParkedOffMenuBarBand(among: [], screens: []))
    }

    private var control: MenuBarItem {
        item(CGRect(x: 1400, y: 4, width: 31, height: 24), tag: .visibleControlItem)
    }

    @Test("The leading-edge sentinel is parked", arguments: [[], screens])
    func sentinelIsParked(screens: [CGRect]) {
        let parked = item(CGRect(x: -1, y: 4, width: 31, height: 24))
        #expect(parked.isParkedOffMenuBarBand(among: [control, parked], screens: screens))
    }

    @Test("A real seat beside the bar is not parked", arguments: [[], screens])
    func realSeatIsNotParked(screens: [CGRect]) {
        let live = item(CGRect(x: 1200, y: 4, width: 24, height: 22))
        #expect(!live.isParkedOffMenuBarBand(among: [control, live], screens: screens))
    }

    @Test("A zero-size frame is parked", arguments: [[], screens])
    func zeroSizeIsParked(screens: [CGRect]) {
        let empty = item(CGRect(x: 1400, y: 0, width: 0, height: 0))
        #expect(empty.isParkedOffMenuBarBand(among: [control, empty], screens: screens))
        #expect(empty.isParkedOffMenuBarBand(among: [control, empty]))
    }

    @Test("The Y-band collateral park is still detected", arguments: [[], screens])
    func yBandIsParked(screens: [CGRect]) {
        let collateral = item(CGRect(x: 1200, y: 1400, width: 24, height: 22))
        #expect(collateral.isParkedOffMenuBarBand(among: [control, collateral], screens: screens))
    }
}
