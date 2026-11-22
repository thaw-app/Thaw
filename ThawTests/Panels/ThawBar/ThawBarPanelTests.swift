//
//  ThawBarPanelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
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

/// How the Thaw Bar appears: a short drop out of the menu bar, or a fade under Reduce Motion.
@MainActor
@Suite("Thaw Bar entrance")
struct ThawBarEntranceTests {
    @Test("The entrance is brief, and shorter still under Reduce Motion")
    func durations() {
        #expect(ThawBarEntrance.duration(reduceMotion: false) == 0.16)
        #expect(ThawBarEntrance.duration(reduceMotion: true) == 0.1)
    }

    @Test("The start pose sits above the rest pose and is scaled about the top center")
    func startTransformDropsFromTheMenuBar() {
        let size = CGSize(width: 200, height: 40)
        let start = ThawBarEntrance.startTransform(size: size)
        func apply(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * start.m11 + point.y * start.m21 + start.m41, y: point.x * start.m12 + point.y * start.m22 + start.m42)
        }
        let topCenter = apply(CGPoint(x: 100, y: 40))
        #expect(abs(topCenter.x - 100) < 0.001, "the top center stays centered")
        #expect(abs(topCenter.y - 46) < 0.001, "and starts 6 pt toward the menu bar")
        #expect(abs(start.m11 - 0.97) < 0.001)
    }

    @Test("Dismissing mid-entrance leaves the panel opaque with no animation left")
    func dismissResetsThePanel() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 50, height: 20), styleMask: .borderless, backing: .buffered, defer: true)
        panel.contentView?.wantsLayer = true
        panel.alphaValue = 0.3
        panel.contentView?.layer?.add(CABasicAnimation(keyPath: "transform"), forKey: ThawBarEntrance.animationKey)
        ThawBarEntrance.dismiss(panel)
        #expect(panel.alphaValue == 1)
        #expect(panel.contentView?.layer?.animation(forKey: ThawBarEntrance.animationKey) == nil)
        #expect(!panel.isVisible)
    }

    @Test("Presenting fades the panel in with the drop, and a reopen while visible doesn't restart the drop")
    func presentPlaysOnce() throws {
        let panel = NSPanel(contentRect: CGRect(x: -20000, y: -20000, width: 50, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        defer { ThawBarEntrance.dismiss(panel) }
        ThawBarEntrance.present(panel, reduceMotion: false)
        #expect(panel.isVisible)
        let layer = try #require(panel.contentView?.layer)
        #expect(layer.animation(forKey: ThawBarEntrance.animationKey) != nil)
        layer.removeAnimation(forKey: ThawBarEntrance.animationKey)
        ThawBarEntrance.present(panel, reduceMotion: false)
        #expect(layer.animation(forKey: ThawBarEntrance.animationKey) == nil, "already visible, so no second drop")

        let calm = NSPanel(contentRect: CGRect(x: -20000, y: -20000, width: 50, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        defer { ThawBarEntrance.dismiss(calm) }
        ThawBarEntrance.present(calm, reduceMotion: true)
        #expect(calm.contentView?.layer?.animation(forKey: ThawBarEntrance.animationKey) == nil)
    }

    @Test("The content's animation starts at the drop and ends at rest, with no movement under Reduce Motion")
    func contentAnimation() {
        let moving = ThawBarEntrance.contentAnimation(size: CGSize(width: 200, height: 40), reduceMotion: false)
        #expect(moving?.keyPath == "transform")
        let end = (moving?.toValue as? NSValue)?.caTransform3DValue
        #expect(end.map(CATransform3DIsIdentity) == true)
        #expect(ThawBarEntrance.contentAnimation(size: CGSize(width: 200, height: 40), reduceMotion: true) == nil)
    }
}

@MainActor
@Suite("Thaw Bar presentation", .serialized, .scratchDefaults)
struct ThawBarPresentationTests {
    @Test("A cold first show produces an onscreen panel without reopening")
    func coldFirstShow() async throws {
        let screen = try #require(NSScreen.main)
        let appState = AppState()
        let panel = ThawBarPanel()
        let originalPolicy = NSApp.activationPolicy()
        defer {
            panel.close()
            NSApp.setActivationPolicy(originalPolicy)
        }
        NSApp.setActivationPolicy(.accessory)
        panel.performSetup(
            with: appState,
            displayInvalidations: Empty<Void, Never>(completeImmediately: false),
            displaySettlements: Empty<EnvironmentChange, Never>(completeImmediately: false)
        )
        // This test asserts on a panel that stays up. The dismissal monitor is
        // global, so a click anywhere, any app on the machine running the
        // suite, would close the panel between the show and the assertions.
        panel.dismissesOnOutsideClick = false
        panel.show(section: .hidden, on: screen)
        #expect(screen.visibleFrame.contains(panel.frame), "The first show must be placed before ordering front: \(panel.frame)")
        try await Task.sleep(for: .milliseconds(350))
        #expect(appState.navigationState.isThawBarPresented)
        #expect(panel.isVisible)
        #expect(panel.frame.width > 0 && panel.frame.height > 0)
        #expect(screen.visibleFrame.contains(panel.frame), "Reported open, but outside the visible display: \(panel.frame)")

        // The retained hosting view must still be placed when its size hasn't changed.
        panel.close()
        panel.setFrameOrigin(NSPoint(x: screen.frame.maxX, y: screen.frame.maxY))
        panel.show(section: .hidden, on: screen)
        #expect(panel.isVisible)
        #expect(screen.visibleFrame.contains(panel.frame), "Reopening must restore onscreen placement: \(panel.frame)")
    }
}

/// Parked x = -1 or zero-height controls must not anchor the bar, which would clamp it to the left edge.
@Suite("Thaw Bar icon anchor")
struct ThawBarIconAnchorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test("The leading-edge sentinel is not a usable anchor")
    func rejectsParkedSentinel() {
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: -1, y: 0, width: 31, height: 24), screenFrame: screen))
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: -0.5, y: 0, width: 2, height: 0), screenFrame: screen))
    }

    @Test("A zero-height or zero-width frame is not a usable anchor")
    func rejectsDegenerateFrame() {
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 2360, y: 0, width: 35, height: 0), screenFrame: screen))
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 2360, y: 0, width: 0, height: 24), screenFrame: screen))
    }

    @Test("A real seat on the bar is a usable anchor")
    func acceptsRealSeat() {
        #expect(ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 1400, y: 0, width: 35, height: 24), screenFrame: screen))
    }

    @Test("A frame past the screen's right edge is not usable")
    func rejectsOffRightEdge() {
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 1450, y: 0, width: 35, height: 24), screenFrame: screen))
    }

    @Test("A real seat on a left display with negative coordinates is usable")
    func acceptsNegativeOriginSeat() {
        let leftScreen = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        #expect(ThawBarPanel.isUsableThawIconAnchor(CGRect(x: -400, y: 0, width: 24, height: 24), screenFrame: leftScreen))
    }
}

/// Uses the shared ledger the monitors read. The timestamps are far from any
/// real event's, and the last test leaves a press that dismissed nothing.
@MainActor
@Suite("Thaw Bar outside dismissal", .serialized)
struct ThawBarOutsideDismissalTests {
    @Test("A press that closes a section's bar is noted, so show-on-click doesn't reopen it")
    func sectionDismissalIsNoted() {
        let press = MousePress(type: .leftMouseDown, timestamp: 9_000_000)
        let panel = ThawBarPanel()
        defer { _ = MousePressLedger.shared.admit(MousePress(type: .leftMouseDown, timestamp: 9_000_100)) }

        panel.hide(dismissedBy: press)

        #expect(MousePressLedger.shared.admit(press))
        #expect(MousePressLedger.shared.currentPressDismissedBar)
        #expect(!panel.isVisible)
    }
}

@Suite("Mouse press from an event")
struct MousePressEventTests {
    @Test("A press read from an event keeps its type and timestamp")
    func pressFromEvent() throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 1234.5,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))

        #expect(MousePress(event) == MousePress(type: .rightMouseDown, timestamp: 1234.5))
    }
}
