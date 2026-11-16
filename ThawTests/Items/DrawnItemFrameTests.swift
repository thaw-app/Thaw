//
//  DrawnItemFrameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw
import ThawAXCore

/// Pins where Thaw clicks and whether it crops a revealed item, from MenuBarAgent's own window.
@Suite("Drawn item frame")
struct DrawnItemFrameTests {
    private static let agent: pid_t = 786
    private static let driveDx: pid_t = 1096
    private static let windowManager: pid_t = 964

    private static func entry(_ pid: pid_t, x: CGFloat, width: CGFloat) -> MenuBarAgentWindow.Entry {
        MenuBarAgentWindow.Entry(ownerPID: pid, frame: CGRect(x: x, y: 0, width: width, height: 33))
    }

    /// DriveDx reported at x=926 while drawn at x=908, with Window Manager drawn at x=926.
    private static let axFrame = CGRect(x: 926, y: 4.5, width: 20, height: 24)
    private static let bar = [
        entry(agent, x: 1088, width: 22),
        entry(driveDx, x: 908, width: 18),
        entry(windowManager, x: 926, width: 24),
    ]

    // MARK: drawnFrame

    @Test("One drawn entry gives its x and width, with the Accessibility frame's y and height")
    func oneEntry() {
        let drawn = DrawnItemFrame.drawnFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: Self.driveDx, in: Self.bar)

