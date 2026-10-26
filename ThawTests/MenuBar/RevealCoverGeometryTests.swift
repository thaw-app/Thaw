//
//  RevealCoverGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Testing
@testable import Thaw

@Suite("Reveal cover geometry")
struct RevealCoverGeometryTests {
    private typealias Geometry = RevealCoverGeometry

    private let main = Geometry.ScreenBar(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), height: 24)
    private let side = Geometry.ScreenBar(displayID: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), height: 30)

    private func item(at x: CGFloat, width: CGFloat = 30) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: 24)
    }

    @Test("The band ends a pill inset left of the first visible item and spans the concealed width")
    func singleDisplay() {
        let bands = Geometry.bands(
            visibleFrames: [item(at: 1100), item(at: 1000)],
            liveAnchorX: nil,
            screens: [main],
            concealedWidth: 200
        )
        #expect(bands == [1: CGRect(x: 780, y: 0, width: 210, height: 24)])
    }

    @Test("A live anchor on the home display replaces the cached edge, and one off it is ignored")
    func liveAnchor() {
        let live = Geometry.bands(visibleFrames: [item(at: 1000)], liveAnchorX: 950, screens: [main], concealedWidth: 200)
        #expect(live[1] == CGRect(x: 730, y: 0, width: 210, height: 24))
        let offDisplay = Geometry.bands(visibleFrames: [item(at: 1000)], liveAnchorX: 2000, screens: [main], concealedWidth: 200)
        #expect(offDisplay[1] == CGRect(x: 780, y: 0, width: 210, height: 24))
        let onEdge = Geometry.bands(visibleFrames: [item(at: 1000)], liveAnchorX: 0, screens: [main], concealedWidth: 200)
        #expect(onEdge[1]?.maxX == 990, "An anchor on the display's edge is not inside it")
    }

    @Test("A display with no seated items mirrors the home display's distance from the right edge")
    func mirroredDisplay() {
        let bands = Geometry.bands(visibleFrames: [item(at: 1000)], liveAnchorX: nil, screens: [main, side], concealedWidth: 200)
        #expect(bands[1] == CGRect(x: 780, y: 0, width: 210, height: 24))
        #expect(bands[2] == CGRect(x: 2700, y: 0, width: 210, height: 30))
    }

    @Test("Each display with seated items anchors on its own leftmost one, and home is the leftmost overall")
    func perDisplayEdges() {
        let bands = Geometry.bands(
            visibleFrames: [item(at: 2400), item(at: 2000), item(at: 1000)],
            liveAnchorX: 950,
            screens: [main, side],
            concealedWidth: 100
        )
        #expect(bands[1] == CGRect(x: 830, y: 0, width: 110, height: 24))
        #expect(bands[2] == CGRect(x: 1880, y: 0, width: 110, height: 30))
    }

    @Test("The band stops at the display's left edge, and a band with no room is left out")
    func clampedAndEmpty() {
        let wide = Geometry.bands(visibleFrames: [item(at: 1000)], liveAnchorX: nil, screens: [main], concealedWidth: 5000)
        #expect(wide[1] == CGRect(x: 0, y: 0, width: 990, height: 24))
        let noRoom = Geometry.bands(visibleFrames: [item(at: 5)], liveAnchorX: nil, screens: [main], concealedWidth: 100)
        #expect(noRoom.isEmpty)
    }

    @Test("Nothing to cover, or nothing seated to anchor on, gives no bands")
    func noBands() {
        #expect(Geometry.bands(visibleFrames: [item(at: 1000)], liveAnchorX: nil, screens: [main], concealedWidth: 0).isEmpty)
        #expect(Geometry.bands(visibleFrames: [], liveAnchorX: 900, screens: [main], concealedWidth: 100).isEmpty)
        let parked = CGRect(x: MenuBarItemGeometry.transientSentinelX, y: 0, width: 30, height: 24)
        #expect(Geometry.bands(visibleFrames: [parked], liveAnchorX: nil, screens: [main], concealedWidth: 100).isEmpty)
        let offBar = CGRect(x: 1000, y: 500, width: 30, height: 24)
        #expect(Geometry.bands(visibleFrames: [offBar], liveAnchorX: nil, screens: [main], concealedWidth: 100).isEmpty)
    }

    @Test("Each concealed item counts at least the minimum width plus spacing, with the margin on top")
    func concealedWidth() {
        #expect(Geometry.concealedWidth(itemWidths: []) == 0)
        let expected = (Geometry.minimumItemWidth + Geometry.itemSpacing + 30 + Geometry.itemSpacing) * Geometry.widthMargin
        #expect(Geometry.concealedWidth(itemWidths: [0, 30]) == expected)
    }

    @Test("The Thaw icon anchors on its width alone; other items must be on screen in the visible section")
    func anchoring() {
        #expect(Geometry.anchorsBand(width: 20, isVisibleControlItem: true, isOnScreen: false, isInVisibleSection: false))
        #expect(!Geometry.anchorsBand(width: 0, isVisibleControlItem: true, isOnScreen: true, isInVisibleSection: true))
        #expect(Geometry.anchorsBand(width: 20, isVisibleControlItem: false, isOnScreen: true, isInVisibleSection: true))
        #expect(!Geometry.anchorsBand(width: 20, isVisibleControlItem: false, isOnScreen: false, isInVisibleSection: true))
        #expect(!Geometry.anchorsBand(width: 20, isVisibleControlItem: false, isOnScreen: true, isInVisibleSection: false))
    }

    @Test("Only items outside the visible section that are not the Thaw icon are concealed")
    func concealment() {
        #expect(Geometry.isConcealed(isVisibleControlItem: false, isInVisibleSection: false))
        #expect(!Geometry.isConcealed(isVisibleControlItem: true, isInVisibleSection: false))
        #expect(!Geometry.isConcealed(isVisibleControlItem: false, isInVisibleSection: true))
    }

    @Test("The fade covers its fixed width, and never more than half a narrow band")
    func fadeEnd() {
        #expect(Geometry.fadeEnd(width: 320) == 0.1)
        #expect(Geometry.fadeEnd(width: 64) == 0.5)
        #expect(Geometry.fadeEnd(width: 20) == 0.5)
        #expect(Geometry.fadeEnd(width: 0) == 0.5)
    }

    @Test("The mask runs left to right, clear to opaque, over the band")
    @MainActor
    func fadeMask() throws {
        let mask = Geometry.fadeMask(width: 320, height: 24)
        #expect(mask.frame == CGRect(x: 0, y: 0, width: 320, height: 24))
        #expect(mask.startPoint == CGPoint(x: 0, y: 0.5))
        #expect(mask.endPoint == CGPoint(x: 1, y: 0.5))
        let locations = try #require(mask.locations).map(\.doubleValue)
        #expect(locations == [0, 0.1, 1])
        let colors = try #require(mask.colors as? [CGColor])
        #expect(colors.count == 3)
        #expect(colors.first?.alpha == 0)
        #expect(colors.last?.alpha == 1)
    }

    @Test("A watchdog deadline is pushed out, never pulled in")
    func watchdogDeadline() {
        #expect(Geometry.extendsWatchdog(to: 5, from: nil as Int?))
        #expect(Geometry.extendsWatchdog(to: 5, from: 4))
        #expect(!Geometry.extendsWatchdog(to: 5, from: 5))
        #expect(!Geometry.extendsWatchdog(to: 5, from: 6))
    }
}

@Suite("Reveal cover activity", .serialized)
struct RevealCoverActivityTests {
    private typealias Activity = RevealCoverActivity

    private func drain() {
        while Activity.isAnyMaskShowing {
            Activity.noteHidden()
        }
    }

    @Test("The count goes up and down, and never below zero")
    func neverNegative() {
        drain()
        Activity.noteHidden()
        #expect(!Activity.isAnyMaskShowing)
        Activity.noteShown()
        Activity.noteShown()
        Activity.noteHidden()
        #expect(Activity.isAnyMaskShowing)
        Activity.noteHidden()
        #expect(!Activity.isAnyMaskShowing)
        Activity.noteShown()
        #expect(Activity.isAnyMaskShowing, "A hide at zero did not leave a debt behind")
        drain()
    }

    @Test("Concurrent shows and hides balance out")
    func concurrent() {
        drain()
        DispatchQueue.concurrentPerform(iterations: 500) { _ in Activity.noteShown() }
        #expect(Activity.isAnyMaskShowing)
        DispatchQueue.concurrentPerform(iterations: 600) { _ in Activity.noteHidden() }
        #expect(!Activity.isAnyMaskShowing)
    }
}
