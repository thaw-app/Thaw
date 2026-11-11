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

    // MARK: canCrop

    @Test("A crop is cut only where the item is drawn")
    func cropAgreement() {
        #expect(!DrawnItemFrame.canCrop(at: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: Self.bar))

        let onSeat = [Self.entry(Self.driveDx, x: 929, width: 16)]
        #expect(DrawnItemFrame.canCrop(at: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: onSeat))
    }

    @Test("Without a drawn entry, a crop is cut unless the frame is a phantom")
    func cropWithoutDrawn() {
        let bar = Self.bar.filter { $0.ownerPID != Self.driveDx }
        #expect(!DrawnItemFrame.canCrop(at: Self.axFrame, ownerPID: Self.driveDx, sourcePID: nil, in: bar))

        let clear = CGRect(x: 960, y: 4.5, width: 20, height: 24)
        #expect(DrawnItemFrame.canCrop(at: clear, ownerPID: Self.driveDx, sourcePID: nil, in: bar))
    }
}
