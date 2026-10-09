//
//  AXPrimitivesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import ThawAXCore

struct AXPrimitivesTests {
    @Test
    func `only this process counts as its own`() {
        #expect(AXPrimitives.isOwnProcess(getpid()))
        #expect(!AXPrimitives.isOwnProcess(getppid()))
        #expect(!AXPrimitives.isOwnProcess(0))
    }

    @Test
    func `frame is within uses the midpoint`() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(AXPrimitives.frame(CGRect(x: 90, y: 90, width: 20, height: 20), isWithin: display))
        #expect(!AXPrimitives.frame(CGRect(x: 95, y: 95, width: 20, height: 20), isWithin: display))
    }

    @Test
    func `a parked frame belongs to no display`() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(AXPrimitives.frame(CGRect(x: -1, y: 500, width: 20, height: 20), isWithin: display))
    }

    @Test
    func `an item frame overflowing the bar is cut to the bar its centre implies`() {
        // A 24 pt item reported as a 258 pt box centred on a 31 pt bar.
        let frame = CGRect(x: 3411, y: -113.5, width: 24, height: 258)
        #expect(AXPrimitives.itemFrame(frame, maximumHeight: 40, displayTop: 0)
            == CGRect(x: 3411, y: 0, width: 24, height: 31))
    }

    @Test
    func `popovers and off-centre boxes stay rejected`() {
        // Hangs below the bar.
        #expect(AXPrimitives.itemFrame(CGRect(x: 100, y: 24, width: 300, height: 250), maximumHeight: 40, displayTop: 0) == nil)
        // Reaches above the display but its centre implies no bar.
        #expect(AXPrimitives.itemFrame(CGRect(x: 100, y: -300, width: 24, height: 258), maximumHeight: 40, displayTop: 0) == nil)
        // Display unknown.
        #expect(AXPrimitives.itemFrame(CGRect(x: 100, y: -113.5, width: 24, height: 258), maximumHeight: 40, displayTop: nil) == nil)
    }

    @Test
    func `an ordinary item frame is kept as is`() {
        let frame = CGRect(x: 100, y: 3.5, width: 24, height: 24)
        #expect(AXPrimitives.itemFrame(frame, maximumHeight: 40, displayTop: nil) == frame)
        #expect(AXPrimitives.itemFrame(CGRect(x: 100, y: 0, width: 24, height: 0), maximumHeight: 40, displayTop: 0) == nil)
    }

    @Test
    func `press treats success as opened`() {
        var askedOwner = false
        let opened = AXPrimitives.press(perform: { .success }, ownerPID: {
            askedOwner = true
            return nil
        })
        #expect(opened)
        #expect(!askedOwner)
    }

    @Test
    func `press treats a plain failure as not opened`() {
        #expect(!AXPrimitives.press(perform: { .failure }, ownerPID: { nil }))
    }

    @Test
    func `press cannot complete without an owner is not opened`() {
        #expect(!AXPrimitives.press(perform: { .cannotComplete }, ownerPID: { nil }))
    }

    @Test
    func `press cannot complete without an open menu is not opened`() {
        // The test process has no window on the popup menu layer, so a
        // cannotComplete that no open menu explains is a failure.
        #expect(!AXPrimitives.press(perform: { .cannotComplete }, ownerPID: { getpid() }))
    }

    @Test
    func `no process is tracking an open menu at a bogus pid`() {
        #expect(!AXPrimitives.isTrackingOpenMenu(pid: -1))
    }
}
