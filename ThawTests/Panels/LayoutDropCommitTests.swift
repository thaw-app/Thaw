//
//  LayoutDropCommitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite(.serialized, .scratchDefaults)
struct LayoutDropCommitTests {
    private typealias World = LayoutEditorWorld

    private func drop(
        _ items: [MenuBarItem],
        from source: MenuBarSection.Name,
        to target: MenuBarSection.Name
    ) -> LayoutDropCommit.Drop {
        LayoutDropCommit.Drop(items: items, source: source, target: target, previousTargetOrder: [], targetOrder: items)
    }

    @Test
    func aDropOfNothingIsRefused() {
        let world = World()
        #expect(LayoutDropCommit.refuses(drop([], from: .visible, to: .hidden), appState: world.appState))
        #expect(world.appState.layoutFeedback.refusal == nil)
    }

    @Test(arguments: [MenuBarSection.Name.hidden, .alwaysHidden])
    func theThawIconCannotLeaveVisible(target: MenuBarSection.Name) {
        let world = World()
        let thaw = World.item(.visibleControlItem)

        #expect(LayoutDropCommit.refuses(drop([World.item("Other"), thaw], from: .visible, to: target), appState: world.appState))
        #expect(world.appState.layoutFeedback.refusal?.message.contains(Constants.displayName) == true)
    }

    @Test(arguments: MenuBarSection.Name.allCases)
    func anAppItemReordersInsideItsSection(section: MenuBarSection.Name) {
        let world = World()
        #expect(!LayoutDropCommit.refuses(drop([World.item("App")], from: section, to: section), appState: world.appState))
        #expect(world.appState.layoutFeedback.refusal == nil)
    }

    @Test
    func anItemMacOSKeepsInPlaceCannotBeReorderedInVisible() {
        let world = World()
        let divider = World.item(.hiddenControlItem)

        #expect(LayoutDropCommit.refuses(drop([divider], from: .visible, to: .visible), appState: world.appState))
        let expected = LayoutBarFeedbackCenter.itemNotMovable(itemName: divider.displayName)
        #expect(world.appState.layoutFeedback.refusal?.title == expected.title)
    }

    @Test
    func anAppItemMovesToAnotherSection() {
        let world = World()
        #expect(!LayoutDropCommit.refuses(drop([World.item("App")], from: .visible, to: .hidden), appState: world.appState))
        #expect(world.appState.layoutFeedback.refusal == nil)
    }

    @Test
    func aSingleItemThatCannotBeAssignedIsRefused() {
        let world = World()
        let divider = World.item(.hiddenControlItem)

        #expect(LayoutDropCommit.refuses(drop([divider], from: .visible, to: .hidden), appState: world.appState))
        #expect(world.appState.layoutFeedback.refusal != nil)
    }

    @Test
    func aGroupCrossingSectionsIsLeftToTheAssignment() {
        let world = World()
        let group = [World.item("One"), World.item("Two")]
        #expect(!LayoutDropCommit.refuses(drop(group, from: .visible, to: .hidden), appState: world.appState))
    }

    @Test
    func aSameLaneDropOnlyRecordsOrder() {
        let controller = RecordingSectionController()
        let folded = World.item("Folded")
        let other = World.item("Other")

        LayoutDropCommit.recordIntent(of: folded, orderedAs: [other, folded], from: .hidden, to: .hidden, controller: controller)

        #expect(controller.sectionAssignments.isEmpty)
        #expect(controller.sectionOrderCalls.count == 1)
        #expect(controller.sectionOrderCalls.first?.0 == .hidden)
        #expect(controller.sectionOrderCalls.first?.1 == [other, folded].map(\.uniqueIdentifier))
    }

    @Test
    func aCrossLaneDropReassignsThenRecordsOrder() {
        let controller = RecordingSectionController()
        let item = World.item("Moved")

        LayoutDropCommit.recordIntent(of: item, orderedAs: [item], from: .visible, to: .hidden, controller: controller)

        #expect(controller.sectionAssignments.count == 1)
        #expect(controller.sectionAssignments.first?.0 == .hidden)
        #expect(controller.sectionAssignments.first?.1 == item.uniqueIdentifier)
        #expect(controller.sectionOrderCalls.first?.0 == .hidden)
    }
}
