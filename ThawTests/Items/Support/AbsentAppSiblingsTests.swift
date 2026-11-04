//
//  AbsentAppSiblingsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Native hiding keeps an app on the bar while any of its items is placed in Visible, drawn or not,
/// so a drop takes along the app's items Layout can't show.
@Suite("Absent app siblings")
struct AbsentAppSiblingsTests {
    private func item(_ bundle: String, _ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, windowID: 1, instanceIndex: 0),
            windowID: 1,
            ownerPID: 42,
            sourcePID: 42,
            bounds: CGRect(x: 900, y: 0, width: 24, height: 24),
            title: nil,
            isOnScreen: true
        )
    }

    private let droppy = "iordv.Droppy"

    /// The scan as the manager runs it: explicit assignments and recorded orders are the candidates,
    /// and a recorded item with no assignment resolves to Visible, as the section controller does.
    private func siblings(
        of items: [MenuBarItem],
        to target: MenuBarSectionName,
        assignment: [String: MenuBarSectionName],
        recorded: [String] = [],
        live: Set<String>
    ) -> [String] {
        AbsentAppSiblings.identifiers(
            following: items,
            to: target,
            candidates: Array(assignment.keys) + recorded,
            sectionOf: { assignment[$0] ?? .visible },
            liveIdentifiers: live
        )
    }

    @Test("A sibling only recorded in an order, implicitly Visible, follows a move to Hidden")
    func recordedVisibleSiblingFollows() {
        let moved = siblings(
            of: [item(droppy, "DroppyMenuBar")],
            to: .hidden,
            assignment: ["iordv.Droppy:DroppyMenuBar": .hidden],
            recorded: ["iordv.Droppy:Item-0", "iordv.Droppy:DroppyMenuBar"],
            live: ["iordv.Droppy:DroppyMenuBar"]
        )
        #expect(moved == ["iordv.Droppy:Item-0"])
    }

    @Test("An app's items placed elsewhere and not on the bar follow the dropped one")
    func undrawnSiblingsFollow() {
        let dropped = item(droppy, "DroppyMenuBar")
        let moved = siblings(
            of: [dropped],
            to: .hidden,
            assignment: [
                "iordv.Droppy:DroppyMenuBar": .hidden,
                "iordv.Droppy:Item-0": .visible,
                "iordv.Droppy:LiquidPlayerMenuBar": .visible,
                "com.example.Other:Item-0": .visible,
            ],
            live: ["iordv.Droppy:DroppyMenuBar", "com.example.Other:Item-0"]
        )
        #expect(moved == ["iordv.Droppy:Item-0", "iordv.Droppy:LiquidPlayerMenuBar"])
    }

    @Test("A sibling on the bar, one already in the target, and another app's lookalike prefix stay put")
    func onlyAbsentSiblingsOfTheSameAppMove() {
        let moved = siblings(
            of: [item(droppy, "DroppyMenuBar")],
            to: .hidden,
            assignment: [
                "iordv.Droppy:Live": .visible,
                "iordv.Droppy:AlreadyThere": .hidden,
                "iordv.DroppyHelper:Item-0": .visible,
            ],
            live: ["iordv.Droppy:Live"]
        )
        #expect(moved.isEmpty)
    }

    @MainActor
    @Test("Carrying moves an app's absent siblings through the controller and reports them")
    func carryMovesThroughTheController() {
        let controller = RecordingSectionController(order: [.visible: ["iordv.Droppy:Item-0", "com.example.Other:Item-0"]])
        controller.sectionAssignment = ["iordv.Droppy:DroppyMenuBar": .hidden]
        controller.sectionsByIdentifier = [
            "iordv.Droppy:DroppyMenuBar": .hidden,
            "iordv.Droppy:Item-0": .visible,
            "com.example.Other:Item-0": .visible,
        ]

        let moved = AbsentAppSiblings.carry(
            [item(droppy, "DroppyMenuBar")],
            to: .hidden,
            in: controller,
            liveIdentifiers: ["iordv.Droppy:DroppyMenuBar"]
        )

        #expect(moved == ["iordv.Droppy:Item-0"])
        #expect(controller.identifierAssignments.map(\.1) == ["iordv.Droppy:Item-0"])
        #expect(controller.identifierAssignments.allSatisfy { $0.0 == .hidden })
    }

    @MainActor
    @Test("Without Native hiding, a section change only runs its own commit")
    func withoutNativeHidingOnlyTheCommitRuns() {
        let appState = AppState()
        var commits = 0
        appState.itemManager.commitKeepingAppsTogether([item(droppy, "DroppyMenuBar")], to: .hidden) { commits += 1 }
        #expect(commits == 1)
        #expect(!appState.menuBarManager.nativeAppHidingExperiment.isActive)
    }

    @Test("Items that aren't grouped by app, such as Apple's, bring nothing along")
    func systemItemsBringNothing() {
        let moved = siblings(
            of: [item("com.apple.MenuBarAgent", "com.apple.menuextra.wifi")],
            to: .hidden,
            assignment: ["com.apple.MenuBarAgent:com.apple.menuextra.bluetooth": .visible],
            live: []
        )
        #expect(moved.isEmpty)
    }
}
