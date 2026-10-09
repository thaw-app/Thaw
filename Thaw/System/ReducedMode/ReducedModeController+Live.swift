//
//  ReducedModeController+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import OSLog

/// The half of the reduced mode that needs a running app: a real status item, the saved icon and
/// the hand-over to the full app. The decisions are in ReducedModeController.swift.
extension ReducedModeController {
    static let shared = ReducedModeController(environment: .live())

    func start(with appState: AppState) {
        self.appState = appState
        guard statusItem == nil else { return }
        // Variable, since a custom icon may be wider than it is tall.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.setAccessibilityLabel(Constants.displayName)
        menu.delegate = self
        // Off, or AppKit switches the toggle back on whenever it has a target.
        menu.autoenablesItems = false
        // No menu on the item itself, or every click would open it.
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        applyHiding()
        Self.diagLog.info("reduced mode started; hiding available=\(self.environment.hidingIsAvailable())")
    }

    /// Shows everything and removes the status item, before the full app takes over.
    func stop() {
        environment.hide([])
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    /// The Thaw icon the user chose, in the state the full app would show: one image while apps
    /// are hidden, the other while everything is on the bar.
    func updateIcon(isHidingSomething: Bool) {
        guard let appState, let button = statusItem?.button else { return }
        let icon = Self.savedIcon()
        let image = (isHidingSomething ? icon.hidden : icon.visible).nsImage(for: appState)
        if case .custom = icon.name, let image {
            // Settings are not loaded in this mode, so the template choice is read where it is saved.
            image.isTemplate = Defaults.bool(forKey: .customThawIconIsTemplate)
            button.image = ControlItemImage.scaledToFitMenuBar(image)
        } else {
            button.image = image
        }
    }

    /// Read from where the full app saves it. The app's settings are not loaded in this mode.
    private static func savedIcon() -> ControlItemImageSet {
        guard let data = Defaults.data(forKey: .thawIcon),
              let icon = try? JSONDecoder().decode(ControlItemImageSet.self, from: data)
        else { return Defaults.DefaultValue.thawIcon }
        return icon
    }

    @objc func statusItemClicked() {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard clicked(secondary: secondary) == .openMenu, let statusItem else { return }
        // Attached only for this click, so the next plain click reaches the action again.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func switchToFullApp() {
        guard let appState else { return }
        Self.isChosen = false
        stop()
        // With the permission granted this starts the full app; without it, it opens the window that asks.
        appState.completeFirstLaunchSetup()
    }
}

extension ReducedModeController.Environment {
    @MainActor
    static func live() -> ReducedModeController.Environment {
        let hider = ReducedModeHider()
        return ReducedModeController.Environment(
            hidingIsAvailable: { hider.isAvailable },
            hide: { hider.apply(hiding: $0) },
            apps: { ReducedModeInventory.current() },
            loadHidden: { Set(Defaults.stringArray(forKey: .reducedModeHiddenBundleIDs) ?? []) },
            saveHidden: { Defaults.set($0.sorted(), forKey: .reducedModeHiddenBundleIDs) }
        )
    }
}
