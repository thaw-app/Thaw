//
//  MenuBarCaptureReadingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Capture geometry reads pick their owners and fall back to a full walk")
struct MenuBarCaptureReadingTests {
    /// A PID no process uses, so window and AX reads find nothing.
    private static let absentPID: pid_t = 999_998

    private static func item(_ title: String, owner: pid_t, source: pid_t? = nil) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.capture"), title: title, instanceIndex: 0),
            windowID: 12,
            ownerPID: owner,
            sourcePID: source,
            bounds: CGRect(x: 500, y: 0, width: 22, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("No targets means no owners to refresh")
    func noTargetsNoOwners() {
        let owners = MenuBarItemImageCache.captureGeometryOwners(
            for: [],
            knownItems: [Self.item("Known", owner: 5)],
            recentItems: []
        )
        #expect(owners.isEmpty)
    }

    @Test("Owners cover the targets, the known items and the recent items, preferring the source PID")
    func ownersCoverEveryKnownItem() {
        let owners = MenuBarItemImageCache.captureGeometryOwners(
            for: [Self.item("Target", owner: 1, source: 11)],
            knownItems: [Self.item("Known", owner: 2)],
            recentItems: [Self.item("Recent", owner: 3, source: 33), Self.item("Again", owner: 2)]
        )
        #expect(owners == [11, 2, 33])
    }

    @Test("Without owners the geometry read walks every app")
    func emptyOwnersDiscover() async {
        var ownerReads = 0
        let items = await MenuBarItemImageCache.freshCaptureGeometry(
            owners: [],
            readOwners: { _ in
                ownerReads += 1
                return []
            },
            discover: { [Self.item("Walked", owner: 4)] }
        )
        #expect(ownerReads == 0)
        #expect(items.map(\.title) == ["Walked"])
    }

    @Test("A complete owner read is used as is")
    func ownerReadUsed() async {
        var askedFor: Set<pid_t> = []
        var discovered = false
        let items = await MenuBarItemImageCache.freshCaptureGeometry(
            owners: [7, 8],
            readOwners: { owners in
                askedFor = owners
                return [Self.item("Fresh", owner: 7)]
            },
            discover: {
                discovered = true
                return []
            }
        )
        #expect(askedFor == [7, 8])
        #expect(!discovered)
        #expect(items.map(\.title) == ["Fresh"])
    }

    @Test("An incomplete owner read falls back to the full walk")
    func incompleteOwnerReadFallsBack() async {
        let items = await MenuBarItemImageCache.freshCaptureGeometry(
            owners: [7],
            readOwners: { _ in nil },
            discover: { [Self.item("Walked", owner: 9)] }
        )
        #expect(items.map(\.title) == ["Walked"])
    }

    @Test("A process with no windows has no bar window and no bar capture")
    func absentOwnerHasNoBarWindow() async {
        let display = CGDisplayBounds(CGMainDisplayID())
        #expect(MenuBarItemImageCache.barWindow(for: Self.absentPID, displayBounds: display) == nil)
        #expect(MenuBarItemImageCache.barWindow(for: Self.absentPID, displayBounds: .zero) == nil)
        let capture = await MenuBarItemImageCache.barWindowCapture(for: Self.absentPID, displayBounds: display)
        #expect(capture == nil)
    }

    @Test("The live reader has no live bounds for items whose owner is not running")
    func liveBoundsWithoutHosts() async {
        let reader = LiveMenuBarCaptureReader()
        let empty = await reader.liveBounds(for: [])
        #expect(empty.bounds.isEmpty)
        #expect(empty.ambiguous.isEmpty)

        let orphan = Self.item("Orphan", owner: Self.absentPID, source: Self.absentPID)
        let read = await reader.liveBounds(for: [(orphan, orphan.bounds)])
        #expect(read.bounds.isEmpty)
        #expect(read.ambiguous.isEmpty)
    }

    @Test("The live reader's band is the display's frame, and an unknown display has none")
    func captureBand() async {
        let reader = LiveMenuBarCaptureReader()
        let unknown = await reader.captureBand(displayID: 0xDEAD_BEEF)
        #expect(unknown.frame == .zero)
        #expect(unknown.menuMaxX == nil)

        let mainID = CGMainDisplayID()
        let expected = await MainActor.run { NSScreen.screen(for: mainID)?.frame }
        let band = await reader.captureBand(displayID: mainID)
        #expect(band.frame == expected ?? .zero)
        #expect(!reader.displayBounds().isEmpty)
    }

    @Test("The menu bar host's bar window, when it runs, is the widest strip on the display")
    func hostBarWindow() {
        let host = NSRunningApplication.runningApplications(withBundleIdentifier: SharedConstants.menuBarHostingBundleID).first
        guard let pid = host?.processIdentifier else { return }
        let display = CGDisplayBounds(CGMainDisplayID())

        guard let window = MenuBarItemImageCache.barWindow(for: pid, displayBounds: display) else { return }

        #expect(window.windowID != 0)
        #expect(window.frame.width > 0)
        #expect(window.frame.width <= display.width + 1)
    }
}
