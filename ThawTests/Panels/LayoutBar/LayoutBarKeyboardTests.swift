//
//  LayoutBarKeyboardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Keyboard focus and the guarded edges of keyboard moves, in two offscreen bars.
/// No test here reaches a move that would be committed to the menu bar.
@MainActor
@Suite("Layout bar keyboard", .serialized, .scratchDefaults)
struct LayoutBarKeyboardTests {
    private typealias World = LayoutEditorWorld

    /// Two bars, one above the other, in one offscreen window.
    @MainActor
    private final class Bars {
        let world = World()
        let window: NSWindow
        let visible: LayoutBarScrollView
        let lower: LayoutBarScrollView

        init(_ items: [MenuBarItem]) throws {
            world.seat(items, in: .visible)
            let selection = LayoutSelectionModel { _ in }
            visible = LayoutBarScrollView(appState: world.appState, section: .visible, selection: selection)
            // A second Visible bar stands in for the one below: placing items in Hidden would
            // need a section assignment, and focus crossing only reads the bars' frames.
            lower = LayoutBarScrollView(appState: world.appState, section: .visible, selection: selection)
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 120))
            window = NSWindow(contentRect: content.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = content
            for (bar, y) in [(visible, 64.0), (lower, 8.0)] {
                bar.translatesAutoresizingMaskIntoConstraints = true
                bar.frame = CGRect(x: 0, y: y, width: 600, height: 48)
                content.addSubview(bar)
                let container = try #require(bar.documentView?.subviews.lazy.compactMap { $0 as? LayoutBarContainer }.first)
                container.rebuildViews()
            }
            window.layoutIfNeeded()
        }

        func views(_ bar: LayoutBarScrollView) -> [LayoutBarItemView] {
            bar.arrangedViews.compactMap { $0 as? LayoutBarItemView }
        }

        func view(_ item: MenuBarItem) throws -> LayoutBarItemView {
            try #require(views(visible).first { $0.item.tag == item.tag })
        }

