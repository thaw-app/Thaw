//
//  LayoutSelectionInteraction.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Selection input for one Layout bar, seen ahead of the item views, which keep everything it passes on.
@MainActor
final class LayoutSelectionInteraction {
    /// One press on an item, from mouse-down to mouse-up.
    private struct Press {
        let view: LayoutBarItemView
        var isDragging = false
    }

    private weak var scrollView: LayoutBarScrollView?
    private let selection: LayoutSelectionModel
    private var press: Press?

    private lazy var monitor = EventMonitor.local(
        for: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .keyDown]
    ) { [weak self] event in
        guard let self else { return event }
        return handle(event)
    }

    init(scrollView: LayoutBarScrollView, selection: LayoutSelectionModel) {
        self.scrollView = scrollView
        self.selection = selection
    }

    /// Watches input only while the bar is in a window.
    func windowDidChange(_ window: NSWindow?) {
        if window == nil {
            monitor.stop()
            press = nil
        } else {
            monitor.start()
        }
    }

    /// Returns the event to pass on, or nil when the selection took it.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard let scrollView, event.window === scrollView.window else { return event }
        switch event.type {
        case .leftMouseDown:
            return mouseDown(event, in: scrollView)
        case .leftMouseDragged:
            return mouseDragged(event, in: scrollView)
        case .leftMouseUp:
            return mouseUp(event)
        case .rightMouseDown:
            return rightMouseDown(event, in: scrollView)
        case .keyDown:
            return keyDown(event, in: scrollView)
        default:
            return event
        }
    }

    private func mouseDown(_ event: NSEvent, in scrollView: LayoutBarScrollView) -> NSEvent? {
        press = nil
        guard let hit = hitView(for: event, in: scrollView) else { return event }
        if let view = Self.itemView(containing: hit) {
            press = Press(view: view)
        } else if !(hit is LayoutBarGroupHandleView) {
            // Empty space on the bar clears the selection.
            selection.clear()
        }
        return event
    }

    /// Dragging one of several selected items carries them all, in place of the item's own drag.
    private func mouseDragged(_ event: NSEvent, in scrollView: LayoutBarScrollView) -> NSEvent? {
        guard var press, !press.isDragging,
              let container = press.view.superview as? LayoutBarContainer,
              container.isPartOfSelection(press.view)
        else {
            return event
        }
        press.isDragging = true
        self.press = press
        scrollView.beginSelectionDrag(from: press.view, event: event)
        return nil
    }

    /// Command and Shift clicks only select; a plain click selects and still opens the inspector.
    private func mouseUp(_ event: NSEvent) -> NSEvent? {
        defer { press = nil }
        guard let press, !press.isDragging, let container = press.view.superview as? LayoutBarContainer else {
            return event
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let kind = LayoutSelection.Click(command: flags.contains(.command), shift: flags.contains(.shift))
        container.applyClick(kind, on: press.view)
        return kind == .replace ? event : nil
    }

    private func rightMouseDown(_ event: NSEvent, in scrollView: LayoutBarScrollView) -> NSEvent? {
        guard let hit = hitView(for: event, in: scrollView),
              let view = Self.itemView(containing: hit),
              let menu = (view.superview as? LayoutBarContainer)?.selectionMenu(for: view)
        else {
            return event
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        return nil
    }

    /// Escape on a focused item in this bar clears the selection.
    private func keyDown(_ event: NSEvent, in scrollView: LayoutBarScrollView) -> NSEvent? {
        guard KeyCode(rawValue: Int(event.keyCode)) == .escape,
              !selection.selection.isEmpty,
              let responder = scrollView.window?.firstResponder as? NSView,
              responder.isDescendant(of: scrollView)
        else {
            return event
        }
        selection.clear()
        return nil
    }

    private func hitView(for event: NSEvent, in scrollView: LayoutBarScrollView) -> NSView? {
        guard let superview = scrollView.superview else { return nil }
        return scrollView.hitTest(superview.convert(event.locationInWindow, from: nil))
    }

    private static func itemView(containing view: NSView) -> LayoutBarItemView? {
        sequence(first: view, next: \.superview).lazy.compactMap { $0 as? LayoutBarItemView }.first
    }
}
