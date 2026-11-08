//
//  LayoutDashboardWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import SwiftUI

/// The Layout window opened by Pop Out Editor. It stays open across Space
/// and display changes, pinned to the bar it opened for.
@MainActor
final class LayoutDashboardWindow: NSObject, NSWindowDelegate {
    private static let frameName = "ThawLayoutDashboard"
    private static let defaultSize = NSSize(width: 900, height: 520)

    private var window: NSWindow?
    private(set) var model: LayoutDashboardModel?
    private let onClose: () -> Void

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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Layout")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 360)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: LayoutDashboardView(appState: appState, model: model))
        window.setContentSize(Self.defaultSize)
        if !window.setFrameUsingName(Self.frameName) {
            let visible = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: visible.midX - Self.defaultSize.width / 2, y: visible.maxY - 80))
        }
        window.setFrameAutosaveName(Self.frameName)
        self.window = window
        self.model = model
        window.makeKeyAndOrderFront(nil)
        appState.activate(withPolicy: appState.userWindowActivationPolicy)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        window = nil
        model = nil
        onClose()
    }
}
