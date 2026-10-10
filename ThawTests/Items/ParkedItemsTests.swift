//
//  ParkedItemsTests.swift
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
@Suite("Parked items and the repair identity")
struct ParkedItemsTests {
    @Test("The bar's centre comes from the seated visible control")
    func barCentreComesFromTheVisibleControl() {
        let control = Self.item(.visibleControlItem, y: 0, windowID: 1)
        let app = Self.item(Self.appTag("A"), y: 0, windowID: 2)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [app, control])
        #expect(reading.barMidY == control.bounds.midY)
        #expect(reading.parkedIDs.isEmpty)
    }

    @Test("An empty frame and a frame far below the bar are parked")
    func emptyAndFarFramesAreParked() {
        let control = Self.item(.visibleControlItem, y: 0, windowID: 1)
        let seated = Self.item(Self.appTag("A"), y: 0, windowID: 2)
        let empty = Self.item(Self.appTag("B"), y: 0, windowID: 3, size: .zero)
        let far = Self.item(Self.appTag("C"), y: 1068, windowID: 4)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [control, seated, empty, far])
        #expect(reading.parkedIDs == [3, 4])
    }

    @Test("Without a seated control there is no centre, and only empty or off-band frames are parked")
    func noControlMeansNoCentre() {
        let seated = Self.item(Self.appTag("A"), y: 0, windowID: 2)
        let empty = Self.item(Self.appTag("B"), y: 0, windowID: 3, size: .zero)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [seated, empty])
        #expect(reading.barMidY == nil)
        #expect(reading.parkedIDs == [3])
    }

    @Test("The repair identity is the item's identifier and owning process")
    func repairIdentityFollowsIdentifierAndOwner() {
        let first = Self.item(Self.appTag("A"), y: 0, windowID: 2)
        let sameItemNewWindow = Self.item(Self.appTag("A"), y: 0, windowID: 9)
        let relaunched = Self.item(Self.appTag("A"), y: 0, windowID: 2, ownerPID: 101)
        let id = PostRestrictionRepairItemID(first)
        #expect(id.uniqueIdentifier == first.uniqueIdentifier)
        #expect(id.ownerPID == first.ownerPID)
        #expect(id == PostRestrictionRepairItemID(sameItemNewWindow))
        #expect(id != PostRestrictionRepairItemID(relaunched))
    }

    private static func appTag(_ title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0)
    }

    private static func item(
        _ tag: MenuBarItemTag,
        y: CGFloat,
        windowID: CGWindowID,
        size: CGSize = CGSize(width: 24, height: 24),
        ownerPID: pid_t = 100
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: 200,
            bounds: CGRect(origin: CGPoint(x: 10, y: y), size: size),
            title: tag.title,
            isOnScreen: true
        )
    }
}
