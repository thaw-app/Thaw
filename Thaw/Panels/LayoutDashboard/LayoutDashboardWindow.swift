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

    private var window: NSWindow?
    private(set) var model: LayoutDashboardModel?
    private let onClose: () -> Void

    /// Escape and ⌘W, which a window without a File menu doesn't get on its own.
    private lazy var keyMonitor = EventMonitor.local(for: [.keyDown]) { [weak self] event in
        guard let self, let window, event.window === window, let model else { return event }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let action = LayoutDashboardKeys.action(
            keyCode: KeyCode(rawValue: Int(event.keyCode)),
            characters: event.charactersIgnoringModifiers ?? "",
            flags: flags,
            filterText: model.filterText,
            isEditingText: window.firstResponder is NSText
        )
        switch action {
        case .clearFilter:
            model.filterText = ""
        case .close:
            window.performClose(nil)
        case nil:
            return event
        }
        return nil
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

/// What Escape and ⌘W do in the Layout window.
enum LayoutDashboardKeys {
    enum Action: Equatable {
        case clearFilter
        case close
    }

    /// ⌘W closes. Escape empties the filter, then closes; while a field is being typed in,
    /// Escape is the field's, which empties the filter or cancels a rename.
    static func action(
        keyCode: KeyCode,
        characters: String,
        flags: NSEvent.ModifierFlags,
        filterText: String,
        isEditingText: Bool
    ) -> Action? {
        if flags == .command, characters.lowercased() == "w" {
            return .close
        }
        guard keyCode == .escape, flags.isEmpty, !isEditingText else { return nil }
        return filterText.isEmpty ? .close : .clearFilter
    }
}
