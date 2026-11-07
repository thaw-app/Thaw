//
//  SearchListMoveTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw
import ThawUI

/// Which keys move the search list's highlight, and where they move it.
@Suite("Search list moves")
struct SearchListMoveTests {
    /// A heading, then ten rows, with a second heading after the fourth.
    private static let rows: [(id: String, isSelectable: Bool)] = [(id: "head", isSelectable: false)]
        + (0 ..< 4).map { (id: "r\($0)", isSelectable: true) }
        + [(id: "head2", isSelectable: false)]
        + (4 ..< 10).map { (id: "r\($0)", isSelectable: true) }

    @Test("The arrows and page keys move the highlight; other keys don't")
    func keyMapping() {
        #expect(SearchListMove(key: .upArrow, modifiers: []) == .up)
        #expect(SearchListMove(key: .downArrow, modifiers: []) == .down)
        #expect(SearchListMove(key: .pageUp, modifiers: []) == .pageUp)
        #expect(SearchListMove(key: .pageDown, modifiers: []) == .pageDown)
        #expect(SearchListMove(key: .home, modifiers: []) == .home)
        #expect(SearchListMove(key: .end, modifiers: []) == .end)
        #expect(SearchListMove(key: .leftArrow, modifiers: []) == nil)
        #expect(SearchListMove(key: .a, modifiers: []) == nil)
        #expect(SearchListMove(key: .returnKey, modifiers: []) == nil)
    }

    @Test("A modified arrow is left to the query field", arguments: [Modifiers.shift, .option, .command, .control])
    func modifiedArrowsPassThrough(modifier: Modifiers) {
        #expect(SearchListMove(key: .downArrow, modifiers: modifier) == nil)
        #expect(SearchListMove(key: .upArrow, modifiers: modifier) == nil)
    }

    @Test("Up and Down step over headings and stop at the ends")
    func stepping() {
        #expect(SearchListMove.down.target(from: "r3", in: Self.rows) == "r4")
        #expect(SearchListMove.up.target(from: "r4", in: Self.rows) == "r3")
        #expect(SearchListMove.up.target(from: "r0", in: Self.rows) == "r0")
        #expect(SearchListMove.down.target(from: "r9", in: Self.rows) == "r9")
    }

    @Test("Page keys skip a page and clamp; Home and End go to the ends")
    func paging() {
        #expect(SearchListMove.pageDown.target(from: "r0", in: Self.rows) == "r\(SearchListMove.pageLength)")
        #expect(SearchListMove.pageDown.target(from: "r5", in: Self.rows) == "r9")
        #expect(SearchListMove.pageUp.target(from: "r9", in: Self.rows) == "r\(9 - SearchListMove.pageLength)")
        #expect(SearchListMove.pageUp.target(from: "r2", in: Self.rows) == "r0")
        #expect(SearchListMove.home.target(from: "r6", in: Self.rows) == "r0")
        #expect(SearchListMove.end.target(from: "r1", in: Self.rows) == "r9")
    }

    @Test("With no highlight, or one that is gone, any move starts at the first row")
    func staleStart() {
        #expect(SearchListMove.down.target(from: nil as String?, in: Self.rows) == "r0")
        #expect(SearchListMove.end.target(from: "gone", in: Self.rows) == "r0")
        #expect(SearchListMove.down.target(from: "head", in: Self.rows) == "r0")
        #expect(SearchListMove.down.target(from: "r0", in: [(id: "head", isSelectable: false)]) == nil)
    }

    @Test("A highlight that is still listed stays, and a stale one moves to the first row")
    func validation() {
        #expect(SearchListSelection.validated("r5", in: Self.rows) == "r5")
        #expect(SearchListSelection.validated("gone", in: Self.rows) == "r0")
        #expect(SearchListSelection.validated("head2", in: Self.rows) == "r0")
        #expect(SearchListSelection.validated(nil as String?, in: Self.rows) == "r0")
        #expect(SearchListSelection.validated("r5", in: []) == nil)
    }
}

/// The model's highlight operations and the panel's key monitor, on a panel that is never shown.
@MainActor
@Suite("Search list keyboard", .serialized, .scratchDefaults)
struct SearchListKeyboardTests {
    private typealias ID = MenuBarSearchModel.ItemID
    private typealias World = LayoutEditorWorld

    private static func rows(_ ids: [ID]) -> [SectionedListItem<ID, MenuBarSearchListContent>] {
        ids.map { id in
            SectionedListItem(content: .label("Row"), id: id, isSelectable: id != .header(.visible) && id != .recentsHeader)
        }
    }

    @Test("The model keeps a listed highlight, replaces a stale one and moves through the rows")
    func modelOperations() {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let alphaID = ID.item(alpha.tag, windowID: alpha.windowID)
        let betaID = ID.item(beta.tag, windowID: beta.windowID)
        let model = MenuBarSearchModel()
        model.displayedItems = Self.rows([.header(.visible), alphaID, betaID])

        model.selectFirstSelectableRow()
        #expect(model.selection == alphaID)
        model.moveSelection(.down)
        #expect(model.selection == betaID)
        model.revalidateSelection()
        #expect(model.selection == betaID, "a listed highlight stays")

        // The same item under a new window ID, as after a menu bar rebuild.
        model.selection = .item(beta.tag, windowID: 99999)
        model.revalidateSelection()
        #expect(model.selection == alphaID)

        model.displayedItems = []
        model.revalidateSelection()
        #expect(model.selection == nil)
    }

    private static func keyDown(_ keyCode: KeyCode, flags: NSEvent.ModifierFlags = [], in panel: NSWindow?, isARepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: panel?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isARepeat,
            keyCode: UInt16(keyCode.rawValue)
        ))
    }

    @Test("The panel's key monitor moves the highlight for held arrows, and leaves modified arrows and renames alone")
    func panelMonitor() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        world.seat([alpha, beta])
        let panel = MenuBarSearchPanel()
        let alphaID = ID.item(alpha.tag, windowID: alpha.windowID)
        let betaID = ID.item(beta.tag, windowID: beta.windowID)
        panel.model.displayedItems = Self.rows([alphaID, betaID])
        panel.model.selection = alphaID

        let down = try Self.keyDown(.downArrow, in: panel, isARepeat: true)
        try #require(down.window === panel, "the event has to resolve to the panel")
        #expect(panel.handleKeyDown(down) == nil)
        #expect(panel.model.selection == betaID)

        let shiftUp = try Self.keyDown(.upArrow, flags: .shift, in: panel)
        #expect(panel.handleKeyDown(shiftUp) === shiftUp)
        #expect(panel.model.selection == betaID)

        let elsewhere = try Self.keyDown(.upArrow, in: nil)
        #expect(panel.handleKeyDown(elsewhere) === elsewhere, "another window's key is not this list's")

        panel.model.renameSession = .init(tag: beta.tag, windowID: beta.windowID, draft: "")
        let up = try Self.keyDown(.upArrow, in: panel)
        #expect(panel.handleKeyDown(up) === up)
        #expect(panel.model.selection == betaID)
    }
}
