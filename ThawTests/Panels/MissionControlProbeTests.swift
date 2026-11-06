//
//  MissionControlProbeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Mission Control probe")
struct MissionControlProbeTests {
    private let rest = CGPoint(x: 960, y: 539)

    @Test("macOS 27 takes the probe off screen without moving it, and that counts as displaced")
    func offScreenCounts() {
        #expect(MissionControlShieldProbe.isDisplaced(isOnScreen: false, origin: rest, atRest: rest))
    }

    @Test("Moved on both axes counts, as on earlier macOS; resting or moved along one axis doesn't")
    func movement() {
        #expect(MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: 400, y: 300), atRest: rest))
        #expect(!MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: rest, atRest: rest))
        #expect(!MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: 400, y: rest.y), atRest: rest))
    }

    @Test("A drift of up to a point on both axes is still at rest")
    func pointOfDrift() {
        #expect(!MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: rest.x + 1, y: rest.y - 1), atRest: rest))
        #expect(MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: rest.x + 1.5, y: rest.y - 1.5), atRest: rest))
    }

    @Test("Only WindowManager's Exposé shield window counts as the shield")
    func shieldWindow() {
        #expect(MissionControlShieldProbe.isShieldWindow(ownerName: "WindowManager", title: "ExposeShieldWindow"))
        #expect(!MissionControlShieldProbe.isShieldWindow(ownerName: "WindowManager", title: "Desktop"))
        #expect(!MissionControlShieldProbe.isShieldWindow(ownerName: "Dock", title: "ExposeShieldWindow"))
        #expect(!MissionControlShieldProbe.isShieldWindow(ownerName: nil, title: nil))
    }
}