        func key(_ code: KeyCode, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: UInt16(code.rawValue)
            ))
        }

        /// Focuses view and sends it a key, returning whether the keyboard handler took it.
        func press(_ code: KeyCode, _ flags: NSEvent.ModifierFlags = [], on view: LayoutBarItemView) throws -> Bool {
            window.makeFirstResponder(view)
            return try LayoutBarKeyboard.handleKeyDown(key(code, flags), in: view)
        }

        var focused: LayoutBarItemView? {
            window.firstResponder as? LayoutBarItemView
        }
    }

    private static func items(_ names: [String]) -> [MenuBarItem] {
        names.map(World.item)
    }

    @Test("Left and right arrows step focus along a bar and stop at its ends")
    func arrowsStepFocus() throws {
        let items = Self.items(["A", "B", "C"])
        let bars = try Bars(items)
        let views = bars.views(bars.visible)
        try #require(views.count == 3)

        #expect(try bars.press(.rightArrow, on: views[0]))
        #expect(bars.focused === views[1])
        #expect(try bars.press(.leftArrow, on: views[1]))
        #expect(bars.focused === views[0])
        #expect(try bars.press(.leftArrow, on: views[0]))
        #expect(bars.focused === views[0], "the first item keeps focus")
    }

    @Test("Home, End and Command arrows jump to a bar's ends")
    func edgesJump() throws {
        let items = Self.items(["A", "B", "C"])
        let bars = try Bars(items)
        let views = bars.views(bars.visible)

        #expect(try bars.press(.end, on: views[0]))
        #expect(bars.focused === views[2])
        #expect(try bars.press(.home, on: views[2]))
        #expect(bars.focused === views[0])
        #expect(try bars.press(.rightArrow, .command, on: views[0]))
        #expect(bars.focused === views[2])
        #expect(try bars.press(.leftArrow, .command, on: views[2]))
        #expect(bars.focused === views[0])
    }

    @Test("Up and down arrows move focus to the nearest item in the bar above or below")
    func arrowsCrossBars() throws {
        let bars = try Bars(Self.items(["A", "B"]))
        let topViews = bars.views(bars.visible)
        let bottomViews = bars.views(bars.lower)
        try #require(!topViews.isEmpty && !bottomViews.isEmpty)

        #expect(try bars.press(.downArrow, on: topViews[0]))
        #expect(bars.focused === bottomViews[0], "the nearest item below keeps the same horizontal place")
        #expect(try bars.press(.upArrow, on: bottomViews[0]))
        #expect(topViews.contains { $0 === bars.focused })
        let before = bars.focused
        #expect(try bars.press(.upArrow, on: #require(before)))
        #expect(bars.focused === before, "there is no bar above Visible")
    }

    @Test("Tab steps through the key view loop and Command-Z goes to the window's undo manager")
    func tabAndUndo() throws {
        let items = Self.items(["A", "B"])
        let bars = try Bars(items)
        let views = bars.views(bars.visible)
        #expect(try bars.press(.tab, on: views[0]))
        #expect(try bars.press(.tab, .shift, on: views[0]))
        #expect(try bars.press(.z, .command, on: views[0]))
        #expect(try bars.press(.z, [.command, .shift], on: views[0]))
        #expect(try !bars.press(.a, on: views[0]), "other keys pass through")
        #expect(try !bars.press(.a, .command, on: views[0]))
    }

    @Test("Key equivalents act only on the focused item")
    func keyEquivalentsNeedFocus() throws {
        let items = Self.items(["A", "B", "C"])
        let bars = try Bars(items)
        let views = bars.views(bars.visible)
        bars.window.makeFirstResponder(views[0])
        #expect(try !LayoutBarKeyboard.handleKeyEquivalent(bars.key(.rightArrow, .command), in: views[1]))
        #expect(try !LayoutBarKeyboard.handleKeyEquivalent(bars.key(.rightArrow, [.command, .option]), in: views[0]))
        #expect(try LayoutBarKeyboard.handleKeyEquivalent(bars.key(.rightArrow, .command), in: views[0]))
        #expect(bars.focused === views[2])
        #expect(try views[2].performKeyEquivalent(with: bars.key(.leftArrow, .command)))
        #expect(bars.focused === views[0])
    }

    @Test("Moves that would leave the bar's ends, or go to the item's own or a missing section, do nothing")
    func guardedMovesDoNothing() throws {
        let item = World.item("Solo")
        let bars = try Bars([item])
        let view = try bars.view(item)
        try #require(view.isEnabled)

        #expect(try bars.press(.leftArrow, .option, on: view))
        #expect(try bars.press(.rightArrow, .option, on: view))
        #expect(try bars.press(.upArrow, .option, on: view))
        #expect(try bars.press(.one, .command, on: view))
        LayoutBarKeyboard.moveToSectionNumber(9, in: view)
        #expect(bars.world.appState.layoutFeedback.refusal == nil)
        #expect(bars.views(bars.visible).map(\.item.tag) == [item.tag])
    }

    @Test("An item macOS will not move explains itself instead of moving")
    func immovableItemExplains() throws {
        let item = World.item("Pinned")
        let bars = try Bars([item, World.item("Other")])
        let view = try bars.view(item)
        view.isEnabled = false

        #expect(try bars.press(.rightArrow, .option, on: view))
        #expect(bars.world.appState.layoutFeedback.refusal != nil)
        bars.world.appState.layoutFeedback.clear()
        #expect(try bars.press(.two, .command, on: view))
        #expect(bars.world.appState.layoutFeedback.refusal != nil)
    }

    @Test("A view outside a bar ignores keyboard moves")
    func detachedViewIgnoresMoves() {
        let world = World()
        let view = LayoutBarItemView(appState: world.appState, item: World.item("Loose"))
        LayoutBarKeyboard.moveWithinSection(view, direction: .left)
        LayoutBarKeyboard.moveAcrossSection(view, direction: .down)
        LayoutBarKeyboard.moveToSectionNumber(2, in: view)
        #expect(world.appState.layoutFeedback.refusal == nil)
        #expect(view.acceptsFirstResponder)
        #expect(view.canBecomeKeyView)
        #expect(view.focusRingMaskBounds == view.bounds)
    }
}
