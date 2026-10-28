//
//  MultiBarFramesTests.swift
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
@Suite("Frames stated against several bars")
struct MultiBarFramesTests {
    /// Two side-by-side 1920 pt displays, as on the machine the bug was seen on.
    private static let displays = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 1920, y: 0, width: 1920, height: 1080),
    ]

    private static func item(x: CGFloat, y: CGFloat = 3.5, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.app\(windowID)"), title: "Item-0", instanceIndex: 0),
            windowID: windowID,
            ownerPID: pid_t(windowID),
            sourcePID: pid_t(windowID),
            bounds: CGRect(x: x, y: y, width: 24, height: 24),
            title: "Item-0",
            isOnScreen: true
        )
    }

    @Test("One item stated against the second bar is detected")
    func mixedBarsAreDetected() {
        let items = [Self.item(x: 1338, windowID: 1), Self.item(x: 1716, windowID: 2), Self.item(x: 3209, windowID: 3)]
        #expect(ControlOrderRules.framesSpanSeveralBars(items, displays: Self.displays))
    }

    @Test("Items all on one bar are not")
    func singleBarIsNotMixed() {
        let items = [Self.item(x: 3209, windowID: 1), Self.item(x: 3378, windowID: 2)]
        #expect(!ControlOrderRules.framesSpanSeveralBars(items, displays: Self.displays))
    }

    @Test("Concealed snapshots on an old display do not block visible-order persistence")
    func concealedSnapshotsDoNotBlockMirroring() {
        let key = "MenuBarItemManager.savedSectionOrder"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let visible = [Self.item(x: 3209, windowID: 1), Self.item(x: 3378, windowID: 2)]
        let hidden = Self.item(x: 1338, windowID: 3)
        let alwaysHidden = Self.item(x: 1400, windowID: 4)
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = visible
        cache[.hidden] = [hidden]
        cache[.alwaysHidden] = [alwaysHidden]
        let manager = MenuBarItemManager()
        let visibleKey = MenuBarSectionName.visible.rawValue
        manager.savedSectionOrder = [visibleKey: visible.reversed().map(\.uniqueIdentifier)]

        manager.mirrorSavedSectionOrderIfSettled(from: cache, displays: Self.displays)

        #expect(manager.savedSectionOrder[visibleKey] == visible.map(\.uniqueIdentifier))
        #expect(manager.savedSectionOrder[MenuBarSectionName.hidden.rawValue] == [hidden.uniqueIdentifier])
        #expect(manager.savedSectionOrder[MenuBarSectionName.alwaysHidden.rawValue] == [alwaysHidden.uniqueIdentifier])
        #expect(UserDefaults.standard.dictionary(forKey: key)?[visibleKey] as? [String] == visible.map(\.uniqueIdentifier))
    }

    @Test("Live visible items on different bars still leave the saved order untouched")
    func mixedVisibleFramesDoNotOverwriteSavedOrder() {
        let key = "MenuBarItemManager.savedSectionOrder"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let visible = [Self.item(x: 1338, windowID: 1), Self.item(x: 3209, windowID: 2)]
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = visible
        let manager = MenuBarItemManager()
        let saved = [MenuBarSectionName.visible.rawValue: visible.reversed().map(\.uniqueIdentifier)]
        manager.savedSectionOrder = saved
        UserDefaults.standard.set(saved, forKey: key)

        manager.mirrorSavedSectionOrderIfSettled(from: cache, displays: Self.displays)

        #expect(manager.savedSectionOrder == saved)
        #expect(UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] == saved)
    }

    @Test("Parked and off-band frames do not count as another bar")
    func parkedFramesAreIgnored() {
        let items = [
            Self.item(x: 3209, windowID: 1),
            Self.item(x: -1, y: 1068, windowID: 2),
            Self.item(x: 7, y: 1068, windowID: 3),
        ]
        #expect(!ControlOrderRules.framesSpanSeveralBars(items, displays: Self.displays))
    }

    @Test("A parked Hidden divider leaves the saved order untouched")
    func parkedDividerDoesNotOverwriteSavedOrder() {
        let key = "MenuBarItemManager.savedSectionOrder"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let visible = [Self.item(x: 3209, windowID: 1), Self.item(x: 3378, windowID: 2)]
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = visible
        let parked = MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 9,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: 3100, y: 113.5, width: 2, height: 24),
            title: ControlItemIdentifier.hidden.rawValue,
            isOnScreen: true
        )
        let manager = MenuBarItemManager()
        let saved = [MenuBarSectionName.visible.rawValue: visible.reversed().map(\.uniqueIdentifier)]
        manager.savedSectionOrder = saved

        manager.mirrorSavedSectionOrderIfSettled(
            from: cache,
            controlItems: ControlItemPair(hidden: parked, alwaysHidden: nil),
            displays: Self.displays
        )

        #expect(manager.savedSectionOrder == saved)
    }

    @Test("A Hidden divider parked off the bar blocks order writes")
    func parkedDividerIsOffTheBar() {
        func divider(y: CGFloat) -> MenuBarItem {
            MenuBarItem(
                tag: .hiddenControlItem,
                windowID: 9,
                ownerPID: 501,
                sourcePID: 501,
                bounds: CGRect(x: -570.5, y: y, width: 2, height: 24),
                title: ControlItemIdentifier.hidden.rawValue,
                isOnScreen: true
            )
        }
        // Frames from a reconnect: the dividers parked at y 113.5 while Stats
        // still read on the bar, so Stats looked stranded among hidden items.
        let stats = Self.item(x: -400, windowID: 1)
        let displays = [CGRect(x: -1920, y: 0, width: 1920, height: 1080)]

        let parked = divider(y: 113.5)
        #expect(ControlOrderRules.dividerIsOffTheBar(ControlItemPair(hidden: parked, alwaysHidden: nil), among: [parked, stats], displays: displays))
        let onBar = divider(y: 4.5)
        #expect(!ControlOrderRules.dividerIsOffTheBar(ControlItemPair(hidden: onBar, alwaysHidden: nil), among: [onBar, stats], displays: displays))
    }

    @Test("A stand-in Hidden divider is not taken for one parked off the bar")
    func standInDividerIsNotOffTheBar() {
        let stats = Self.item(x: 3209, windowID: 1)
        let standIns = CacheDividers.standIns(leadingX: 1920, alwaysHiddenEnabled: true, ownerPID: 501)
        #expect(!ControlOrderRules.dividerIsOffTheBar(standIns, among: [stats], displays: Self.displays))
    }

    @Test("A real Hidden divider at x -1 or with an empty frame is still refused")
    func realParkedDividerIsStillRefused() {
        func divider(_ bounds: CGRect) -> ControlItemPair {
            let hidden = MenuBarItem(
                tag: .hiddenControlItem,
                windowID: 9,
                ownerPID: 501,
                sourcePID: 501,
                bounds: bounds,
                title: ControlItemIdentifier.hidden.rawValue,
                isOnScreen: false
            )
            return ControlItemPair(hidden: hidden, alwaysHidden: nil)
        }
        let stats = Self.item(x: 3209, windowID: 1)
        let atMinusOne = divider(CGRect(x: -1, y: 4.5, width: 2, height: 24))
        let empty = divider(CGRect(x: 1920, y: 0, width: 0, height: 0))
        #expect(ControlOrderRules.dividerIsOffTheBar(atMinusOne, among: [stats], displays: Self.displays))
        #expect(ControlOrderRules.dividerIsOffTheBar(empty, among: [stats], displays: Self.displays))
    }

    private static func hiddenDivider(x: CGFloat) -> ControlItemPair {
        let hidden = MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 9,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 4.5, width: 2, height: 24),
            title: ControlItemIdentifier.hidden.rawValue,
            isOnScreen: true
        )
        return ControlItemPair(hidden: hidden, alwaysHidden: nil)
    }

    private static func anchored(_ title: String, x: CGFloat, width: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: title),
            windowID: 20,
            ownerPID: 400,
            sourcePID: 400,
            bounds: CGRect(x: x, y: 3.5, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A Hidden divider read after the Clock, as after a display change, is caught")
    func dividerAfterClock() {
        let items = [Self.item(x: 1398, windowID: 1), Self.anchored("com.apple.menuextra.controlcenter", x: 1929, width: 26),
                     Self.anchored("com.apple.menuextra.clock", x: 1971, width: 56)]
        #expect(ControlOrderRules.dividerIsRightOfTrailingAnchors(Self.hiddenDivider(x: 2046.5), among: items, displays: Self.displays))
        #expect(ControlOrderRules.dividerMisplacement(Self.hiddenDivider(x: 2046.5), among: items, displays: Self.displays) != nil)
        #expect(ControlOrderRules.dividerMisplacement(Self.hiddenDivider(x: 1350), among: items, displays: Self.displays) == nil)
    }

    @Test("A Hidden divider left of the visible items is not")
    func dividerInPlace() {
        let items = [Self.item(x: 1398, windowID: 1), Self.anchored("com.apple.menuextra.clock", x: 1840, width: 56)]
        #expect(!ControlOrderRules.dividerIsRightOfTrailingAnchors(Self.hiddenDivider(x: 1350), among: items, displays: Self.displays))
    }

    @Test("A Clock on another display's bar says nothing about this divider")
    func clockOnOtherBar() {
        let items = [Self.anchored("com.apple.menuextra.clock", x: 1500, width: 56)]
        #expect(!ControlOrderRules.dividerIsRightOfTrailingAnchors(Self.hiddenDivider(x: 3800), among: items, displays: Self.displays))
    }
}
