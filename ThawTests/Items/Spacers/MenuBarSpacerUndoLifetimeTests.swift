//
//  MenuBarSpacerUndoLifetimeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Spacer undo steps live in the undo manager, so they must not keep that manager alive themselves.
@MainActor
@Suite("Spacer undo lifetime", .serialized, .scratchDefaults)
struct MenuBarSpacerUndoLifetimeTests {
    @Test("An undo manager holding spacer steps goes away with its owner")
    func undoManagerIsReleased() throws {
        let spacers = MenuBarSpacerManager()
        weak var released: UndoManager?
        try autoreleasepool {
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            released = undoManager
            undoManager.beginUndoGrouping()
            spacers.addSpacer(undoManager: undoManager)
            let spacer = try #require(spacers.spacers.last)
            spacers.setWidth(spacer.width + 4, for: spacer.id, undoManager: undoManager)
            undoManager.endUndoGrouping()
        }
        #expect(released == nil)
        for spacer in spacers.spacers {
            spacers.removeSpacer(id: spacer.id)
        }
    }
}
