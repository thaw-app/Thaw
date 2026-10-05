//
//  MultiBarFramesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
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
        #expect(MenuBarItemManager.framesSpanSeveralBars(items, displays: Self.displays))
    }

    @Test("Items all on one bar are not")
    func singleBarIsNotMixed() {
        let items = [Self.item(x: 3209, windowID: 1), Self.item(x: 3378, windowID: 2)]
        #expect(!MenuBarItemManager.framesSpanSeveralBars(items, displays: Self.displays))
    }

    @Test("Parked and off-band frames do not count as another bar")
    func parkedFramesAreIgnored() {
        let items = [
            Self.item(x: 3209, windowID: 1),
            Self.item(x: -1, y: 1068, windowID: 2),
            Self.item(x: 7, y: 1068, windowID: 3),
        ]
        #expect(!MenuBarItemManager.framesSpanSeveralBars(items, displays: Self.displays))
    }
}
