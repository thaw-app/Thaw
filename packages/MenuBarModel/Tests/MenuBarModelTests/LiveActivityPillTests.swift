//
//  LiveActivityPillTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import MenuBarModel
import Testing

/// macOS draws a Live Activity where it likes. A weight written for it is ignored and a drag does
/// not move it, so Thaw shows it and leaves it alone.
struct LiveActivityPillTests {
    private func agentItem(_ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: title),
            windowID: 1,
            ownerPID: 731,
            sourcePID: 731,
            bounds: CGRect(x: 1377, y: 3, width: 70, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private var pill: MenuBarItem {
        agentItem("live-activity-pill-com.apple.chrono.WidgetRenderer-Activities")
    }

    @Test("A Live Activity is recognised by its identifier, whatever app it belongs to")
    func recognisedByIdentifier() {
        #expect(pill.tag.isLiveActivityPill)
        #expect(agentItem("live-activity-pill-com.example.Timer").tag.isLiveActivityPill)
        #expect(!agentItem("com.apple.menuextra.sound").tag.isLiveActivityPill)
        #expect(!MenuBarItemTag(namespace: .string("com.example.App"), title: "live-activity-pill-x").isLiveActivityPill)
    }

    @Test("It cannot be moved, with or without the Everything method")
    func cannotBeMoved() {
        #expect(!pill.isMovable)
        #expect(!pill.isMovable(experimentalSystemItemHiding: false))
        #expect(!pill.isMovable(experimentalSystemItemHiding: true))
        #expect(pill.orderabilityRefusal(experimentalSystemItemHiding: false) == .systemAnchored)
        #expect(pill.orderabilityRefusal(experimentalSystemItemHiding: true) == .systemAnchored)
        #expect(!pill.isPhysicallyOrderable(experimentalSystemItemHiding: true))
    }

    @Test("It is shown in Layout and cannot be assigned to a hidden section")
    func shownButNotHideable() {
        #expect(pill.sectionManagementPolicy == .forcedVisible)
        #expect(pill.sectionManagementPolicy(experimentalSystemItemHiding: true) == .forcedVisible)
        #expect(!pill.canBeHidden)
        #expect(!pill.canBeHidden(experimentalSystemItemHiding: true))
    }

    @Test("An ordinary module keeps its verdicts")
    func ordinaryModulesAreUnaffected() {
        let wifi = agentItem("com.apple.menuextra.wifi")
        #expect(wifi.isMovable)
        #expect(wifi.sectionManagementPolicy == .hideable)
    }
}
