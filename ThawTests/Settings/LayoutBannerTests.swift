//
//  LayoutBannerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Layout shows one warning at a time, the most serious first", .scratchDefaults)
struct LayoutBannerTests {
    private func banner(
        denied: Bool = false,
        outOfReach: Bool = false,
        outOfRoom: Bool = false,
        recording: Bool = true
    ) -> LayoutBanner? {
        LayoutBanner.mostSerious(
            isDeniedBySystem: denied,
            hasItemsOutOfReach: outOfReach,
            isOutOfRoom: outOfRoom,
            hasScreenRecording: recording
        )
    }

    @Test("Thaw switched off in System Settings outranks everything")
    func deniedComesFirst() {
        #expect(banner(denied: true, outOfReach: true, recording: false) == .deniedBySystem)
    }

    @Test("Items out of reach outrank a missing Screen Recording grant")
    func outOfReachComesSecond() {
        #expect(banner(outOfReach: true, recording: false) == .outOfReach)
    }

    @Test("macOS hiding items for lack of room ranks after items out of reach and before Screen Recording")
    func outOfRoomComesThird() {
        #expect(banner(outOfReach: true, outOfRoom: true) == .outOfReach)
        #expect(banner(outOfRoom: true, recording: false) == .outOfRoom)
        #expect(!LayoutBanner.allowsTips(beside: .outOfRoom))
    }

    @Test("The items macOS is not drawing are named in bar order, each name once")
    func namesNotDrawn() {
        let items = [item("Alpha", windowID: 1), item("Beta", windowID: 2), item("Gamma", windowID: 3), item("Beta", windowID: 4)]
        let tags = Set([items[2].tag, items[1].tag, items[3].tag])
        #expect(LayoutBanner.namesNotDrawn(visibleItems: items, notDrawnTags: tags) == ["Beta", "Gamma"])
        #expect(LayoutBanner.namesNotDrawn(visibleItems: items, notDrawnTags: []).isEmpty)
    }

    @Test("Move to Hidden takes each Visible item macOS is not drawing, in bar order")
    func itemsNotDrawn() {
        let items = [item("Alpha", windowID: 1), item("Beta", windowID: 2), item("Gamma", windowID: 3)]
        let notDrawn = LayoutBanner.itemsNotDrawn(visibleItems: items, notDrawnTags: [items[2].tag, items[0].tag])
        #expect(notDrawn.map(\.tag) == [items[0].tag, items[2].tag])
        #expect(LayoutBanner.itemsNotDrawn(visibleItems: items, notDrawnTags: []).isEmpty)
    }

    private func item(_ title: String, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: Int(windowID)),
            windowID: windowID,
            // No process has these, so the name comes from the namespace.
            ownerPID: 999_999,
            sourcePID: 999_999,
            bounds: CGRect(x: CGFloat(windowID) * 30, y: 3, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A missing Screen Recording grant shows when nothing worse is true")
    func screenRecordingComesLast() {
        #expect(banner(recording: false) == .noScreenRecording)
        #expect(banner() == nil)
    }

    @Test("Tips show beside no warning or the Screen Recording one, and not beside a broken state")
    func tipsStayAwayFromBrokenStates() {
        #expect(LayoutBanner.allowsTips(beside: nil))
        #expect(LayoutBanner.allowsTips(beside: .noScreenRecording))
        #expect(!LayoutBanner.allowsTips(beside: .outOfReach))
        #expect(!LayoutBanner.allowsTips(beside: .deniedBySystem))
    }
}
