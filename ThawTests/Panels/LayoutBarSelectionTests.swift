//
//  LayoutBarSelectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw
import ThawUI

/// A drag of the selection as the destination sees it, at a fixed spot in the window.
@MainActor
private final class SelectionDrag: NSObject, NSDraggingInfo {
    let draggingSource: Any?
    let draggingLocation: NSPoint
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    init(source: Any?, location: NSPoint) {
        self.draggingSource = source
        self.draggingLocation = location
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { NSPasteboard(name: NSPasteboard.Name("ThawTests.LayoutSelection")) }
    var draggingSequenceNumber: Int { 1 }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to _: NSPoint) {}

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [],
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}

@MainActor
@Suite(.serialized, .scratchDefaults)
struct LayoutBarSelectionTests {
    private typealias World = LayoutEditorWorld

    /// One Hidden bar in an offscreen window, built from the test's items.
    @MainActor
    private final class Bar {
        let world: World
        let selection: LayoutSelectionModel
        let window: NSWindow
        let scrollView: LayoutBarScrollView
        let container: LayoutBarContainer
        var commands = [LayoutBatchMove]()

        init(_ items: [MenuBarItem], section: MenuBarSection.Name = .visible) throws {
            let world = World()
            world.seat(items, in: section)
            let selection = LayoutSelectionModel { _ in }
            let scrollView = LayoutBarScrollView(appState: world.appState, section: section, selection: selection)
            let frame = CGRect(x: 0, y: 0, width: 600, height: 48)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = scrollView
            scrollView.translatesAutoresizingMaskIntoConstraints = true
            scrollView.frame = frame
            self.world = world
            self.selection = selection
            self.scrollView = scrollView
            self.window = window
            self.container = try #require(scrollView.documentView?.subviews.lazy.compactMap { $0 as? LayoutBarContainer }.first)
            container.rebuildViews()
            container.syncSelection()
            window.layoutIfNeeded()
            selection.makeMover = { _ in
                { [self] command in
                    commands.append(command)
                    return .refused(.moveRefused)
                }
            }
        }

        func view(_ item: MenuBarItem) throws -> LayoutBarItemView {
            try #require(scrollView.arrangedViews.lazy.compactMap { $0 as? LayoutBarItemView }.first { $0.item.tag == item.tag })
        }

        func point(on view: NSView) -> NSPoint {
            view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        }

        func mouse(_ type: NSEvent.EventType, at location: NSPoint, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }

        /// Sends a press and release through the bar's selection input; true when the release went on to the item.
        func click(_ view: NSView, flags: NSEvent.ModifierFlags = []) throws -> Bool {
            let interaction = try #require(scrollView.selectionInteraction)
            let location = point(on: view)
            _ = interaction.handle(try mouse(.leftMouseDown, at: location, flags: flags))
            return interaction.handle(try mouse(.leftMouseUp, at: location, flags: flags)) != nil
        }

        func settle() async {
            for _ in 0 ..< 5 {
                await Task.yield()
            }
        }
    }

    private static func pair() -> [MenuBarItem] {
        ["One", "Two"].map {
            World.item(MenuBarItemTag(namespace: .string("com.example.Pair"), title: $0, instanceIndex: 0))
        }
    }

    @Test("Section names use existing catalog translations in menus and VoiceOver", arguments: [
        (MenuBarSectionName.visible, "Visible"),
        (.hidden, "Hidden"),
        (.alwaysHidden, "Always-Hidden"),
    ])
    func sectionNamesUseCatalogTranslations(section: MenuBarSectionName, key: String) {
        let expected = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        #expect(section.localizedName == expected)
        #expect(LayoutSelectionHighlight.accessibilityValue(section: section, isSelected: false) == expected)

        let selectedFormat = Bundle.main.localizedString(forKey: "%@, selected", value: nil, table: nil)
        #expect(LayoutSelectionHighlight.accessibilityValue(section: section, isSelected: true) == String(format: selectedFormat, expected))
    }

    @Test("The bar lists its items as units, a bundle's items as one, and its control item as unselectable")
    func unitsFollowTheBar() throws {
        let alpha = World.item("Alpha")
        let pair = Self.pair()
        let bar = try Bar([alpha] + pair + [World.item(.visibleControlItem)], section: .visible)

        let units = bar.container.selectionUnits()
        #expect(units.first == LayoutSelection.Unit(memberIDs: [alpha.uniqueIdentifier], isSelectable: true))
        #expect(units.contains(LayoutSelection.Unit(memberIDs: pair.map(\.uniqueIdentifier), isSelectable: true)))
        #expect(units.contains { !$0.isSelectable })
    }

    @Test("Plain, Command and Shift clicks select; only a plain click goes on to open the inspector")
    func clicksSelect() throws {
        let items = ["Alpha", "Beta", "Gamma"].map(World.item)
        let bar = try Bar(items)
        let views = try items.map(bar.view)

        #expect(try bar.click(views[0]))
        #expect(bar.selection.contains(items[0].uniqueIdentifier))
        #expect(try !bar.click(views[2], flags: .shift))
        #expect(bar.selection.count == 3)
        #expect(try !bar.click(views[1], flags: .command))
        #expect(bar.selection.orderedItemIDs == [items[0], items[2]].map(\.uniqueIdentifier))
    }

    @Test("A click on the bar between items clears the selection")
    func emptySpaceClears() throws {
        let item = World.item("Alpha")
        let bar = try Bar([item])
        _ = try bar.click(bar.view(item))
        #expect(bar.selection.count == 1)

        let interaction = try #require(bar.scrollView.selectionInteraction)
        let corner = bar.scrollView.convert(NSPoint(x: 1, y: 1), to: nil)
        #expect(interaction.handle(try bar.mouse(.leftMouseDown, at: corner)) != nil)
        #expect(bar.selection.count == 0)
    }

