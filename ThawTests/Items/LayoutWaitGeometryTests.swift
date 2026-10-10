//
//  LayoutWaitGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Layout wait geometry")
struct LayoutWaitGeometryTests {
    @Test("A persisted timeout is clamped to the Layout control's range")
    func timeoutIsClamped() {
        #expect(LayoutWaitGeometry.clampedResortTimeout(0) == 1)
        #expect(LayoutWaitGeometry.clampedResortTimeout(4) == 4)
        #expect(LayoutWaitGeometry.clampedResortTimeout(600) == 15)
    }

    @Test("The deadline is the clamped timeout past the start")
    func deadlineFollowsTheClampedTimeout() {
        let start = ContinuousClock.now
        #expect(LayoutWaitGeometry.menuBarAgentResortDeadline(timeout: 4, from: start) == start + .seconds(4))
        #expect(LayoutWaitGeometry.menuBarAgentResortDeadline(timeout: 600, from: start) == start + .seconds(15))
    }

    @Test("The signature records each item's leading edge")
    func signatureRecordsLeadingEdges() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        #expect(LayoutWaitGeometry.layoutGeometrySignature([a, b]) == [a.uniqueIdentifier: 10, b.uniqueIdentifier: 40])
    }

    @Test("Only an item in both snapshots that moved at least epsilon counts as motion")
    func motionNeedsASharedItemPastEpsilon() {
        #expect(!LayoutWaitGeometry.layoutGeometryChanged(from: ["a": 10], to: ["a": 10.5]))
        #expect(LayoutWaitGeometry.layoutGeometryChanged(from: ["a": 10], to: ["a": 11]))
        #expect(LayoutWaitGeometry.layoutGeometryChanged(from: ["a": 10], to: ["a": 10.5], epsilon: 0.5))
        // Rows blinking in and out are not motion.
        #expect(!LayoutWaitGeometry.layoutGeometryChanged(from: ["a": 10], to: ["b": 300]))
        #expect(!LayoutWaitGeometry.layoutGeometryChanged(from: ["a": 10, "b": 40], to: ["a": 10]))
    }

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}