        #expect(drawn == CGRect(x: 908, y: 4.5, width: 18, height: 24))
    }

    @Test("An app with nothing drawn, or a read that failed, gives no drawn frame")
    func noEntry() {
        #expect(DrawnItemFrame.drawnFrame(for: Self.axFrame, ownerPID: 555, sourcePID: nil, in: Self.bar) == nil)
        #expect(DrawnItemFrame.drawnFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: nil) == nil)
    }

    @Test("An app with several items drawn can't say which is this one")
    func severalEntries() {
        let bar = Self.bar + [Self.entry(Self.driveDx, x: 880, width: 20)]

        #expect(DrawnItemFrame.drawnFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: bar) == nil)
    }

    @Test("An item MenuBarAgent hosts is found by its source process")
    func hostedItem() {
        let drawn = DrawnItemFrame.drawnFrame(for: Self.axFrame, ownerPID: Self.agent, sourcePID: Self.driveDx, in: Self.bar)

        #expect(drawn?.minX == 908)
    }

    @Test("A hosted item whose app has nothing drawn doesn't take MenuBarAgent's own entry")
    func hostedItemIgnoresTheHost() {
        // The bar has exactly one entry of MenuBarAgent's, an item of its own.
        #expect(DrawnItemFrame.drawnFrame(for: Self.axFrame, ownerPID: Self.agent, sourcePID: 555, in: Self.bar) == nil)
    }

    @Test("A read taken while an item leaves the bar is not trusted")
    func unsettledRead() {
        let bar = Self.bar + [Self.entry(0, x: 0, width: 0)]

        #expect(DrawnItemFrame.drawnFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: bar) == nil)
        #expect(!DrawnItemFrame.isPhantom(Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: bar))
    }

    // MARK: isPhantom

    @Test("A frame on another app's drawn item is a phantom")
    func phantomOverlap() {
        #expect(DrawnItemFrame.isPhantom(Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar))
        let shifted = CGRect(x: 930, y: 4.5, width: 20, height: 24)
        #expect(DrawnItemFrame.isPhantom(shifted, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar))
    }

    @Test("A frame next to another app's item, or on the app's own, is no phantom")
    func adjacentIsNoPhantom() {
        let adjacent = CGRect(x: 950, y: 4.5, width: 20, height: 24)
        #expect(!DrawnItemFrame.isPhantom(adjacent, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar))
        let onOwn = CGRect(x: 908, y: 4.5, width: 18, height: 24)
        #expect(!DrawnItemFrame.isPhantom(onOwn, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar))
    }

    @Test("A sliver such as a section divider doesn't make a phantom")
    func sliverIsNoPeer() {
        let bar = [Self.entry(Self.agent, x: 926, width: 1)]

        #expect(!DrawnItemFrame.isPhantom(Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: bar))
    }

    // MARK: clickFrame

    @Test("A click aims where the item is drawn")
    func clickAimsAtDrawn() {
        #expect(DrawnItemFrame.clickFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar)?.minX == 908)
    }

    @Test("A phantom frame with nothing drawn gets no click; a plain frame keeps its own")
    func clickWithoutDrawn() {
        let bar = Self.bar.filter { $0.ownerPID != Self.driveDx }
        #expect(DrawnItemFrame.clickFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: bar) == nil)

        let clear = CGRect(x: 960, y: 4.5, width: 20, height: 24)
        #expect(DrawnItemFrame.clickFrame(for: clear, ownerPID: Self.driveDx, sourcePID: nil, in: bar) == clear)
        #expect(DrawnItemFrame.clickFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: nil) == Self.axFrame)
    }

    // MARK: cropFrame

    @Test("A picture is cut where the item is drawn, at the size it reports")
    func cropMovesToTheDrawnSeat() {
        let crop = DrawnItemFrame.cropFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar)

        #expect(crop == CGRect(x: 907, y: 4.5, width: 20, height: 24), "Centred on the drawn frame's middle, x=917")
    }

    @Test("A picture stays at the reported frame while the drawn one is the same seat")
    func cropStaysOnAnAgreeingSeat() {
        let onSeat = [Self.entry(Self.driveDx, x: 929, width: 16)]
        #expect(DrawnItemFrame.cropFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: onSeat) == Self.axFrame)

        let twoPointsOff = [Self.entry(Self.driveDx, x: 930, width: 16)]
        #expect(DrawnItemFrame.cropFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: twoPointsOff) == Self.axFrame)
    }

    @Test("Without one drawn entry of its own, a picture is cut at the reported frame")
    func cropWithoutDrawn() {
        let noEntry = Self.bar.filter { $0.ownerPID != Self.driveDx }
        let twoEntries = Self.bar + [Self.entry(Self.driveDx, x: 880, width: 20)]

        #expect(DrawnItemFrame.cropFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: noEntry) == Self.axFrame)
        #expect(DrawnItemFrame.cropFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: twoEntries) == Self.axFrame)
        #expect(DrawnItemFrame.cropFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: nil) == Self.axFrame)
    }

    @Test("A crop that runs four points or more into another app's drawn item takes in its neighbour")
    func cropTakingInANeighbour() {
        // DriveDx drawn at 908 to 926, Window Manager from 926. A 20 wide crop there ends a point into it.
        let own = DrawnItemFrame.cropFrame(for: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar)
        #expect(!DrawnItemFrame.takesInNeighbour(own, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar))

        // Reported 38 wide, the crop runs from 898 to 936: ten points of Window Manager.
        let wide = DrawnItemFrame.cropFrame(for: CGRect(x: 920, y: 4.5, width: 38, height: 24), ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar)
        #expect(wide == CGRect(x: 898, y: 4.5, width: 38, height: 24))
        #expect(DrawnItemFrame.takesInNeighbour(wide, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar))

        #expect(!DrawnItemFrame.takesInNeighbour(wide, ownerPID: Self.driveDx, sourcePID: nil, in: nil), "An unreadable bar says nothing")
    }

    // MARK: Displays

    /// 2026-11-11, left display's bar active: DockDoor read at x=-191, but the click went to
    /// x=1722.5, where MenuBarAgent's first window, the main display's bar, draws it.
    private static let displays = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: -2048, y: 0, width: 2048, height: 1152),
    ]
    private static let dockDoor: pid_t = 79536
    private static let onSecondDisplay = CGRect(x: -191, y: 3, width: 24, height: 24)
    private static let mainBar = [
        entry(agent, x: 1088, width: 22),
        entry(dockDoor, x: 1722.5, width: 38),
    ]

    @Test("Another display's bar neither moves the click there nor makes the frame a phantom")
    func anotherDisplaysBarIsIgnored() {
        let click = DrawnItemFrame.clickFrame(
            for: Self.onSecondDisplay, ownerPID: Self.dockDoor, sourcePID: nil, in: Self.mainBar, displays: Self.displays
        )

        #expect(click == Self.onSecondDisplay)
        #expect(DrawnItemFrame.drawnFrame(for: Self.onSecondDisplay, ownerPID: Self.dockDoor, sourcePID: nil, in: Self.mainBar, displays: Self.displays) == nil)
        #expect(!DrawnItemFrame.isPhantom(Self.onSecondDisplay, ownerPID: Self.dockDoor, sourcePID: nil, in: Self.mainBar, displays: Self.displays))
    }

    @Test("The bar of the item's own display is still used")
    func ownDisplaysBarIsUsed() {
        let drawn = DrawnItemFrame.clickFrame(
            for: CGRect(x: 1741, y: 3, width: 24, height: 24), ownerPID: Self.dockDoor, sourcePID: nil, in: Self.mainBar, displays: Self.displays
        )

        #expect(drawn?.minX == 1722.5)
        #expect(drawn?.width == 38)
    }

    @Test("With stacked displays, an item drawn at the same x on the other bar doesn't make the frame a phantom")
    func stackedDisplaysShareX() {
        let displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: -1152, width: 2048, height: 1152)]
        let onUpperBar = CGRect(x: 926, y: -1149, width: 20, height: 24)
        let lowerBar = [Self.entry(Self.windowManager, x: 926, width: 24)]

        #expect(DrawnItemFrame.isPhantom(onUpperBar, ownerPID: Self.driveDx, sourcePID: nil, in: lowerBar), "Without displays, the x alone decides")
        #expect(!DrawnItemFrame.isPhantom(onUpperBar, ownerPID: Self.driveDx, sourcePID: nil, in: lowerBar, displays: displays))
        #expect(DrawnItemFrame.clickFrame(for: onUpperBar, ownerPID: Self.driveDx, sourcePID: nil, in: lowerBar, displays: displays) == onUpperBar)
    }
}
