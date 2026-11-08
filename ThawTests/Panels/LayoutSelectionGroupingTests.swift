//
//  LayoutSelectionGroupingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Grouping several selected items, and the Groups tab selecting and taking items.
@MainActor
@Suite("Layout selection grouping", .serialized, .scratchDefaults)
struct LayoutSelectionGroupingTests {
    private typealias World = LayoutEditorWorld

    @MainActor
    private struct Fixture {
        let world = World()
        let alpha = World.item("Alpha"), beta = World.item("Beta"), gamma = World.item("Gamma"), delta = World.item("Delta")
        let undoManager: UndoManager

        init() {
            undoManager = world.appState.layoutUndo
            undoManager.groupsByEvent = false
            world.seat([alpha, beta, gamma, delta])
        }

        var manager: MenuBarItemGroupManager {
            world.appState.itemGroupManager
        }

        var visible: [MenuBarItem] {
            [alpha, beta, gamma, delta]
        }

        func grouping(_ items: [MenuBarItem], isOneSection: Bool = true) -> LayoutSelectionGrouping {
            LayoutSelectionGrouping(items: items, sectionItems: visible, manager: manager, undoManager: undoManager, isOneSection: isOneSection)
        }

        func record(_ edit: () -> Void) {
            undoManager.beginUndoGrouping()
            edit()
            undoManager.endUndoGrouping()
        }

        func memberIDs() -> [[String]] {
            manager.groupSet.groups.map(\.memberIdentifiers)
        }
    }

    @Test("Group Selected makes one group of the selection, and undo and redo it")
    func groupSelected() {
        let fixture = Fixture()
        fixture.record { fixture.grouping([fixture.alpha, fixture.beta, fixture.gamma]).group() }

        #expect(fixture.memberIDs() == [[fixture.alpha, fixture.beta, fixture.gamma].map(\.uniqueIdentifier)])
        #expect(fixture.undoManager.undoActionName == "Group 3 Items")
        fixture.undoManager.undo()
        #expect(fixture.manager.groupSet.groups.isEmpty)
        fixture.undoManager.redo()
        #expect(fixture.manager.groupSet.groups.count == 1)
    }

    @Test("A selection that is one group already isn't grouped again")
    func alreadyOneGroup() throws {
        let fixture = Fixture()
        try #require(fixture.manager.createGroup(name: "Duo", items: [fixture.alpha, fixture.beta]))
        let grouping = fixture.grouping([fixture.alpha, fixture.beta])

        #expect(grouping.selectedGroup != nil)
        #expect(!grouping.canGroup)
        #expect(grouping.group() == nil)
        #expect(grouping.joinableGroups.isEmpty)
    }

    @Test("Grouping is refused across sections and for a single groupable item")
    func refusals() {
        let fixture = Fixture()
        let spread = fixture.grouping([fixture.alpha, fixture.beta], isOneSection: false)
        #expect(spread.refusal == .severalSections)
        #expect(spread.group() == nil)
        #expect(spread.joinableGroups.isEmpty)

        let single = fixture.grouping([fixture.alpha])
        #expect(single.refusal == .tooFewGroupable)
        #expect(single.group() == nil)
        #expect(fixture.manager.groupSet.groups.isEmpty)
        #expect(LayoutSelectionGrouping.explanation(for: .severalSections) != LayoutSelectionGrouping.explanation(for: .tooFewGroupable))
    }

    @Test("Add to Group puts the selection in an existing group, and undo takes it out")
    func addToGroup() throws {
        let fixture = Fixture()
        let duo = try #require(fixture.manager.createGroup(name: "Duo", items: [fixture.alpha, fixture.beta]))
        let grouping = fixture.grouping([fixture.gamma, fixture.delta])
        let target = try #require(grouping.joinableGroups.first { $0.origin == .user(duo.id) })

        fixture.record { grouping.add(to: target) }

        #expect(fixture.memberIDs() == [fixture.visible.map(\.uniqueIdentifier)])
        #expect(fixture.undoManager.undoActionName == "Add to Duo")
        fixture.undoManager.undo()
        #expect(fixture.memberIDs() == [[fixture.alpha, fixture.beta].map(\.uniqueIdentifier)])
        fixture.undoManager.redo()
        #expect(fixture.memberIDs().first?.count == 4)
    }

    @Test("Make Folder groups the selection in one undo step")
    func makeFolder() {
        let fixture = Fixture()
        // The test world has no folder icons, so the folder half declines, as for a group it can't resolve.
        fixture.record { fixture.grouping([fixture.alpha, fixture.beta]).makeFolder(folders: fixture.world.appState.groupFolders) }

        #expect(fixture.manager.groupSet.groups.count == 1)
        #expect(fixture.undoManager.undoActionName == "Make Folder")
        fixture.undoManager.undo()
        #expect(fixture.manager.groupSet.groups.isEmpty)
        #expect(!fixture.undoManager.canUndo)
    }

    @Test("Make Folder does nothing for a refused selection")
    func makeFolderRefused() {
        let fixture = Fixture()
        fixture.record { fixture.grouping([fixture.alpha, fixture.beta], isOneSection: false).makeFolder(folders: fixture.world.appState.groupFolders) }
        #expect(fixture.manager.groupSet.groups.isEmpty)
    }

