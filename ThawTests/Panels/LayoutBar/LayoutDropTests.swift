//
//  LayoutDropTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
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

@MainActor
struct LayoutBarDropMarkerTests {
    /// Three 24-point icons, 6 points apart.
    private let frames = [0, 30, 60].map { CGRect(x: CGFloat($0), y: 0, width: 24, height: 24) }

    /// The three icons as slots; nil marks one that is not an item, such as an opaque slot or a collapsed group.
    private func slots(_ itemIndices: [Int?], holdingItems: [Bool]? = nil) -> [LayoutBarDropMarker.Slot] {
        zip(frames, itemIndices).enumerated().map { offset, pair in
            LayoutBarDropMarker.Slot(
                frame: pair.0,
                itemIndex: pair.1,
                holdsItems: holdingItems?[offset] ?? (pair.1 != nil)
            )
        }
    }

    @Test("A dragged item's marker sits in the middle of the gap it holds open")
    func gapMarker() {
        #expect(LayoutBarDropMarker.x(inGap: [frames[1]]) == 42)
        #expect(LayoutBarDropMarker.x(inGap: [frames[0], frames[1]]) == 27)
        #expect(LayoutBarDropMarker.x(inGap: []) == nil)
    }

    @Test("A group lands before the nearest icon, or after it past its middle", arguments: [
        (x: CGFloat(-10), index: 0),
        (x: CGFloat(10), index: 0),
        (x: CGFloat(14), index: 1),
        (x: CGFloat(40), index: 1),
        (x: CGFloat(44), index: 2),
        (x: CGFloat(200), index: 3),
    ])
    func groupDestination(x: CGFloat, index: Int) {
        let destination = LayoutBarDropMarker.groupDestination(forX: x, among: slots([0, 1, 2]), itemCount: 3)
        #expect(destination == .init(itemIndex: index, boundary: index))
    }

    @Test("A slot that is not an item is skipped in the item list but not on the bar")
    func groupDestinationCountsItemsOnly() {
        let destination = LayoutBarDropMarker.groupDestination(forX: 70, among: slots([nil, 0, 1]), itemCount: 2)
        #expect(destination == .init(itemIndex: 1, boundary: 2))
    }

    @Test("A group dropped nearest a slot that is not an item goes to the end of the items, and is marked there")
    func groupDestinationFallsBackToTheEnd() {
        // Nearest the opaque slot in the middle: the marker is after the last item, not beside the slot.
        let middle = LayoutBarDropMarker.groupDestination(forX: 40, among: slots([0, nil, 1]), itemCount: 2)
        #expect(middle == .init(itemIndex: 2, boundary: 3))

        // A trailing opaque slot holds no items, so the end of the items is the boundary before it.
        let trailing = LayoutBarDropMarker.groupDestination(forX: 10, among: slots([nil, 0, nil]), itemCount: 1)
        #expect(trailing == .init(itemIndex: 1, boundary: 2))

        // A collapsed group is not an item, but its members are in the list, so the end is after it.
        let collapsed = LayoutBarDropMarker.groupDestination(
            forX: 70,
            among: slots([0, 1, nil], holdingItems: [true, true, true]),
            itemCount: 4
        )
        #expect(collapsed == .init(itemIndex: 4, boundary: 3))

        let empty = LayoutBarDropMarker.groupDestination(forX: 0, among: [], itemCount: 0)
        #expect(empty == .init(itemIndex: 0, boundary: 0))
    }

    @Test("A group's marker sits on the boundary it is inserted at", arguments: [
        (index: 0, x: CGFloat(0)),
        (index: 1, x: CGFloat(27)),
        (index: 2, x: CGFloat(57)),
        (index: 3, x: CGFloat(84)),
        (index: 9, x: CGFloat(84)),
    ])
    func boundaryMarker(index: Int, x: CGFloat) {
        #expect(LayoutBarDropMarker.x(insertingAt: index, among: frames) == x)
    }

    @Test("The marker stays whole at either end of the bar")
    func markerStaysInside() {
        let bounds = CGRect(x: 0, y: 0, width: 84, height: 28)
        #expect(LayoutBarDropMarker.rect(atX: 0, in: bounds).minX == 0)
        #expect(LayoutBarDropMarker.rect(atX: 84, in: bounds).maxX == 84)
        #expect(LayoutBarDropMarker.rect(atX: 42, in: bounds) == CGRect(x: 41, y: 2, width: 2, height: 24))
    }
}

