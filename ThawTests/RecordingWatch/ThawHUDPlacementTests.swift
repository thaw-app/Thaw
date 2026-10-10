//
//  ThawHUDPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Where on a display the recording watch's banners land;
/// RecordingWatchScreenTests covers which display.
@Suite("HUD placement")
struct ThawHUDPlacementTests {
    /// A 1920×1080 primary display.
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    /// A display left of the primary, so its frame has a negative origin.
    private let leftOfPrimary = CGRect(x: -2560, y: 0, width: 2560, height: 1440)

    private let capsule: CGFloat = 200

    @Test("Center splits the screen evenly")
    func centerIsCentered() {
        let x = ThawHUDPlacement.center.originX(screenFrame: primary, width: capsule)

        #expect(x == 860)
        #expect(x - primary.minX == primary.maxX - (x + capsule))
    }

    @Test("Leading sits one inset from the left edge")
    func leadingHugsTheLeftEdge() {
        let x = ThawHUDPlacement.leading.originX(screenFrame: primary, width: capsule)

        #expect(x == ThawHUDPlacement.edgeInset)
    }

    @Test("Trailing sits one inset from the right edge")
    func trailingHugsTheRightEdge() {
        let x = ThawHUDPlacement.trailing.originX(screenFrame: primary, width: capsule)

        #expect(x + capsule == primary.maxX - ThawHUDPlacement.edgeInset)
    }

    @Test("Every placement respects a display with a negative origin")
    func placementsFollowTheScreenOrigin() {
        let leading = ThawHUDPlacement.leading.originX(screenFrame: leftOfPrimary, width: capsule)
        let center = ThawHUDPlacement.center.originX(screenFrame: leftOfPrimary, width: capsule)
        let trailing = ThawHUDPlacement.trailing.originX(screenFrame: leftOfPrimary, width: capsule)

        #expect(leading == leftOfPrimary.minX + ThawHUDPlacement.edgeInset)
        #expect(center == leftOfPrimary.midX - capsule / 2)
        #expect(trailing + capsule == leftOfPrimary.maxX - ThawHUDPlacement.edgeInset)
        // All three land on the display they were asked about, not the primary.
        for x in [leading, center, trailing] {
            #expect(x >= leftOfPrimary.minX)
            #expect(x + capsule <= leftOfPrimary.maxX)
        }
    }

    @Test("A capsule wider than the screen still starts on it")
    func anOversizedCapsuleStartsOnScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 320, height: 240)
        let wide: CGFloat = 400

        #expect(ThawHUDPlacement.leading.originX(screenFrame: narrow, width: wide) == ThawHUDPlacement.edgeInset)
        #expect(ThawHUDPlacement.center.originX(screenFrame: narrow, width: wide) < narrow.minX)
    }
}
