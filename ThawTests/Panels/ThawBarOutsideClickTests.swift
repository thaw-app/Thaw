//
//  ThawBarOutsideClickTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
struct ThawBarOutsideClickTests {
    @Test("A click on the live icon is not dismissed using its stale position on another display")
    func liveIconOnLeftDisplay() {
        // The 22:04:56 trace closed on mouse-down, then reopened on the icon's action 15 ms later.
        #expect(ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: -182, y: 1065),
            liveControlItemFrame: CGRect(x: -199, y: 1050, width: 33, height: 30),
            quartzLocation: CGPoint(x: -182, y: 15),
            cachedControlItemFrame: CGRect(x: 1720, y: 3, width: 35, height: 24)
        ))
    }

    @Test("A live icon hit does not require a populated AX cache")
    func liveIconWithoutCache() {
        #expect(ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: 1737, y: 1065),
            liveControlItemFrame: CGRect(x: 1721, y: 1050, width: 33, height: 30),
            quartzLocation: nil,
            cachedControlItemFrame: nil
        ))
    }

    @Test("Cached AX bounds still work when the live status window is unavailable")
    func cachedIconFallback() {
        #expect(ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: 1737, y: 1065),
            liveControlItemFrame: nil,
            quartzLocation: CGPoint(x: 1737, y: 15),
            cachedControlItemFrame: CGRect(x: 1720, y: 3, width: 35, height: 24)
        ))
    }

    @Test("A click outside both icon frames still dismisses the panel")
    func outsideBothFrames() {
        #expect(!ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: -500, y: 500),
            liveControlItemFrame: CGRect(x: -199, y: 1050, width: 33, height: 30),
            quartzLocation: CGPoint(x: -500, y: 580),
            cachedControlItemFrame: CGRect(x: 1720, y: 3, width: 35, height: 24)
        ))
    }

    @Test("AppKit and Quartz bounds are not tested against the other coordinate space")
    func coordinateSpacesStaySeparate() {
        #expect(!ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: 1737, y: 15),
            liveControlItemFrame: CGRect(x: 1721, y: 1050, width: 33, height: 30),
            quartzLocation: CGPoint(x: 1737, y: 1065),
            cachedControlItemFrame: CGRect(x: 1720, y: 3, width: 35, height: 24)
        ))
    }
}
