//
//  LayoutSelectionModelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct LayoutSelectionModelTests {
    typealias Unit = LayoutSelection.Unit
    typealias Entry = LayoutBatchMoveSnapshot.Entry

    @MainActor
    private final class Spoken {
        var messages = [String]()
    }

    private func model(_ spoken: Spoken = Spoken()) -> LayoutSelectionModel {
        let model = LayoutSelectionModel { spoken.messages.append($0) }
        model.update(LayoutSelectionTests.visible, in: .visible)
        model.update(LayoutSelectionTests.hidden, in: .hidden)
        return model
    }

    private static func entry(_ id: String, assignable: Set<MenuBarSectionName> = Set(MenuBarSectionName.allCases)) -> Entry {
        Entry(id: id, isControlItem: false, groupID: nil, assignableSections: assignable, reordersInVisible: true)
    }

    @Test("Clicks change the selection and VoiceOver hears the count")
    func clicksAreAnnounced() {
        let spoken = Spoken()
        let model = model(spoken)

        model.click("a", in: .visible, kind: .replace)
        model.click("h1", in: .hidden, kind: .toggle)
        model.click("h1", in: .hidden, kind: .toggle)
        model.click("a", in: .visible, kind: .replace)
        model.clear()
        model.clear()

        #expect(model.count == 0)
        #expect(spoken.messages == [
            LayoutSelectionModel.announcement(count: 1),
            LayoutSelectionModel.announcement(count: 2),
            LayoutSelectionModel.announcement(count: 1),
            LayoutSelectionModel.announcement(count: 0),
        ])
        #expect(LayoutSelectionModel.announcement(count: 3).contains("3"))
        #expect(LayoutSelectionModel.announcement(count: 0) != LayoutSelectionModel.announcement(count: 1))
    }

    @Test("A bar that no longer shows a selected item deselects it")
    func updateDropsVanishedItems() {
        let model = model()
        model.click("a", in: .visible, kind: .replace)
        model.click("h1", in: .hidden, kind: .toggle)

        model.update(LayoutSelectionTests.visible, in: .visible)
        #expect(model.count == 2)
        model.update([Unit(memberIDs: ["h2"], isSelectable: true)], in: .hidden)
        #expect(model.contains("a"))
        #expect(!model.contains("h1"))
    }

    @Test("The move is the whole selection in menu bar order")
    func commandCarriesTheSelection() throws {
        let model = model()
        #expect(model.command(to: .hidden, placement: .end) == nil)

        model.click("c", in: .visible, kind: .toggle)
        model.click("h2", in: .hidden, kind: .toggle)
        let command = try #require(model.command(to: .alwaysHidden, placement: .start))
        #expect(command.itemIDs == ["h2", "c"])
        #expect(command.section == .alwaysHidden)
        #expect(command.placement == .start)
        #expect(model.orderedItemIDs == ["h2", "c"])
    }

    @Test("The menu offers only the sections the whole selection can go to")
    func moveTargetsFollowThePlan() {
        let model = model()
        model.click("a", in: .visible, kind: .replace)
        model.click("b", in: .visible, kind: .toggle)
        let snapshot = LayoutBatchMoveSnapshot(sections: [
            .visible: [Self.entry("a"), Self.entry("b", assignable: [.visible, .hidden])],
            .hidden: [Self.entry("h1")],
        ])
        #expect(model.moveTargets(in: snapshot) == [.hidden])

        let withAlwaysHidden = LayoutBatchMoveSnapshot(sections: [
            .visible: [Self.entry("a"), Self.entry("b")],
            .hidden: [],
            .alwaysHidden: [],
        ])
        #expect(model.moveTargets(in: withAlwaysHidden) == [.hidden, .alwaysHidden])
        #expect(LayoutSelectionModel().moveTargets(in: withAlwaysHidden).isEmpty)
    }

    @Test("Moving hands one batch to the mover and clears the selection")
    func moveClearsAndRunsOnce() async {
        let model = model()
        model.click("a", in: .visible, kind: .replace)
        model.click("b", in: .visible, kind: .toggle)
        var commands = [LayoutBatchMove]()

        let outcome = await model.move(to: .hidden, placement: .after("h1")) { command in
            commands.append(command)
            return .refused(.moveRefused)
        }

        #expect(commands == [LayoutBatchMove(itemIDs: ["a", "b"], section: .hidden, placement: .after("h1"))])
        #expect(outcome == .refused(.moveRefused))
        #expect(model.count == 0)
        #expect(await model.move(to: .hidden, placement: .end) { _ in .refused(.moveRefused) } == nil)
    }

    @Test("A refused move names the item that cannot go, or explains the batch")
    func refusalsExplainThemselves() throws {
        let names = ["a": "Alpha"]
        let plan = LayoutBatchMovePlan(itemIDs: ["a"], source: .visible, target: .hidden, previousTargetOrder: [], targetOrder: ["a"])
        #expect(LayoutSelectionModel.refusal(for: .moved(plan), section: .hidden) { names[$0] } == nil)
        #expect(LayoutSelectionModel.refusal(for: .unchanged(plan), section: .hidden) { names[$0] } == nil)

        let named = try #require(LayoutSelectionModel.refusal(for: .refused(.notMovable("a", .hidden)), section: .hidden) { names[$0] })
        #expect(named.title.contains("Alpha"))
        let control = try #require(LayoutSelectionModel.refusal(for: .refused(.controlItem("a")), section: .hidden) { names[$0] })
        #expect(control.title.contains("Alpha"))

        let unnamed = try #require(LayoutSelectionModel.refusal(for: .refused(.notMovable("z", .hidden)), section: .hidden) { names[$0] })
        let general = try #require(LayoutSelectionModel.refusal(for: .refused(.moveRefused), section: .hidden) { names[$0] })
        #expect(unnamed.title == general.title)
        #expect(!general.message.isEmpty)
    }

    @Test("Without a speaker of its own the model announces through VoiceOver")
    func defaultAnnouncementPosts() {
        let model = LayoutSelectionModel()
        model.update(LayoutSelectionTests.visible, in: .visible)
        model.click("a", in: .visible, kind: .replace)
        #expect(model.count == 1)
    }
}
