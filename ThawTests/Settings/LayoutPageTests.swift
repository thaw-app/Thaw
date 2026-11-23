//
//  LayoutPageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import MenuBarModel
import SwiftUI
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

/// The line about macOS keeping system items showed above every refusal, including an unresponsive app.
@MainActor
@Suite("Layout refusal notice", .serialized, .scratchDefaults)
struct LayoutRefusalNoticeTests {
    private func height(for refusal: LayoutBarFeedbackCenter.Refusal?, appState: AppState) -> CGFloat {
        appState.layoutFeedback.clear()
        if let refusal {
            appState.layoutFeedback.post(refusal)
        }
        let host = NSHostingView(rootView: LayoutRefusalNotice().environment(appState).frame(width: 480))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("The system-items line shows only for refusals about system items")
    func systemLineOnlyWhenItApplies() {
        let appState = AppState()
        let system = height(for: LayoutBarFeedbackCenter.itemCannotMove(itemName: "Clock", section: .hidden), appState: appState)
        let other = height(for: LayoutBarFeedbackCenter.ownerUnresponsive(itemName: "Stuck"), appState: appState)
        let none = height(for: nil, appState: appState)
        #expect(system > other)
        #expect(other > none)
        appState.layoutFeedback.clear()
    }
}

/// Keeps the Layout pane and Simple Mode off a spinner that never resolves. The overlay's
/// deadline is armed by the preload's timeout, so a path that skips the preload must arm it itself.
@MainActor
@Suite("Layout bars loading plan")
struct LayoutBarsLoadingPlanTests {
    @Test("Without items, a denied grant resolves at once and a granted one preloads; with items nothing loads", arguments: [
        (false, false, LayoutBarsLoading.PreloadPlan.resolveWithoutLoading, true),
        (false, true, .preload, false),
        (true, false, .nothingToLoad, false),
        (true, true, .nothingToLoad, false),
    ])
    func plan(hasItems: Bool, hasScreenRecording: Bool, expected: LayoutBarsLoading.PreloadPlan, armsDeadline: Bool) {
        let plan = LayoutBarsLoading.preloadPlan(hasItems: hasItems, hasScreenRecordingPermission: hasScreenRecording)
        #expect(plan == expected)
        #expect(plan.armsDeadlineImmediately == armsDeadline)
    }
}

@Suite("Group drop target")
struct GroupDropTargetTests {
    private let group = UUID()
    private let other = UUID()

    @Test("A row that gains the pointer becomes the target, whatever was before")
    func gainingThePointer() {
        #expect(GroupDropTarget.after(true, on: group, current: nil) == group)
        #expect(GroupDropTarget.after(true, on: group, current: other) == group)
    }

    @Test("A row that loses the pointer clears the target only if it was the target")
    func losingThePointer() {
        #expect(GroupDropTarget.after(false, on: group, current: group) == nil)
        // Another row took over in the meantime.
        #expect(GroupDropTarget.after(false, on: group, current: other) == other)
        #expect(GroupDropTarget.after(false, on: group, current: nil) == nil)
    }
}