/// A failed single-item drop was only logged, so the item drifted back with no explanation.
@MainActor
@Suite("Reorder drop outcome", .serialized, .scratchDefaults)
struct ReorderDropOutcomeTests {
    private func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: CGWindowID(x), ownerPID: 42, sourcePID: 42,
            bounds: CGRect(x: x, y: 0, width: 20, height: 22), title: title, isOnScreen: true
        )
    }

    @Test("An item beside its target on the drop's side landed; anywhere else it didn't")
    func landedFollowsTheDropSide() {
        let first = item("A", x: 100), second = item("B", x: 130), third = item("C", x: 160)
        #expect(ReorderDropOutcome.landed(second, at: .rightOfItem(first), in: [third, second, first]) == true)
        #expect(ReorderDropOutcome.landed(second, at: .leftOfItem(third), in: [first, second, third]) == true)
        #expect(ReorderDropOutcome.landed(first, at: .rightOfItem(third), in: [first, second, third]) == false)
    }

    @Test("A read that misses the item or its target can't tell, so it raises nothing")
    func unknownWhenMissing() {
        let first = item("A", x: 100), second = item("B", x: 130)
        #expect(ReorderDropOutcome.landed(second, at: .rightOfItem(first), in: [first]) == nil)
        #expect(ReorderDropOutcome.landed(second, at: .rightOfItem(first), in: [second]) == nil)
    }

    @Test("The notice names the item and says macOS put it back")
    func messageNamesTheItem() {
        let refusal = ReorderDropOutcome.missedDrop(itemName: "Clock")
        #expect(refusal.title.contains("Clock"))
        #expect(refusal.message == "macOS put it back.")
    }

    @Test("A failed move posts the notice only when a fresh read shows the item elsewhere")
    func reportsOnlyAMiss() async {
        let appState = AppState()
        let first = item("A", x: 100), second = item("B", x: 130), third = item("C", x: 160)
        let log = DiagLog(category: "ReorderDropOutcomeTests")

        await ReorderDropOutcome.reportFailure(of: second, to: .rightOfItem(first), appState: appState, log: log) { _ in
            [first, second, third]
        }
        #expect(appState.layoutFeedback.refusal == nil, "it landed after all")

        await ReorderDropOutcome.reportFailure(of: second, to: .rightOfItem(first), appState: appState, log: log) { _ in nil }
        #expect(appState.layoutFeedback.refusal == nil, "no read, no claim")

        await ReorderDropOutcome.reportFailure(of: first, to: .rightOfItem(third), appState: appState, log: log) { _ in
            [first, second, third]
        }
        #expect(appState.layoutFeedback.refusal?.message == "macOS put it back.")
        appState.layoutFeedback.clear()
    }
}

@Suite("Move result message")
struct MoveResultMessageTests {
    @Test("A move that landed says where the item went")
    func landed() {
        let message = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: true, landed: true)
        #expect(message == MoveResultMessage(symbol: "checkmark", text: "Moved Slack to Hidden"))
    }

    @Test("A move that didn't hold says so")
    func didNotStay() {
        let message = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: true, landed: false)
        #expect(message.text == "Slack didn’t stay in Hidden")
        #expect(message.symbol == "exclamationmark.triangle")
    }

    @Test("A move that was never made says it couldn't move", arguments: [true, false])
    func notCommitted(landed: Bool) {
        let message = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: false, landed: landed)
        #expect(message.text == "Couldn’t move Slack")
    }

    /// Search showed a failed move as briefly as a success, and VoiceOver heard neither.
    @Test("A failure stays up longer than a success and becomes a Layout notice")
    func failureStandsOut() {
        let success = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: true, landed: true)
        let failure = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: false, landed: false)
        let drifted = MoveResultMessage.make(itemName: "Slack", sectionTitle: "Hidden", committed: true, landed: false)
        #expect(!success.isFailure && failure.isFailure && drifted.isFailure)
        #expect(failure.displayDuration > success.displayDuration)
        #expect(success.refusal == nil)
        let refusal = failure.refusal
        #expect(refusal?.title == failure.text)
        #expect(refusal?.isAboutSystemItems == false)
        #expect(failure.refusal?.message != drifted.refusal?.message, "a move never made isn't one macOS undid")
    }
}
