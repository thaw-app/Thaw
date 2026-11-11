//
//  LayoutDashboardWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import SwiftUI
import ThawUI

/// The Layout window opened by Pop Out Editor. It stays open across Space
/// and display changes, pinned to the bar it opened for.
@MainActor
final class LayoutDashboardWindow: NSObject, NSWindowDelegate {
    private static let frameName = "ThawLayoutDashboard"
    private static let defaultSize = NSSize(width: 1100, height: 640)
    /// No full screen: there the window showed no close button, which left only quitting Thaw.
    /// The green button zooms the window instead.
    static let collectionBehavior: NSWindow.CollectionBehavior = .fullScreenNone

    private var window: NSWindow?
    private(set) var model: LayoutDashboardModel?
    private weak var appState: AppState?
    private let onClose: () -> Void

    /// Escape, ⌘W and ⌘Z, which a window in an app without File and Edit menus doesn't get on its own.
    private lazy var keyMonitor = EventMonitor.local(for: [.keyDown]) { [weak self] event in
        guard let self, let window, event.window === window, let model else { return event }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let action = LayoutDashboardKeys.action(
            keyCode: KeyCode(rawValue: Int(event.keyCode)),
            characters: event.charactersIgnoringModifiers ?? "",
            flags: flags,
            filterText: model.filterText,
            isEditingText: LayoutDashboardKeys.isEditingText(window.firstResponder),
            isEditingFilter: LayoutDashboardKeys.isEditingFilter(window.firstResponder, filter: model.filterAnchor)
        )
        switch action {
        case .clearFilter:
            model.filterText = ""
        case .endEditing:
            window.makeFirstResponder(nil)
        case .close:
            window.performClose(nil)
        case let .undo(redo):
            undo(redo: redo, in: window, isEditable: model.pin.isEditable)
        case nil:
            return event
        }
        return nil
    }

    /// Typing in a field undoes first; after that, and anywhere else, the layout's history.
    private func undo(redo: Bool, in window: NSWindow, isEditable: Bool) {
        let typing = LayoutDashboardKeys.isEditingText(window.firstResponder) ? window.undoManager : nil
        if let typing, redo ? typing.canRedo : typing.canUndo {
            Self.step(typing, redo: redo)
        } else if isEditable, let history = appState?.layoutUndo {
            Self.step(history, redo: redo)
        }
    }

    private static func step(_ manager: UndoManager, redo: Bool) {
        if redo {
            manager.redo()
        } else {
            manager.undo()
        }
    }

    var isShown: Bool {
        window?.isVisible ?? false
    }

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func show(appState: AppState, on screen: NSScreen, displayInvalidations: some Publisher<Void, Never>) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            appState.activate(withPolicy: appState.userWindowActivationPolicy)
            return
        }
        let model = LayoutDashboardModel.live(appState: appState, displayInvalidations: displayInvalidations)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Layout")
        window.isReleasedWhenClosed = false
        window.collectionBehavior.formUnion(Self.collectionBehavior)
        window.contentMinSize = LayoutDashboardMetrics.windowMinSize
        window.delegate = self
        let host = NSHostingController(rootView: LayoutDashboardView(appState: appState, model: model))
        // Lets the view's .toolbar, title and subtitle reach the window, as a native toolbar.
        host.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = host
        window.toolbarStyle = .unified
        window.setContentSize(Self.defaultSize)
        if !window.setFrameUsingName(Self.frameName) {
            let visible = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: visible.midX - Self.defaultSize.width / 2, y: visible.maxY - 80))
        }
        window.setFrameAutosaveName(Self.frameName)
        self.window = window
        self.model = model
        self.appState = appState
        keyMonitor.start()
        window.makeKeyAndOrderFront(nil)
        appState.activate(withPolicy: appState.userWindowActivationPolicy)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        keyMonitor.stop()
        window = nil
        model = nil
        onClose()
    }
}

/// What Escape, ⌘W and ⌘Z do in the Layout window.
enum LayoutDashboardKeys {
    enum Action: Equatable {
        case clearFilter
        case endEditing
        case close
        case undo(redo: Bool)
    }

    /// ⌘W closes and ⌘Z or ⇧⌘Z undo or redo. Escape empties the filter, then closes. In the filter
    /// field it empties the field, then leaves it; in any other field, Escape is the field's.
    static func action(
        keyCode: KeyCode,
        characters: String,
        flags: NSEvent.ModifierFlags,
        filterText: String,
        isEditingText: Bool,
        isEditingFilter: Bool = false
    ) -> Action? {
        switch (flags, characters.lowercased()) {
        case (.command, "w"): return .close
        case (.command, "z"): return .undo(redo: false)
        case ([.command, .shift], "z"): return .undo(redo: true)
        default: break
        }
        guard keyCode == .escape, flags.isEmpty else { return nil }
        if isEditingFilter {
            return filterText.isEmpty ? .endEditing : .clearFilter
        }
        guard !isEditingText else { return nil }
        return filterText.isEmpty ? .close : .clearFilter
    }

    /// Whether the field being typed in is the list's filter: its text field sits inside the
    /// filter's frame. Escape in the filter field left it untouched, so the window empties it.
    static func isEditingFilter(_ responder: NSResponder?, filter: NSView?) -> Bool {
        guard isEditingText(responder), let editor = responder as? NSTextView, let field = editor.delegate as? NSView, let filter, field.window === filter.window, field.window != nil
        else { return false }
        return isInside(field.convert(field.bounds, to: nil), filter.convert(filter.bounds, to: nil))
    }

    /// Whether a field's frame sits inside the filter's, both in window coordinates.
    static func isInside(_ field: NSRect, _ filter: NSRect) -> Bool {
        !filter.isEmpty && filter.insetBy(dx: -1, dy: -1).contains(NSPoint(x: field.midX, y: field.midY))
    }

    /// Whether a text field is being typed in. Only a field editor counts, so a text view that
    /// SwiftUI uses for a focusable list's keys can't keep Escape from the window.
    static func isEditingText(_ responder: NSResponder?) -> Bool {
        (responder as? NSTextView)?.isFieldEditor == true
    }
}
