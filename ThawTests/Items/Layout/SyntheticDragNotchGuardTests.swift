//
//  SyntheticDragNotchGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("A synthetic drag is refused when an endpoint is under a notch")
struct SyntheticDragNotchGuardTests {
    private let notch = CGRect(x: 700, y: 0, width: 200, height: 32)

    @Test("Endpoints clear of every notch pass")
    func clearEndpointsPass() {
        let covered = SyntheticDragNotchGuard.coveredEndpoint(
            start: CGPoint(x: 1000, y: 12),
            end: CGPoint(x: 1200, y: 12),
            notchRects: [notch]
        )
        #expect(covered == nil)
    }

    @Test("The grab point is reported before the drop point")
    func grabReportedFirst() throws {
        let start = CGPoint(x: 750, y: 12)
        let covered = try #require(SyntheticDragNotchGuard.coveredEndpoint(
            start: start,
            end: CGPoint(x: 800, y: 12),
            notchRects: [notch]
        ))
        #expect(covered.point == start)
        #expect(covered.notch == notch)
    }

    @Test("A drop under a notch on a second display is caught")
    func dropUnderSecondNotch() throws {
        let other = CGRect(x: 2500, y: 0, width: 180, height: 32)
        let end = CGPoint(x: 2600, y: 10)
        let covered = try #require(SyntheticDragNotchGuard.coveredEndpoint(
            start: CGPoint(x: 100, y: 10),
            end: end,
            notchRects: [notch, other]
        ))
        #expect(covered.point == end)
        #expect(covered.notch == other)
    }

    @Test("The notch's trailing edge is a visible column and is allowed")
    func trailingEdgeAllowed() {
        let covered = SyntheticDragNotchGuard.coveredEndpoint(
            start: CGPoint(x: notch.maxX, y: 12),
            end: CGPoint(x: notch.maxX + 10, y: 12),
            notchRects: [notch]
        )
        #expect(covered == nil)
    }

    @Test("Empty and null rectangles never cover anything")
    func degenerateRectsIgnored() {
        let covered = SyntheticDragNotchGuard.coveredEndpoint(
            start: CGPoint(x: 750, y: 12),
            end: CGPoint(x: 750, y: 12),
            notchRects: [.null, CGRect(x: 700, y: 0, width: 0, height: 32)]
        )
        #expect(covered == nil)
    }

    @Test("The live notch list has one entry at most per screen")
    @MainActor
    func liveNotchRectsAreBounded() {
        let rects = SyntheticDragNotchGuard.liveNotchRects()
        #expect(rects.count <= NSScreen.screens.count)
        for rect in rects {
            #expect(rect.width > 0)
        }
    }
}
