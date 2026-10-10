//
//  MenuBarAppearanceEditorPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation
import SwiftUI

/// Presents the appearance editor as a popover hanging from the top of a
/// screen, for use outside the settings window.
@MainActor
final class MenuBarAppearanceEditorPanel: NSObject, NSPopoverDelegate {
    /// The default screen to show the popover on.
    static var defaultScreen: NSScreen? {
        PopoverAnchor.defaultScreen
    }

    /// The app state this panel was set up with.
    private weak var appState: AppState?

    /// Keeps the panel's Combine subscriptions alive.
    private var cancellables = Set<AnyCancellable>()

    /// Watches the appearance configuration, replacing the old Combine
    /// projection.
    private var configurationObservationTask: Task<Void, Never>?

    private var popover: NSPopover?

    /// The invisible window that hangs the popover off the top of the screen.
    private let anchor = PopoverAnchor()

    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers(with: appState)
    }

    func show(on screen: NSScreen, onDone: (() -> Void)? = nil) {
        guard
            let appState,
            let anchorView = anchor.view(atTopOf: screen)
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

    func close() {
        popover?.performClose(nil)
        popover = nil
    }

    // MARK: NSPopoverDelegate

    func popoverWillShow(_: Notification) {
        NSColorPanel.shared.hidesOnDeactivate = false
    }

    func popoverDidClose(_: Notification) {
        anchor.hide()
        NSColorPanel.shared.hidesOnDeactivate = true
        NSColorPanel.shared.close()
        MemoryReclaimer.scheduleRelief(reason: "appearance editor closed")
    }

    // MARK: Private

    /// Keeps the popover matched to the app's appearance and to the size the
    /// editor currently needs.
    private func configureObservers(with appState: AppState) {
        cancellables = [
            NSApp.publisher(for: \.effectiveAppearance)
                .sink { [weak self] appearance in
                    self?.popover?.appearance = appearance
                },
        ]
        configurationObservationTask?.cancel()
        configurationObservationTask = Task { @MainActor [weak self, appearanceManager = appState.appearanceManager] in
            let changes = Observations { appearanceManager.configuration }
            for await _ in changes {
                guard let self else { return }
                updateContentSize()
            }
        }
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
}

// MARK: - MenuBarAppearanceEditorHostingController

@MainActor
private final class MenuBarAppearanceEditorHostingController: NSHostingController<MenuBarAppearanceEditorContentView> {
    private weak var appState: AppState?

    /// Watches the appearance configuration, replacing the old Combine
    /// projection.
    private var configurationObservationTask: Task<Void, Never>?

    init(appState: AppState, onDone: (() -> Void)?) {
        self.appState = appState
        super.init(rootView: MenuBarAppearanceEditorContentView(appState: appState, onDone: onDone))
        updatePreferredContentSize()

        configurationObservationTask = Task { @MainActor [weak self, appearanceManager = appState.appearanceManager] in
            let changes = Observations { appearanceManager.configuration }
            for await _ in changes {
                guard let self else { return }
                updatePreferredContentSize()
            }
        }
    }

    isolated deinit {
        configurationObservationTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreferredContentSize() {
        guard let appState else {
            preferredContentSize = NSSize(width: 525, height: 620)
            return
        }
        let configuration = appState.appearanceManager.configuration

        // Single-editor layout: dynamic mode only adds the mode picker row.
        var height: CGFloat = configuration.isDynamic ? 610 : 555
        height += 32 // panel heading

        let partials: [MenuBarAppearancePartialConfiguration] = if configuration.isDynamic {
            // Size for the taller Light/Dark config so switching modes doesn't clip.
            [configuration.lightModeConfiguration, configuration.darkModeConfiguration]
        } else {
            [configuration.staticConfiguration]
        }

        if configuration.shapeKind != .noShape {
            height += 105 // shape chrome + margins
            height += 90 // shape fill section header + style row
            height += partials.map { Self.shapeFillExtraHeight(for: $0) }.max() ?? 0
        }

        height += partials.map { Self.backgroundExtraHeight(for: $0) }.max() ?? 0

        preferredContentSize = NSSize(width: 525, height: height)
        view.setFrameSize(preferredContentSize)
    }

    private static func shapeFillExtraHeight(for partial: MenuBarAppearancePartialConfiguration) -> CGFloat {
        var height: CGFloat = 0
        if partial.tintKind != .noTint, partial.tintKind != .glass {
            height += 40 // opacity
        }
        if partial.tintKind == .glass {
            height += 40 // glass effect
            if partial.tintGlassStyle.usesTint {
                height += 80 // color control + tint opacity
            }
        }
        if partial.hasBorder {
            height += 80 // border color + width
        }
        return height
    }

    private static func backgroundExtraHeight(for partial: MenuBarAppearancePartialConfiguration) -> CGFloat {
        guard partial.backgroundKind != .none else { return 0 }
        var height: CGFloat = 45 // opacity/effect + shadow
        if partial.backgroundKind == .glass, partial.backgroundGlassStyle.usesTint {
            height += 80 // color control + tint opacity
        }
        if partial.backgroundHasBorder {
            height += 80 // border color + width
        }
        return height
    }
}

// MARK: - MenuBarAppearanceEditorContentView

private struct MenuBarAppearanceEditorContentView: View {
    let appState: AppState
    let onDone: (() -> Void)?

    var body: some View {
        MenuBarAppearanceEditor(
            appearanceManager: appState.appearanceManager,
            location: .panel,
            onDone: onDone
        )
        .environment(appState)
    }
}
