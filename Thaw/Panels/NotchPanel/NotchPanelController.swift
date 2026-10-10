//
//  NotchPanelController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel

/// Owns the descender's lifecycle: the pointer resting on a menu bar item that
/// has a widget grows a descender beneath that item, and moving off it
/// retracts the descender again.
///
/// There is no resting state. An item with no widget, and empty bar space,
/// both show nothing at all, a permanent tab under every item that happens to
/// have a widget would be constant noise across the whole bar.
@MainActor
final class NotchPanelController {
    private static let diagLog = DiagLog(category: "NotchPanel")

    private let model = NotchPanelModel()
    private lazy var panel = NotchPanel(content: NotchContentView(model: model))

    private let mediaWidget = NotchMediaWidget()
    private let clockWidget = NotchClockWidget()
    private let accessoryWidget = NotchAccessoryWidget()
    private lazy var registry = NotchWidgetRegistry(widgets: [
        clockWidget,
        mediaWidget,
        // Last: it matches anything that exposes usable accessibility text, so
        // it would shadow the widgets above if it came first.
        accessoryWidget,
    ])

    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var hoverDebounce: Task<Void, Never>?
    private var transition: Task<Void, Never>?

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Defaults.Key.enableMenuBarItemDescenders.rawValue)
    }

    func performSetup(with appState: AppState) {
        self.appState = appState

        // The monitors follow the flag. A global mouse-moved monitor wakes
        // the process for every pointer event on the machine, so it must
        // not exist while the feature is off.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if isEnabled {
                    installHoverMonitors()
                } else {
                    removeHoverMonitors()
                    dismiss()
                }
            }
            .store(in: &cancellables)

        // A display change invalidates the anchor the descender was placed
        // against, and the item it belongs to may not even be on this screen
        // any more. Retract rather than leave it hanging somewhere stale.
        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in self?.dismiss() }
        .store(in: &cancellables)

        if isEnabled {
            installHoverMonitors()
        }
        Self.diagLog.info("notch panel: ready, enabled=\(isEnabled)")
    }

    // MARK: Hover

    private func installHoverMonitors() {
        guard monitors.isEmpty else { return }

        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged],
            handler: { [weak self] _ in self?.handlePointerMove() }
        )
        if let global {
            monitors.append(global)
        }

        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged],
            handler: { [weak self] event in
                self?.handlePointerMove()
                return event
            }
        )
        if let local {
            monitors.append(local)
        }
    }

    private func removeHoverMonitors() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        hoverDebounce?.cancel()
    }

    /// Debounced both ways, a pointer monitor over the menu bar fires
    /// continuously, and neither the item lookup nor a descent should run at
    /// that rate.
    private func handlePointerMove() {
        guard isEnabled else { return }
        guard let location = MouseHelpers.locationCoreGraphics else { return }

        hoverDebounce?.cancel()
        hoverDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled, let self else { return }
            update(pointerAt: location)
        }
    }

    private func update(pointerAt location: CGPoint) {
        // The pointer moving onto the descender itself must not retract it:
        // the whole point of descending is to be reachable.
        if
            model.isRevealed,
            let appKitLocation = MouseHelpers.locationAppKit,
            panel.frame.insetBy(dx: -8, dy: -8).contains(appKitLocation)
        {
            return
        }

        guard let presentation = resolve(pointerAt: location) else {
            dismiss()
            return
        }
        guard presentation.id != model.presentation?.id || !model.isRevealed else {
            return
        }
        present(presentation)
    }

    /// Finds the item under the pointer and the widget that descends from it.
    ///
    /// Hit testing uses the settled on-screen enumeration rather than asking
    /// the window server per event; the live bounds that place the descender
    /// are read once, in NotchAnchor, after an item has been chosen.
    private func resolve(pointerAt location: CGPoint) -> NotchPresentation? {
        guard let appState else { return nil }
        guard
            let item = appState.itemManager.onScreenItemSnapshot.items.first(where: {
                $0.isOnScreen && $0.bounds.contains(location)
            })
        else {
            return nil
        }
        guard let widget = registry.widget(for: item) else { return nil }
        guard
            let appKitLocation = MouseHelpers.locationAppKit,
            let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitLocation) })
        else {
            return nil
        }
        return NotchAnchor.present(widget: widget, for: item, on: screen)
    }

    // MARK: Transitions

    /// Retracts whatever is showing, moves the panel, then grows the new body
    /// out of the bar. Sliding a drawn descender sideways across the bar would
    /// read as a window moving rather than as part of the menu bar.
    private func present(_ presentation: NotchPresentation) {
        transition?.cancel()
        transition = Task { [weak self] in
            guard let self else { return }

            if model.isRevealed {
                model.setRevealed(false)
                try? await Task.sleep(for: NotchMetrics.revealDuration)
                guard !Task.isCancelled else { return }
            }

            model.stage(presentation)
            panel.apply(presentation)
            panel.orderFrontRegardless()
            panel.ignoresMouseEvents = false

            // One tick between staging and revealing, so the retracted state
            // is committed before the reveal and the body grows out of the bar
            // instead of appearing at full height.
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            model.setRevealed(true)
        }
    }

    private func dismiss() {
        guard model.presentation != nil || model.isRevealed else { return }

        transition?.cancel()
        transition = Task { [weak self] in
            guard let self else { return }
            model.setRevealed(false)
            panel.ignoresMouseEvents = true
            try? await Task.sleep(for: NotchMetrics.revealDuration)
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            model.stage(nil)
        }
    }
}
