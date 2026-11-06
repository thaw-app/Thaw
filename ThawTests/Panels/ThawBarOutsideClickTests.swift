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

    @Test("A click at the very top of the screen above the icon counts as a click on it", arguments: [CGFloat(0), 3])
    func clickAboveTheIcon(quartzY: CGFloat) {
        // macOS 27 places the icon 4.5 points below the top, and still sends this click to it.
        let cached = CGRect(x: 1239, y: 4.5, width: 35, height: 24)
        #expect(ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: 1250, y: 1080 - quartzY),
            liveControlItemFrame: CGRect(x: 1239, y: 1051.5, width: 35, height: 24),
            liveScreenMaxY: 1080,
            quartzLocation: CGPoint(x: 1250, y: quartzY),
            cachedControlItemFrame: cached,
            cachedScreenMinY: 0
        ))
        #expect(ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: -500, y: 500),
            liveControlItemFrame: nil,
            quartzLocation: CGPoint(x: 1250, y: quartzY),
            cachedControlItemFrame: cached,
            cachedScreenMinY: 0
        ))
    }

    @Test("The same height beside the icon still dismisses the panel")
    func clickBesideTheIcon() {
        #expect(!ThawBarPanel.isControlItemClick(
            appKitLocation: CGPoint(x: 1200, y: 1080),
            liveControlItemFrame: CGRect(x: 1239, y: 1051.5, width: 35, height: 24),
            liveScreenMaxY: 1080,
            quartzLocation: CGPoint(x: 1200, y: 0),
            cachedControlItemFrame: CGRect(x: 1239, y: 4.5, width: 35, height: 24),
            cachedScreenMinY: 0
        ))
    }
}

@Suite("Thaw icon hit column")
struct ControlItemHitColumnTests {
    @Test("The column reaches the top of the screen, top row included, in both coordinate spaces")
    func reachesTheTop() {
        let appKit = ControlItemHitColumn.appKit(CGRect(x: 10, y: 1051.5, width: 35, height: 24), screenMaxY: 1080)
        #expect(appKit.contains(CGPoint(x: 20, y: 1080)))
        #expect(appKit.contains(CGPoint(x: 20, y: 1052)))
        #expect(!appKit.contains(CGPoint(x: 20, y: 1050)))
        let quartz = ControlItemHitColumn.quartz(CGRect(x: 10, y: 4.5, width: 35, height: 24), screenMinY: 0)
        #expect(quartz.contains(CGPoint(x: 20, y: 0)))
        #expect(!quartz.contains(CGPoint(x: 20, y: 29)))
        #expect(!quartz.contains(CGPoint(x: 50, y: 0)))
    }

    @Test("A display below the main one uses its own top")
    func secondDisplay() {
        let quartz = ControlItemHitColumn.quartz(CGRect(x: 10, y: 1084.5, width: 35, height: 24), screenMinY: 1080)
        #expect(quartz.contains(CGPoint(x: 20, y: 1080)))
        #expect(!quartz.contains(CGPoint(x: 20, y: 1079)))
    }
}
