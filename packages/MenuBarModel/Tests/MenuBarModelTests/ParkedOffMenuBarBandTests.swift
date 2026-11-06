//
//  ParkedOffMenuBarBandTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Foundation
@testable import MenuBarModel
import Testing

/// MenuBarItem.isParkedOffMenuBarBand(among:): the host parks an item it
/// cannot seat at origin.x == -1, in the bar's own Y band, which the Y-only
/// checks used to miss (a notched, overflowed bar parks the control item there).
@Suite("Parked off the menu bar band")
struct ParkedOffMenuBarBandTests {
    private static let screens = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 2560, y: 290, width: 1710, height: 1107),
    ]

    private func item(
        _ bounds: CGRect,
        tag: MenuBarItemTag = MenuBarItemTag(namespace: .string("com.example.app"), title: "Item-0")
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 1,
            ownerPID: 700,
            sourcePID: 700,
            bounds: bounds,
            title: tag.title,
            isOnScreen: true
        )
    }

    @Test("A lower bar is seated with its own reference or with only a main-display reference", arguments: [false, true])
    func lowerDisplayBarIsSeated(ownReference: Bool) {
        let lowerControl = item(CGRect(x: 3722.5, y: 295, width: 2, height: 24), tag: .visibleControlItem)
        let seated = item(CGRect(x: 3600, y: 295, width: 24, height: 24))
        let peers = ownReference ? [control, lowerControl, seated] : [control, seated]
        #expect(!seated.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(seated.isParkedOffMenuBarBand(among: peers, screens: []))
    }

    @Test("Distance is checked against a seated reference on the same display")
    func referenceIsPerScreen() {
        let lowerControl = item(CGRect(x: 3722.5, y: 295, width: 2, height: 24), tag: .visibleControlItem)
        let seated = item(CGRect(x: 3600, y: 295, width: 24, height: 24))
        let displaced = item(CGRect(x: 3600, y: 350, width: 24, height: 24))
        let farBelow = item(CGRect(x: 3600, y: 1068, width: 24, height: 24))
        let peers = [control, lowerControl, seated, displaced, farBelow]
        #expect(!seated.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(displaced.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(farBelow.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(!displaced.isParkedOffMenuBarBand(among: [control], screens: Self.screens))
    }

    @Test("A seated wide control is the fallback when the visible control is parked")
    func fallbackReferenceIsSeated() {
        let parkedControl = item(CGRect(x: 3722.5, y: 1068, width: 2, height: 24), tag: .visibleControlItem)
        let hidden = item(CGRect(x: 3700, y: 295, width: 24, height: 24), tag: .hiddenControlItem)
        let seated = item(CGRect(x: 3600, y: 295, width: 24, height: 24))
        let displaced = item(CGRect(x: 3600, y: 350, width: 24, height: 24))
        let peers = [parkedControl, hidden, seated, displaced]
        #expect(!seated.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
        #expect(displaced.isParkedOffMenuBarBand(among: peers, screens: Self.screens))
    }

    @Test("Screen membership uses the frame centre")
    func frameCentreSelectsScreen() {
        let straddling = item(CGRect(x: 2555, y: 285, width: 24, height: 24))
        #expect(!straddling.isParkedOffMenuBarBand(among: [control], screens: Self.screens))
        let offScreen = item(CGRect(x: 4500, y: 295, width: 24, height: 24))
        #expect(offScreen.isParkedOffMenuBarBand(among: [], screens: Self.screens))
    }

    @Test("Empty screens preserve negative-Y and peer-distance legacy readings")
    func emptyScreensPreserveLegacyBand() {
        let negativeY = item(CGRect(x: 1200, y: -20, width: 24, height: 24))
        let displaced = item(CGRect(x: 1200, y: 60, width: 24, height: 24))
        #expect(!negativeY.isParkedOffMenuBarBand(among: [control], screens: []))
        #expect(displaced.isParkedOffMenuBarBand(among: [control], screens: []))
        #expect(!displaced.isParkedOffMenuBarBand(among: [], screens: []))
    }

    private var control: MenuBarItem {
        item(CGRect(x: 1400, y: 4, width: 31, height: 24), tag: .visibleControlItem)
    }

    @Test("The leading-edge sentinel is parked", arguments: [[], screens])
    func sentinelIsParked(screens: [CGRect]) {
        let parked = item(CGRect(x: -1, y: 4, width: 31, height: 24))
        #expect(parked.isParkedOffMenuBarBand(among: [control, parked], screens: screens))
    }

    @Test("A real seat beside the bar is not parked", arguments: [[], screens])
    func realSeatIsNotParked(screens: [CGRect]) {
        let live = item(CGRect(x: 1200, y: 4, width: 24, height: 22))
        #expect(!live.isParkedOffMenuBarBand(among: [control, live], screens: screens))
    }

    @Test("A zero-size frame is parked", arguments: [[], screens])
    func zeroSizeIsParked(screens: [CGRect]) {
        let empty = item(CGRect(x: 1400, y: 0, width: 0, height: 0))
        #expect(empty.isParkedOffMenuBarBand(among: [control, empty], screens: screens))
        #expect(empty.isParkedOffMenuBarBand(among: [control, empty]))
    }

    @Test("The Y-band collateral park is still detected", arguments: [[], screens])
    func yBandIsParked(screens: [CGRect]) {
        let collateral = item(CGRect(x: 1200, y: 1400, width: 24, height: 22))
        #expect(collateral.isParkedOffMenuBarBand(among: [control, collateral], screens: screens))
    }
}