    @Test("The batch reveal entry covers the selected items but not Thaw's own")
    func alertRevealIdentifiers() {
        let fixture = Fixture()
        let ids = LayoutSelectionActions.alertRevealIdentifiers(
            [fixture.alpha.uniqueIdentifier, fixture.gamma.uniqueIdentifier, fixture.alpha.uniqueIdentifier],
            items: fixture.visible + [fixture.alpha]
        )
        #expect(ids == [fixture.alpha.tag.tagIdentifier, fixture.gamma.tag.tagIdentifier])
    }

    // MARK: Navigator

    @Test("Selecting a group selects its members the bars show")
    func navigatorSelectsMembers() {
        let model = LayoutSelectionModel { _ in }
        model.update([.init(memberIDs: ["a"], isSelectable: true), .init(memberIDs: ["b", "c"], isSelectable: true), .init(memberIDs: ["d"], isSelectable: true)], in: .visible)
        model.update([.init(memberIDs: ["h"], isSelectable: true)], in: .hidden)
        model.click("d", in: .visible, kind: .replace)

        model.select(["c", "gone"])

        #expect(model.orderedItemIDs == ["b", "c"])
        #expect(model.anchorItemID == "b")
        model.select([])
        #expect(model.orderedItemIDs.isEmpty)
    }

    @Test("Selecting leaves out items that can't be selected")
    func navigatorSkipsLocked() {
        let model = LayoutSelectionModel { _ in }
        model.update([.init(memberIDs: ["a"], isSelectable: false), .init(memberIDs: ["b"], isSelectable: true)], in: .visible)
        model.select(["a", "b"])
        #expect(model.orderedItemIDs == ["b"])
    }

    @Test("Items dropped on a group join it, and undo takes them out")
    func dropAdds() throws {
        let fixture = Fixture()
        let duo = try #require(fixture.manager.createGroup(name: "Duo", items: [fixture.alpha, fixture.beta]))
        var outcome: LayoutGroupNavigation.AddOutcome?
        fixture.record {
            outcome = LayoutGroupNavigation.add(
                [fixture.gamma.uniqueIdentifier],
                to: duo,
                manager: fixture.manager,
                undoManager: fixture.undoManager,
                sectionItems: { $0 == .visible ? fixture.visible : [] }
            )
        }
        #expect(outcome == .added)
        #expect(fixture.memberIDs().first?.contains(fixture.gamma.uniqueIdentifier) == true)
        fixture.undoManager.undo()
        #expect(fixture.memberIDs() == [[fixture.alpha, fixture.beta].map(\.uniqueIdentifier)])
    }

    @Test("A drop from another section is refused and dropping members changes nothing")
    func dropRefused() throws {
        let fixture = Fixture()
        let stray = World.item("Stray")
        let duo = try #require(fixture.manager.createGroup(name: "Duo", items: [fixture.alpha, fixture.beta]))
        let sections: (MenuBarSectionName) -> [MenuBarItem] = { section in
            switch section {
            case .visible: fixture.visible
            case .hidden: [stray]
            default: []
            }
        }

        let refused = LayoutGroupNavigation.add([stray.uniqueIdentifier, fixture.gamma.uniqueIdentifier], to: duo, manager: fixture.manager, undoManager: nil, sectionItems: sections)
        #expect(refused == .refused(.visible))
        let members = LayoutGroupNavigation.add([fixture.alpha.uniqueIdentifier], to: duo, manager: fixture.manager, undoManager: nil, sectionItems: sections)
        #expect(members == .unchanged)
        #expect(fixture.memberIDs() == [[fixture.alpha, fixture.beta].map(\.uniqueIdentifier)])
    }

    @Test("A drop carries the IDs written on it, else the selection")
    func dropPayload() {
        let model = LayoutSelectionModel { _ in }
        model.update([.init(memberIDs: ["a"], isSelectable: true), .init(memberIDs: ["b"], isSelectable: true)], in: .visible)
        model.click("a", in: .visible, kind: .replace)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LayoutSelectionGroupingTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: .layoutBarSelection)
        #expect(LayoutGroupDropTarget.itemIDs(pasteboard: pasteboard, source: nil, selection: model) == ["a"])

        pasteboard.clearContents()
        pasteboard.setString("b\na", forType: .layoutBarSelection)
        #expect(LayoutGroupDropTarget.itemIDs(pasteboard: pasteboard, source: nil, selection: model) == ["b", "a"])
    }

    @Test("Selecting a group from the navigator settles without a loop")
    func navigatorIdle() {
        let model = LayoutSelectionModel { _ in }
        model.update([.init(memberIDs: ["a"], isSelectable: true), .init(memberIDs: ["b"], isSelectable: true)], in: .visible)
        model.select(["a", "b"])
        let settled = model.changeCount
        model.select(["a", "b"])
        model.update([.init(memberIDs: ["a"], isSelectable: true), .init(memberIDs: ["b"], isSelectable: true)], in: .visible)
        #expect(model.changeCount == settled)
    }
}
