//
//  MenuBarItemPhantomFrameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Evicted items can retain AX frames occupied by another item; boundary repair must not drag from those frames.
@Suite("Menu bar item phantom frames")
struct MenuBarItemPhantomFrameTests {
    private func item(
        _ title: String,
        x: CGFloat,
        y: CGFloat = 0,
        width: CGFloat = 24,
        windowID: CGWindowID
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("Distinct, non-overlapping frames are real")
    func distinctFramesAreReal() {
        let a = item("A", x: 600, windowID: 1)
        let b = item("B", x: 640, windowID: 2)
        #expect(!a.hasPhantomFrame(among: [a, b]))
        #expect(!b.hasPhantomFrame(among: [a, b]))
    }

    @Test("A duplicate minX is a phantom")
    func duplicateMinXIsPhantom() {
        let stranded = item("Stranded", x: 625, width: 118, windowID: 1)
        let occupant = item("Occupant", x: 625, windowID: 2)
        #expect(stranded.hasPhantomFrame(among: [stranded, occupant]))
    }

    @Test("A substantial horizontal overlap is a phantom")
    func substantialOverlapIsPhantom() {
        let stranded = item("Stranded", x: 625, width: 118, windowID: 1)
        let occupant = item("Occupant", x: 640, windowID: 2)
        #expect(stranded.hasPhantomFrame(among: [stranded, occupant]))
    }

    @Test("A sliver of overlap from sub-point rounding is real")
    func sliverOverlapIsReal() {
        let a = item("A", x: 600, windowID: 1)
        let b = item("B", x: 620, windowID: 2)
        #expect(!a.hasPhantomFrame(among: [a, b]))
    }

    @Test("The item itself is never its own phantom")
    func selfIsNotAPeer() {
        let a = item("A", x: 600, windowID: 1)
        #expect(!a.hasPhantomFrame(among: [a]))
    }

    @Test("A collapsed or sliver peer is not a seat")
    func collapsedPeerIsIgnored() {
        let a = item("A", x: 625, windowID: 1)
        let collapsed = item("Collapsed", x: 625, width: 0, windowID: 2)
        let sliver = item("Sliver", x: 625, width: 2, windowID: 3)
        #expect(!a.hasPhantomFrame(among: [a, collapsed, sliver]))
    }

    @Test("A one-point divider abutting a neighbour under fractional scaling is real")
    func abuttingDividerIsReal() {
        let a = item("A", x: 600.5, windowID: 1)
        let divider = item("Divider", x: 624, width: 1, windowID: 2)
        #expect(!a.hasPhantomFrame(among: [a, divider]))
    }

    @Test("A peer parked off the bar band is not a seat")
    func offBandPeerIsIgnored() {
        let a = item("A", x: 625, windowID: 1)
        let parked = item("Parked", x: 625, y: 1400, windowID: 2)
        #expect(!a.hasPhantomFrame(among: [a, parked]))
    }

    @Test("An item without a frame is not a phantom")
    func frameLessItemIsNotPhantom() {
        let a = item("A", x: 625, width: 0, windowID: 1)
        let b = item("B", x: 625, windowID: 2)
        #expect(!a.hasPhantomFrame(among: [a, b]))
    }
}
