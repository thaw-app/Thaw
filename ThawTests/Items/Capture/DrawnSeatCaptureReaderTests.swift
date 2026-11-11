//
//  DrawnSeatCaptureReaderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw
import ThawAXCore
import ThawCapture

/// Pins the frame a capture's re-read gives an item cropped where MenuBarAgent draws it.
@Suite("Drawn seat capture reader")
struct DrawnSeatCaptureReaderTests {
    private static let driveDx: pid_t = 1096
    private static let windowManager: pid_t = 964

    /// DriveDx reported at x=926 while drawn at x=908, with Window Manager drawn at x=926.
    private static let axFrame = CGRect(x: 926, y: 4.5, width: 20, height: 24)
    private static let seat = CGRect(x: 907, y: 4.5, width: 20, height: 24)

    /// A read that finds an item only when asked at its Accessibility frame, as the geometry
    /// catalog matches items, and finds it there.
    private struct AccessibilityReader: MenuBarCaptureReading {
        func captureBand(displayID _: CGDirectDisplayID) async -> (frame: CGRect, menuMaxX: CGFloat?) {
            (.zero, nil)
        }

        func displayBounds() -> [CGRect] {
            []
        }

        func overflowBounds(displayID _: CGDirectDisplayID) async -> [CGRect] {
            []
        }

        func hostingCapture(displayID _: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
            nil
        }

        func barWindowCapture(ownerPID _: pid_t, displayID _: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
            nil
        }

        func displayStripCapture(displayID _: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
            nil
        }

        func menuBarItems(displayID _: CGDirectDisplayID) async -> [MenuBarItem] {
            []
        }

        func liveBounds(
            for candidates: [(item: MenuBarItem, bounds: CGRect)]
        ) async -> (bounds: [String: CGRect], ambiguous: Set<String>) {
            let found = candidates.filter { $0.bounds == $0.item.bounds }.map { ($0.item.uniqueIdentifier, $0.bounds) }
            return (Dictionary(found, uniquingKeysWith: { first, _ in first }), [])
        }
    }

    private static func item(_ title: String, owner: pid_t, bounds: CGRect) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.seat"), title: title, instanceIndex: 0),
            windowID: 12,
            ownerPID: owner,
            sourcePID: owner,
            bounds: bounds,
            title: title,
            isOnScreen: true
        )
    }

    private static func entry(_ pid: pid_t, x: CGFloat, width: CGFloat) -> MenuBarAgentWindow.Entry {
        MenuBarAgentWindow.Entry(ownerPID: pid, frame: CGRect(x: x, y: 0, width: width, height: 33))
    }

    private static func reread(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        for item: MenuBarItem,
        bar: [MenuBarAgentWindow.Entry]?
    ) async -> [String: CGRect] {
        let reader = DrawnSeatCaptureReader(base: AccessibilityReader(), item: item, drawnBar: { bar })
        return await reader.liveBounds(for: candidates).bounds
    }

    @Test("An item still drawn where it was cropped is re-read on that seat")
    func seatHeld() async {
        let item = Self.item("DriveDx", owner: Self.driveDx, bounds: Self.axFrame)
        let bar = [Self.entry(Self.driveDx, x: 908, width: 18), Self.entry(Self.windowManager, x: 926, width: 24)]

        let bounds = await Self.reread([(item, Self.seat)], for: item, bar: bar)

        #expect(bounds[item.uniqueIdentifier] == Self.seat)
    }

    @Test("An item drawn somewhere else by now is re-read there, so the crop counts as moved")
    func seatMoved() async {
        let item = Self.item("DriveDx", owner: Self.driveDx, bounds: Self.axFrame)
        let bar = [Self.entry(Self.driveDx, x: 880, width: 18), Self.entry(Self.windowManager, x: 926, width: 24)]

        let bounds = await Self.reread([(item, Self.seat)], for: item, bar: bar)

        #expect(bounds[item.uniqueIdentifier] == CGRect(x: 879, y: 4.5, width: 20, height: 24))
    }

    @Test("An item no longer drawn, whose frame sits on another app's item, has no frame")
    func seatGone() async {
        let item = Self.item("DriveDx", owner: Self.driveDx, bounds: Self.axFrame)
        let bar = [Self.entry(Self.windowManager, x: 926, width: 24)]

        let bounds = await Self.reread([(item, Self.seat)], for: item, bar: bar)

        #expect(bounds[item.uniqueIdentifier] == nil)
    }

    @Test("Other items are re-read as the base reads them")
    func otherItemsUnchanged() async {
        let item = Self.item("DriveDx", owner: Self.driveDx, bounds: Self.axFrame)
        let other = Self.item("Other", owner: 777, bounds: CGRect(x: 1000, y: 4.5, width: 22, height: 24))
        let bar = [Self.entry(Self.driveDx, x: 908, width: 18)]

        let bounds = await Self.reread([(item, Self.seat), (other, other.bounds)], for: item, bar: bar)

        #expect(bounds[other.uniqueIdentifier] == other.bounds)
    }
}
