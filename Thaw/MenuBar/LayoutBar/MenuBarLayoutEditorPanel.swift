//
//  MenuBarLayoutEditorPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// A popover that contains a portable version of the menu bar
/// layout editor interface.
@MainActor
final class MenuBarLayoutEditorPanel: NSObject, NSPopoverDelegate {
    /// The default screen to show the popover on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The underlying popover.
    private var popover: NSPopover?

    /// An invisible window used to anchor the popover to the top of the screen.
    private var anchorWindow: NSWindow?

    /// Sets up the popover.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
    }

    /// Shows the popover on the given screen.
    func show(on screen: NSScreen, onDone: (() -> Void)? = nil) {
        guard
            let appState,
            let anchorView = anchorView(for: screen)
        else {
            return
        }
        close()
        popover = makePopover(appState: appState, onDone: onDone)
        popover?.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)

        Task { @MainActor [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.popover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Closes the popover if it is shown.
    func close() {
        popover?.performClose(nil)
        popover = nil
    }

    // MARK: NSPopoverDelegate

    func popoverDidClose(_: Notification) {
        anchorWindow?.orderOut(nil)
    }

    // MARK: Private

    private func configureObservers() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in
                self?.popover?.appearance = appearance
            }
            .store(in: &c)

        cancellables = c
    }

    private func makePopover(appState: AppState, onDone: (() -> Void)?) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSApp.effectiveAppearance

        let controller = NSHostingController(
            rootView: MenuBarLayoutEditorContentView(appState: appState, onDone: onDone)
        )
        // The layout pane is a scrolling form, so unlike the appearance editor
        // the height doesn't need to track a configuration; a fixed size wide
        // enough for the layout bars is sufficient.
        controller.preferredContentSize = NSSize(width: 680, height: 640)
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        return popover
    }

    private func anchorView(for screen: NSScreen) -> NSView? {
        let window: NSWindow
        if let anchorWindow {
            window = anchorWindow
        } else {
            let newWindow = NSWindow(
                contentRect: .init(origin: .zero, size: .init(width: 1, height: 1)),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .statusBar
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.contentView = NSView(
                frame: .init(origin: .zero, size: .init(width: 1, height: 1))
            )
            anchorWindow = newWindow
            window = newWindow
        }

        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.midX, y: frame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()

        return window.contentView
    }
}

// MARK: - MenuBarLayoutEditorContentView

private struct MenuBarLayoutEditorContentView: View {
    let appState: AppState
    let onDone: (() -> Void)?

    var body: some View {
        MenuBarLayoutSettingsPane(
            itemManager: appState.itemManager,
            advancedSettings: appState.settings.advanced
        )
        .scrollEdgeEffectStyle(.automatic, for: .vertical)
        .safeAreaBar(edge: .top, spacing: 0) {
            panelHeading
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            panelBottomBar
        }
        .environment(appState)
    }

    private var panelHeading: some View {
        Text("Layout")
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
    }

    private var panelBottomBar: some View {
        HStack {
            Button("Done") {
                onDone?()
            }

            Spacer()
        }
        .buttonBorderShape(.capsule)
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
    }
}
