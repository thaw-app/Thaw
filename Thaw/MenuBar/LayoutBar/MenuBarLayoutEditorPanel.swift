//
//  MenuBarLayoutEditorPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// A popover with a portable version of the menu bar layout editor.
@MainActor
final class MenuBarLayoutEditorPanel: NSObject, NSPopoverDelegate {
    /// The default screen to show the popover on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    private var popover: NSPopover?

    /// Anchors the popover to the top of the screen.
    private let anchorWindow = PopoverAnchorWindow()

    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
    }

    func show(on screen: NSScreen, onDone: (() -> Void)? = nil) {
        guard
            let appState,
            let anchorView = anchorWindow.anchorView(for: screen)
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

    func close() {
        popover?.performClose(nil)
        popover = nil
    }

    // MARK: NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // The close animates, so this can arrive after a new popover opened
        // on the anchor window.
        guard popover == nil || (notification.object as? NSPopover) === popover else {
            return
        }
        anchorWindow.orderOut()
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
        // A scrolling form, so a fixed size is enough.
        controller.preferredContentSize = NSSize(width: 680, height: 640)
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        return popover
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
            // The popover is semitransient, so Escape doesn't dismiss it;
            // without a shortcut a keyboard-only user can't close the editor.
            .keyboardShortcut(.defaultAction)

            Spacer()
        }
        .buttonBorderShape(.capsule)
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
    }
}
