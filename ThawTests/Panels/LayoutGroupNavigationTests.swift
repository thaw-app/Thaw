//
//  LayoutGroupNavigationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// A drag as a group row's drop view sees it.
@MainActor
private final class GroupRowDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    init(pasteboard: NSPasteboard) {
        draggingPasteboard = pasteboard
    }

    var draggingSource: Any? {
        nil
    }

    var draggingLocation: NSPoint {
        .zero
    }

    var draggingDestinationWindow: NSWindow? {
        nil
    }

    var draggingSourceOperationMask: NSDragOperation {
        .move
    }

    var draggedImageLocation: NSPoint {
        .zero
    }

    var draggedImage: NSImage? {
        nil
    }

    var draggingSequenceNumber: Int {
        1
    }

    var springLoadingHighlight: NSSpringLoadingHighlight {
        .none
    }

    func slideDraggedImage(to _: NSPoint) { /* The drop view never slides the image. */ }

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [],
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) { /* The drop view reads the pasteboard, not the dragging items. */ }

    func resetSpringLoading() { /* Not spring-loaded. */ }
}

/// The Groups tab as a navigator: selecting a group's members, and taking items dropped on a group's row.
@MainActor
@Suite("Layout group navigation", .serialized, .scratchDefaults)
struct LayoutGroupNavigationTests {
    private typealias World = LayoutEditorWorld

    @MainActor
    private struct Fixture {
        let world = World()
        let alpha = World.item("Alpha"), beta = World.item("Beta"), gamma = World.item("Gamma")
        let stray = World.item("Stray")
        let selection = LayoutSelectionModel { _ in }

        init() {
            world.seat([alpha, beta, gamma])
            world.seat([stray], in: .hidden)
            show([alpha, beta, gamma], in: .visible)
            show([stray], in: .hidden)
        }

        /// Reports the items to the selection as the bars would, one unit each.
        func show(_ items: [MenuBarItem], in section: MenuBarSectionName) {
            selection.update(items.map { .init(memberIDs: [$0.uniqueIdentifier], isSelectable: true) }, in: section)
        }

        var navigation: LayoutGroupNavigation {
            LayoutGroupNavigation(selection: selection, appState: world.appState)
        }

        func duo() throws -> MenuBarItemGroup {
            try #require(world.appState.itemGroupManager.createGroup(name: "Duo", items: [alpha, beta]))
        }
    }

    @Test("Selecting a group selects its members, and only that selection counts as the group's")
    func selectsMembers() throws {
        let fixture = Fixture()
        let duo = try fixture.duo()
        let navigation = fixture.navigation
        #expect(!navigation.isSelected(duo), "nothing is selected yet")

        navigation.select(duo)
        #expect(fixture.selection.orderedItemIDs == [fixture.alpha, fixture.beta].map(\.uniqueIdentifier))
        #expect(navigation.isSelected(duo))

        fixture.selection.select([fixture.alpha.uniqueIdentifier])
        #expect(!navigation.isSelected(duo), "one member is not the group")

        fixture.selection.select([fixture.alpha, fixture.beta, fixture.gamma].map(\.uniqueIdentifier))
        #expect(!navigation.isSelected(duo), "an outsider in the selection is not the group")
    }

    @Test("A group counts as selected by the members the bars show")
    func hiddenMemberDoesNotBlockSelection() throws {
        let fixture = Fixture()
        let duo = try fixture.duo()
        // Beta's app quit: the bars no longer show it, and the group still lists it.
        fixture.show([fixture.alpha, fixture.gamma], in: .visible)

        fixture.navigation.select(duo)
        #expect(fixture.selection.orderedItemIDs == [fixture.alpha.uniqueIdentifier])
        #expect(fixture.navigation.isSelected(duo))
    }

    @Test("Items dropped on a group in its own section join it")
    func addJoins() throws {
        let fixture = Fixture()
        let duo = try fixture.duo()

        #expect(fixture.navigation.add([fixture.gamma.uniqueIdentifier], to: duo))
        let members = try #require(fixture.world.appState.itemGroupManager.groupSet.groups.first?.memberIdentifiers)
        #expect(members.contains(fixture.gamma.uniqueIdentifier))
        #expect(fixture.world.appState.layoutFeedback.refusal == nil)
    }

    @Test("The notice for a drop from another section names the group and its section")
    func refusalNotice() {
        let refusal = LayoutGroupNavigation.refusal(section: .hidden, groupName: "Duo")
        #expect(refusal.title.contains(MenuBarSectionName.hidden.localizedName))
        #expect(refusal.title.contains("Duo"))
        #expect(refusal.message.contains(MenuBarSectionName.hidden.localizedName))
    }

    @Test("Dropping a member again adds nothing and says nothing")
    func addMemberChangesNothing() throws {
        let fixture = Fixture()
        let duo = try fixture.duo()

        #expect(!fixture.navigation.add([fixture.alpha.uniqueIdentifier], to: duo))
        #expect(fixture.world.appState.layoutFeedback.refusal == nil)
    }

    @Test("A group row lights up while a drag is over it and never takes the click")
    func dropViewTargeting() {
        let view = LayoutGroupDropTarget.DropView()
        var targeted = [Bool]()
        view.setTargeted = { targeted.append($0) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LayoutGroupNavigationTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let drag = GroupRowDrag(pasteboard: pasteboard)

        #expect(view.draggingEntered(drag) == .move)
        #expect(view.draggingUpdated(drag) == .move)
        view.draggingExited(drag)
        #expect(targeted == [true, false])
        #expect(view.hitTest(.zero) == nil, "clicks go to the row's own controls")
    }

    @Test("A drop hands over the dragged IDs and is not reported as a move")
    func dropViewPerforms() {
        let fixture = Fixture()
        let view = LayoutGroupDropTarget.DropView()
        var targeted = [Bool]()
        var dropped = [[String]]()
        view.setTargeted = { targeted.append($0) }
        view.perform = { dropped.append($0) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LayoutGroupNavigationTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("one\ntwo", forType: .layoutBarSelection)
        let drag = GroupRowDrag(pasteboard: pasteboard)

        #expect(!view.performDragOperation(drag), "without a selection model there is nothing to drop")
        #expect(dropped.isEmpty)

        view.selection = fixture.selection
        #expect(!view.performDragOperation(drag), "the bars put the items back themselves, so this is never a move")
        #expect(dropped == [["one", "two"]])
        #expect(targeted == [false, false])
    }
}
