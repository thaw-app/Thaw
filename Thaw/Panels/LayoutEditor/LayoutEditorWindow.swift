//
//  LayoutEditorWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// The reorder editor in a window of its own, so it can sit anywhere and stay open
/// while the user works in another app.
@MainActor
final class LayoutEditorWindow: NSObject, NSWindowDelegate {
    private static let frameName = "ThawLayoutEditorWindow"
    private static let defaultSize = NSSize(width: 680, height: 300)

    private var window: NSWindow?
    private let onClose: () -> Void

    var isShown: Bool {
        window?.isVisible ?? false
    }

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func show(appState: AppState, on screen: NSScreen) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // A panel closes on Escape without a monitor of its own.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Edit Layout")
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 420, height: 220)
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: ScrollView {
                LayoutEditorBars(appState: appState)
                    .padding(ThawSpacing.gutter)
            }
            .frame(minWidth: 420, minHeight: 220)
            .environment(appState)
        )
        panel.setContentSize(Self.defaultSize)
        if !panel.setFrameUsingName(Self.frameName) {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(
                x: visible.midX - Self.defaultSize.width / 2,
                y: visible.maxY - 80
            ))
        }
        panel.setFrameAutosaveName(Self.frameName)
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        window = nil
        onClose()
    }
}
