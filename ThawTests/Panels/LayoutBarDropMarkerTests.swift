//
//  LayoutBarDropMarkerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
struct LayoutBarDropMarkerTests {
    /// Three 24-point icons, 6 points apart.
    private let frames = [0, 30, 60].map { CGRect(x: CGFloat($0), y: 0, width: 24, height: 24) }

    @Test("A dragged item's marker sits in the middle of the gap it holds open")
    func gapMarker() {
        #expect(LayoutBarDropMarker.x(inGap: [frames[1]]) == 42)
        #expect(LayoutBarDropMarker.x(inGap: [frames[0], frames[1]]) == 27)
        #expect(LayoutBarDropMarker.x(inGap: []) == nil)
    }

    @Test("A group lands before the nearest icon, or after it past its middle", arguments: [
        (x: CGFloat(-10), index: 0),
        (x: CGFloat(10), index: 0),
        (x: CGFloat(14), index: 1),
        (x: CGFloat(40), index: 1),
        (x: CGFloat(44), index: 2),
        (x: CGFloat(200), index: 3),
    ])
    func insertionIndex(x: CGFloat, index: Int) {
        #expect(LayoutBarDropMarker.insertionIndex(forX: x, among: frames) == index)
    }

    @Test("A group's marker sits on the boundary it is inserted at", arguments: [
        (index: 0, x: CGFloat(0)),
        (index: 1, x: CGFloat(27)),
        (index: 2, x: CGFloat(57)),
        (index: 3, x: CGFloat(84)),
        (index: 9, x: CGFloat(84)),
    ])
    func boundaryMarker(index: Int, x: CGFloat) {
        #expect(LayoutBarDropMarker.x(insertingAt: index, among: frames) == x)
    }

    @Test("The marker stays whole at either end of the bar")
    func markerStaysInside() {
        let bounds = CGRect(x: 0, y: 0, width: 84, height: 28)
        #expect(LayoutBarDropMarker.rect(atX: 0, in: bounds).minX == 0)
        #expect(LayoutBarDropMarker.rect(atX: 84, in: bounds).maxX == 84)
        #expect(LayoutBarDropMarker.rect(atX: 42, in: bounds) == CGRect(x: 41, y: 2, width: 2, height: 24))
    }
}
