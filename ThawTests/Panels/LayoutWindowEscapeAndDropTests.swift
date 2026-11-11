//
//  LayoutWindowEscapeAndDropTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
struct LayoutWindowEscapeAndDropTests {
    private func escape(filter: String, editingText: Bool = false, editingFilter: Bool = false) -> LayoutDashboardKeys.Action? {
        LayoutDashboardKeys.action(
            keyCode: .escape,
            characters: "",
            flags: [],
            filterText: filter,
            isEditingText: editingText,
            isEditingFilter: editingFilter
        )
    }

    @Test("Escape in the filter field empties it, then leaves the field")
    func escapeInFilter() {
        #expect(escape(filter: "fl", editingText: true, editingFilter: true) == .clearFilter)
        #expect(escape(filter: "", editingText: true, editingFilter: true) == .endEditing)
    }

    @Test("Escape in the list empties the filter, then closes the window")
    func escapeInList() {
        #expect(escape(filter: "fl") == .clearFilter)
        #expect(escape(filter: "") == .close)
    }

    @Test("Escape in another field, such as Name, is that field's")
    func escapeInOtherField() {
        #expect(escape(filter: "fl", editingText: true) == nil)
        #expect(escape(filter: "", editingText: true) == nil)
    }

    @Test("A field counts as the filter when its center sits inside the filter's frame")
    func filterFrame() {
        let filter = NSRect(x: 10, y: 400, width: 300, height: 36)
        #expect(LayoutDashboardKeys.isInside(NSRect(x: 40, y: 408, width: 250, height: 20), filter))
        #expect(!LayoutDashboardKeys.isInside(NSRect(x: 400, y: 300, width: 200, height: 20), filter))
        #expect(!LayoutDashboardKeys.isInside(NSRect(x: 40, y: 408, width: 250, height: 20), .zero))
    }

    @Test("The filter is told apart from another field in the same window")
    func filterAmongFields() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let content = try #require(window.contentView)
        let anchor = NSView(frame: NSRect(x: 10, y: 340, width: 300, height: 36))
        let filterField = NSTextField(frame: NSRect(x: 30, y: 345, width: 250, height: 22))
        let nameField = NSTextField(frame: NSRect(x: 350, y: 100, width: 200, height: 22))
        [anchor, filterField, nameField].forEach(content.addSubview)

        #expect(window.makeFirstResponder(filterField))
        #expect(LayoutDashboardKeys.isEditingFilter(window.firstResponder, filter: anchor))
        #expect(window.makeFirstResponder(nameField))
        #expect(!LayoutDashboardKeys.isEditingFilter(window.firstResponder, filter: anchor))
        #expect(LayoutDashboardKeys.isEditingText(window.firstResponder))
        #expect(!LayoutDashboardKeys.isEditingFilter(window.firstResponder, filter: nil))
    }

    @Test("A list drop waits until the mouse button is up")
    func dropWaitsForMouseUp() async {
        var reads = 0
        await LayoutItemListDrop.afterMouseUp {
            reads += 1
            return reads < 3 ? 1 : 0
        }
        #expect(reads == 3)
    }
}
