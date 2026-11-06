//
//  MirroredBarGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import MenuBarModel
import Testing

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
