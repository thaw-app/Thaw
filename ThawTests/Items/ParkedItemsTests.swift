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
    private static nonisolated let screens = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 2560, y: 290, width: 1710, height: 1107),
    ]

    @Test("The bar's centre comes from the seated visible control", arguments: [[], screens])
    func barCentreComesFromTheVisibleControl(screens: [CGRect]) {
        let control = Self.item(.visibleControlItem, y: 0, windowID: 1)
        let app = Self.item(Self.appTag("A"), y: 0, windowID: 2)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [app, control], screens: screens)
        #expect(reading.barMidY == control.bounds.midY)
        #expect(reading.parkedIDs.isEmpty)
    }

    @Test("An empty frame and a frame far below the bar are parked", arguments: [[], screens])
    func emptyAndFarFramesAreParked(screens: [CGRect]) {
        let control = Self.item(.visibleControlItem, y: 0, windowID: 1)
        let seated = Self.item(Self.appTag("A"), y: 0, windowID: 2)
        let empty = Self.item(Self.appTag("B"), y: 0, windowID: 3, size: .zero)
        let far = Self.item(Self.appTag("C"), y: 1068, windowID: 4)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [control, seated, empty, far], screens: screens)
        #expect(reading.parkedIDs == [3, 4])
    }

    @Test("Without a seated control there is no centre, and only empty or off-band frames are parked", arguments: [[], screens])
    func noControlMeansNoCentre(screens: [CGRect]) {
        let seated = Self.item(Self.appTag("A"), y: 0, windowID: 2)
        let empty = Self.item(Self.appTag("B"), y: 0, windowID: 3, size: .zero)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [seated, empty], screens: screens)
        #expect(reading.barMidY == nil)
        #expect(reading.parkedIDs == [3])
    }

    @Test("A lower display's bar is seated, but empty and far-below frames are parked")
    func lowerDisplayBarIsSeated() {
        let control = Self.item(.visibleControlItem, x: 3722.5, y: 295, windowID: 1, size: CGSize(width: 2, height: 24))
        let seated = Self.item(Self.appTag("A"), x: 3600, y: 295, windowID: 2)
        let empty = Self.item(Self.appTag("B"), x: 3600, y: 295, windowID: 3, size: .zero)
        let lowerParked = Self.item(Self.appTag("C"), x: 3600, y: 1068, windowID: 4)
        let mainParked = Self.item(Self.appTag("D"), y: 1400, windowID: 5)
        let reading = ParkedItems.parkedSetAndBarMidY(
            in: [control, seated, empty, lowerParked, mainParked], screens: Self.screens
        )
        #expect(reading.barMidY == 307)
        #expect(reading.parkedIDs == [3, 4, 5])
    }

    @Test("A bar with no reference does not use another screen's control")
    func referenceDoesNotCrossScreens() {
        let control = Self.item(.visibleControlItem, y: 0, windowID: 1)
        let lowerSeated = Self.item(Self.appTag("A"), x: 3600, y: 295, windowID: 2)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [control, lowerSeated], screens: Self.screens)
        #expect(reading.barMidY == 12)
        #expect(reading.parkedIDs.isEmpty)
    }

    @Test("Each screen uses its own control's mid-line and the first screen supplies the returned centre")
    func referencesArePerScreen() {
        let mainControl = Self.item(.visibleControlItem, y: 0, windowID: 1)
        let lowerControl = Self.item(.visibleControlItem, x: 3722.5, y: 295, windowID: 2)
        let mainSeated = Self.item(Self.appTag("A"), y: 0, windowID: 3)
        let lowerSeated = Self.item(Self.appTag("B"), x: 3600, y: 295, windowID: 4)
        let mainDisplaced = Self.item(Self.appTag("C"), y: 60, windowID: 5)
        let lowerDisplaced = Self.item(Self.appTag("D"), x: 3600, y: 350, windowID: 6)
        let reading = ParkedItems.parkedSetAndBarMidY(
            in: [lowerControl, mainControl, mainSeated, lowerSeated, mainDisplaced, lowerDisplaced], screens: Self.screens
        )
        #expect(reading.barMidY == 12)
        #expect(reading.parkedIDs == [5, 6])
    }

    @Test("A seated wide control supplies a lower bar's reference when the visible control is parked")
    func lowerDisplayFallsBackToSeatedControl() {
        let visible = Self.item(.visibleControlItem, x: 3722.5, y: 1068, windowID: 1)
        let hidden = Self.item(.hiddenControlItem, x: 3700, y: 295, windowID: 2)
        let seated = Self.item(Self.appTag("A"), x: 3600, y: 295, windowID: 3)
        let displaced = Self.item(Self.appTag("B"), x: 3600, y: 350, windowID: 4)
        let reading = ParkedItems.parkedSetAndBarMidY(in: [visible, hidden, seated, displaced], screens: Self.screens)
        #expect(reading.barMidY == 307)
        #expect(reading.parkedIDs == [1, 4])
    }

    @Test("Leading-edge sentinels stay seated in their own bar band, with that bar's distance check")
    func sentinelsUseTheirBarBand() {
        let mainControl = Self.item(.visibleControlItem, y: 0, windowID: 1)
        let lowerControl = Self.item(.visibleControlItem, x: 3722.5, y: 295, windowID: 2)
        let mainSentinel = Self.item(Self.appTag("A"), x: -1, y: 3, windowID: 3)
        let lowerSentinel = Self.item(Self.appTag("B"), x: -1, y: 295, windowID: 4)
        let parkedSentinel = Self.item(Self.appTag("C"), x: -1, y: 1400, windowID: 5)
        let displacedSentinel = Self.item(Self.appTag("D"), x: -1, y: 350, windowID: 6)
        let reading = ParkedItems.parkedSetAndBarMidY(
            in: [mainControl, lowerControl, mainSentinel, lowerSentinel, parkedSentinel, displacedSentinel], screens: Self.screens
        )
        #expect(reading.parkedIDs == [5, 6])
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
        x: CGFloat = 10,
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
            bounds: CGRect(origin: CGPoint(x: x, y: y), size: size),
            title: tag.title,
            isOnScreen: true
        )
    }
}
