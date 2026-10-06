//
//  MenuBarLayoutEditorPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import SwiftUI
import ThawUI

/// Thaw's quick edit surface: the layout editor, hung under the real menu
/// bar, without the Settings window in the way.
///
/// The "Edit Layout" entry in Thaw's secondary context menu, the
/// .toggleLayoutEditor hotkey (see HotkeyAction) and
/// thaw://toggle-layout-editor (see the app delegate's URL dispatch) all land
/// on the same object.
///
/// The popover is .applicationDefined, not .semitransient. Each glyph in the
/// layout bar opens LayoutBarItemInspector in its own .transient popover
/// anchored inside this one, and AppKit treats a click on that nested popover
/// as activity that can retire the outer one, which tears out the inspector's
/// anchor and can strand the item's spotlight on.
///
/// With .applicationDefined AppKit never closes the popover itself;
/// dismissMonitor treats any window in the popover's own window chain (the
/// inspector's popover window, item menus) as inside. Closing always goes
/// through close(), which the nested surfaces' teardown paths also funnel
/// into, so the spotlight is released exactly once.
@MainActor
final class MenuBarLayoutEditorPanel: NSObject, NSPopoverDelegate {
    /// The default screen to show the popover on.
    ///
    /// The pointer wins over .main: the panel is summoned by a click or
    /// hotkey on a particular display, and the editor should appear there.
    static var defaultScreen: NSScreen? {
        ScreenTopPopoverAnchor.defaultScreen
    }

    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    private var popover: NSPopover?

    /// The invisible window that hangs the popover off the top of the screen.
    private let anchor = ScreenTopPopoverAnchor()

    /// Whether the editor is currently on screen.
    ///
    /// Drives toggle(on:onDone:): a summon gesture while the panel is up puts
    /// it away, like every other toggling surface in Thaw.
    var isShown: Bool {
        popover?.isShown ?? false
    }

    /// Dismisses the panel when a click lands genuinely outside it.
    ///
    /// Universal scope, so a click into another app closes the editor too.
    /// The local half returns the event untouched: dismissal is a side
    /// effect, never a swallowed click.
    private lazy var dismissMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
        guard let self, !isEventInsideEditor(event) else {
            return event
        }
        close()
        return event
    }

    /// Closes the panel on Escape.
    ///
    /// Local only, and honored only for the editor's own window: nested
    /// surfaces own their cancellation (Escape in the inspector's rename field
    /// abandons the rename, Escape in the inspector closes just the
    /// inspector). When we do act the event is swallowed, so the same
    /// keystroke cannot also cancel something behind the editor.
    private lazy var escapeMonitor = EventMonitor.local(for: [.keyDown]) { [weak self] event in
        guard
            let self,
            KeyCode(rawValue: Int(event.keyCode)) == .escape,
            let editorWindow = popover?.contentViewController?.view.window,
            event.window === editorWindow
        else {
            return event
        }
        close()
        return nil
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
    }

    func show(on screen: NSScreen, onDone: (() -> Void)? = nil) {
        guard
            let appState,
            let anchorView = anchor.view(for: screen)
        else {
            return
        }
        close()
        appState.navigationState.isLayoutEditorPresented = true
        appState.imageCache.prepareForPresentation()
        popover = makePopover(appState: appState, onDone: onDone)
        popover?.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        appState.navigationState.isLayoutEditorPresented = isShown

        // Nothing retires an .applicationDefined popover but us, so the
        // monitors that do the retiring go up with it.
        dismissMonitor.start()
        escapeMonitor.start()

        Task { @MainActor [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.popover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Shows the editor on the pointer's screen, or puts it away if it is
    /// already up.
    ///
    /// The entry point for summon gestures that carry no screen of their own
    /// (the hotkey and the thaw:// action). onDone defaults to plain
    /// dismissal.
    func toggle(onDone: (() -> Void)? = nil) {
        if isShown {
            close()
            return
        }
        guard let screen = Self.defaultScreen else {
            return
        }
        show(on: screen, onDone: onDone ?? { [weak self] in self?.close() })
    }

    func close() {
        appState?.navigationState.isLayoutEditorPresented = false
        dismissMonitor.stop()
        escapeMonitor.stop()
        popover?.performClose(nil)
        popover = nil
    }

    // MARK: NSPopoverDelegate

    func popoverDidClose(_: Notification) {
        appState?.navigationState.isLayoutEditorPresented = false
        // Covers the paths that bypass close(), a popover torn down with
        // its anchor window, say, so the monitors can never outlive the
        // surface they exist to dismiss.
        dismissMonitor.stop()
        escapeMonitor.stop()
        anchor.hide()
        // The popover and its layout bars are rebuilt per show, so this
        // close really does free them.
        MemoryReclaimer.scheduleRelief(reason: "layout editor closed")
    }

    // MARK: Private

    private func configureObservers() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in
                self?.popover?.appearance = appearance
            }
            .store(in: &c)

        // A space switch or a display rearrangement invalidates where the
        // panel is hanging, and, worse, the menu bar it is describing. Take
        // it down rather than leave a stale editor pinned to nothing.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.activeSpaceDidChangeNotification
            ).replace(with: ()),
            DisplayTopology.shared.screenParametersChanged
        )
        .sink { [weak self] in
            self?.close()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Whether event landed on the editor or on something the editor put on
    /// screen.
    ///
    /// The primary test is the window chain: AppKit parents a popover's window
    /// to the window holding its anchor view, so the item inspector walks back
    /// up to us. The class-name check is a fallback because popover window
    /// parenting is not contractual, and a false negative (the editor
    /// vanishing mid-inspection) costs far more than a stray click that fails
    /// to dismiss.
    private func isEventInsideEditor(_ event: NSEvent) -> Bool {
        guard let editorWindow = popover?.contentViewController?.view.window else {
            return false
        }
        var candidate: NSWindow? = event.window
        while let window = candidate {
            if window === editorWindow {
                return true
            }
            if String(describing: type(of: window)).localizedCaseInsensitiveContains("popover") {
                return true
            }
            candidate = window.parent
        }
        return false
    }

    private func makePopover(appState: AppState, onDone: (() -> Void)?) -> NSPopover {
        let popover = NSPopover()
        // See the type's documentation: dismissal is ours, because a nested
        // .transient inspector popover inside an AppKit-dismissed one is a
        // race we lose.
        popover.behavior = .applicationDefined
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
}

// MARK: - MenuBarLayoutEditorContentView

/// The quick-edit panel's contents: the layout pane itself, in the chrome it
/// shares with the Appearance popover. See EditorPanelChrome for why the
/// bars carry no glass of their own.
private struct MenuBarLayoutEditorContentView: View {
    let appState: AppState
    let onDone: (() -> Void)?

    var body: some View {
        EditorPanelChrome(
            "Layout",
            subtitle: "Drag to rearrange. Click an item to inspect it."
        ) {
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        } bottomBar: {
            Button("Done") {
                onDone?()
            }
            .keyboardShortcut(.defaultAction)

            Spacer()

            // Escape is the panel's real dismissal gesture; say so once,
            // quietly, rather than leaving it to be discovered.
            Text("Press Esc to close")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
        }
        .environment(appState)
    }
}