    @Test("Escape on a focused item clears the selection and is passed on when there is none")
    func escapeClears() throws {
        let item = World.item("Alpha")
        let bar = try Bar([item])
        let view = try bar.view(item)
        _ = try bar.click(view)
        bar.window.makeFirstResponder(view)
        let interaction = try #require(bar.scrollView.selectionInteraction)
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: bar.window.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))

        #expect(interaction.handle(escape) == nil)
        #expect(bar.selection.count == 0)
        #expect(interaction.handle(escape) != nil)
    }

    @Test("A right click or a drag on an unselected item is left to the item")
    func unselectedItemsKeepTheirOwnInput() throws {
        let items = ["Alpha", "Beta"].map(World.item)
        let bar = try Bar(items)
        let interaction = try #require(bar.scrollView.selectionInteraction)
        let location = bar.point(on: try bar.view(items[0]))

        #expect(interaction.handle(try bar.mouse(.rightMouseDown, at: location)) != nil)
        _ = interaction.handle(try bar.mouse(.leftMouseDown, at: location))
        #expect(interaction.handle(try bar.mouse(.leftMouseDragged, at: location)) != nil)
        #expect(interaction.handle(try bar.mouse(.otherMouseDown, at: location)) != nil)
        interaction.windowDidChange(nil)
        interaction.windowDidChange(bar.window)
    }

    @Test("A selected item shows it, and VoiceOver reads it and offers the selection's actions")
    func selectedItemsShowAndRead() throws {
        let items = ["Alpha", "Beta"].map(World.item)
        let bar = try Bar(items)
        let views = try items.map(bar.view)
        let unselectedActions = try #require(views[0].accessibilityCustomActions())

        _ = try bar.click(views[0])
        _ = try bar.click(views[1], flags: .command)
        #expect(views[0].isLayoutSelected)
        #expect(views[0].isAccessibilitySelected())
        #expect((views[0].accessibilityValue() as? String) == LayoutSelectionHighlight.accessibilityValue(section: .visible, isSelected: true))
        views[0].viewWillDraw()
        #expect(views[0].layer?.borderWidth ?? 0 > 0)

        let actions = try #require(views[0].accessibilityCustomActions())
        let moveTitles = bar.container.selectionMoves(for: views[0]).map(\.title)
        #expect(!moveTitles.isEmpty)
        #expect(actions.map(\.name).suffix(moveTitles.count) == moveTitles[...])
        #expect(unselectedActions.contains { $0.name == String(localized: "Add to Selection") })
        let deselect = try #require(actions.first { $0.name == String(localized: "Deselect") })
        #expect(deselect.handler?() == true)
        #expect(!views[0].isLayoutSelected)
        views[0].viewWillDraw()
        #expect(views[0].layer?.borderWidth == 0)
        #expect((views[0].accessibilityValue() as? String) == MenuBarSection.Name.visible.localizedName)
    }

    @Test("A right click on one of several selected items offers moving them all")
    func selectionMenuMovesTheBatch() async throws {
        let items = ["Alpha", "Beta"].map(World.item)
        let bar = try Bar(items)
        let views = try items.map(bar.view)
        #expect(bar.container.selectionMenu(for: views[0]) == nil)

        _ = try bar.click(views[0])
        _ = try bar.click(views[1], flags: .command)
        let menu = try #require(bar.container.selectionMenu(for: views[0]))
        let move = try #require(menu.items.compactMap { $0 as? ClosureMenuItem }.first)
        _ = move.target?.perform(move.action)
        await bar.settle()

        #expect(bar.commands.count == 1)
        #expect(bar.commands.first?.itemIDs == items.map(\.uniqueIdentifier))
        #expect(bar.commands.first?.placement == .end)
        #expect(bar.selection.count == 0)
    }

    @Test("Dropping a dragged selection on a bar moves it there in one batch")
    func dropMovesTheBatch() async throws {
        let items = ["Alpha", "Beta", "Gamma"].map(World.item)
        let bar = try Bar(items)
        let views = try items.map(bar.view)
        _ = try bar.click(views[1])
        _ = try bar.click(views[2], flags: .command)
        let drop = SelectionDrag(source: bar.scrollView, location: bar.point(on: views[0]))

        #expect(bar.scrollView.draggingEntered(drop) == .move)
        #expect(bar.scrollView.draggingUpdated(drop) == .move)
        #expect(bar.container.groupDropMarkerX != nil)
        bar.scrollView.draggingExited(drop)
        #expect(bar.container.groupDropMarkerX == nil)
        #expect(bar.scrollView.performDragOperation(drop))
        bar.scrollView.draggingEnded(drop)
        await bar.settle()

        #expect(bar.commands.first?.itemIDs == [items[1], items[2]].map(\.uniqueIdentifier))
        #expect(bar.commands.first?.section == .visible)
    }

    @Test("A drag that is not a selection is refused by the selection drop")
    func otherDragsAreRefused() throws {
        let item = World.item("Alpha")
        let bar = try Bar([item])
        let drop = SelectionDrag(source: nil, location: .zero)
        #expect(bar.scrollView.draggingEntered(drop) == [])
        #expect(!bar.scrollView.performDragOperation(drop))
    }

    @Test("Increase Contrast strengthens the highlight")
    func contrastStrengthensTheHighlight() {
        let normal = LayoutSelectionHighlight.Style(increasedContrast: false)
        let strong = LayoutSelectionHighlight.Style(increasedContrast: true)
        #expect(strong.fillAlpha > normal.fillAlpha)
        #expect(strong.strokeAlpha > normal.strokeAlpha)
        #expect(strong.lineWidth > normal.lineWidth)
    }
}
