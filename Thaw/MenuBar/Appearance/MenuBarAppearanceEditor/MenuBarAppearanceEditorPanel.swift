//
//  MenuBarAppearanceEditorPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// A popover that contains a portable version of the menu bar
/// appearance editor interface.
@MainActor
final class MenuBarAppearanceEditorPanel: NSObject, NSPopoverDelegate {
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
        configureObservers(with: appState)
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
        updateContentSize()
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

    func popoverWillShow(_: Notification) {
        NSColorPanel.shared.hidesOnDeactivate = false
    }

    func popoverDidClose(_: Notification) {
        anchorWindow?.orderOut(nil)
        NSColorPanel.shared.hidesOnDeactivate = true
        NSColorPanel.shared.close()
    }

    // MARK: Private

    private func configureObservers(with appState: AppState) {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in
                self?.popover?.appearance = appearance
            }
            .store(in: &c)

        appState.appearanceManager.$configuration
            .sink { [weak self] _ in
                self?.updateContentSize()
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

        let controller = MenuBarAppearanceEditorHostingController(appState: appState, onDone: onDone)
        popover.contentViewController = controller
        return popover
    }

    private func updateContentSize() {
        guard
            let popover,
            let hostingController = popover.contentViewController as? MenuBarAppearanceEditorHostingController
        else {
            return
        }
        hostingController.updatePreferredContentSize()
        popover.contentSize = hostingController.preferredContentSize
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

// MARK: - MenuBarAppearanceEditorHostingController

@MainActor
private final class MenuBarAppearanceEditorHostingController: NSHostingController<MenuBarAppearanceEditorContentView> {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, onDone: (() -> Void)?) {
        self.appState = appState
        super.init(rootView: MenuBarAppearanceEditorContentView(appState: appState, onDone: onDone))
        updatePreferredContentSize()

        appState.appearanceManager.$configuration
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePreferredContentSize()
                }
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreferredContentSize() {
        guard let appState else {
            preferredContentSize = NSSize(width: 525, height: 745)
            return
        }
        let configuration = appState.appearanceManager.configuration
        let baseHeight: CGFloat = configuration.isDynamic ? 755 : 555
        let shapeBonus: CGFloat = configuration.shapeKind == .noShape ? 0 : 105
        let headingBonus: CGFloat = 32
        let tintOpacityBonus: CGFloat = {
            guard configuration.shapeKind != .noShape, !configuration.isDynamic, configuration.current.tintKind != .noTint else { return 0 }
            return 80
        }()
        let backgroundBonus: CGFloat = {
            guard configuration.current.backgroundKind != .none else { return 0 }
            var height: CGFloat = 45 // style picker + opacity + shadow
            if configuration.current.backgroundHasBorder {
                height += 80 // border color + width
            }
            return height
        }()
        preferredContentSize = NSSize(width: 525, height: baseHeight + shapeBonus + headingBonus + tintOpacityBonus + backgroundBonus)
        view.setFrameSize(preferredContentSize)
    }
}

// MARK: - MenuBarAppearanceEditorContentView

private struct MenuBarAppearanceEditorContentView: View {
    @ObservedObject var appState: AppState
    let onDone: (() -> Void)?

    var body: some View {
        MenuBarAppearanceEditor(
            appearanceManager: appState.appearanceManager,
            location: .panel,
            onDone: onDone
        )
        .environmentObject(appState)
    }
}
