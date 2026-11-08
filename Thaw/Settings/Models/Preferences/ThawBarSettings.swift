//
//  ThawBarSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel
import Observation

/// Model for the Thaw Bar page's settings.
@MainActor
@Observable
final class ThawBarSettings: SettingsURIHandling {
    /// A Boolean value that indicates whether the Thaw Bar is pinned in
    /// place instead of being draggable by its background.
    var lockThawBarPosition = Defaults.DefaultValue.lockThawBarPosition {
        didSet {
            guard oldValue != lockThawBarPosition else { return }
            Defaults.set(lockThawBarPosition, forKey: .lockThawBarPosition)
        }
    }

    /// Whether clicking a hidden item, in the Thaw Bar, search or elsewhere,
    /// shows it in the menu bar and opens its menu there. Off, the menu opens
    /// without the icon appearing, and only apps that ignore that are shown.
    var openHiddenItemsInMenuBar = Defaults.DefaultValue.openHiddenItemsInMenuBar {
        didSet {
            guard oldValue != openHiddenItemsInMenuBar else { return }
            Defaults.set(openHiddenItemsInMenuBar, forKey: .openHiddenItemsInMenuBar)
        }
    }

    // MARK: - Deprecated (Per-Display Migration)

    // These properties are kept for one release cycle for downgrade safety.
    // New code should use AppSettings.displaySettings instead.

    /// A Boolean value that indicates whether to show hidden items
    /// in a separate bar below the menu bar.
    var useThawBar = Defaults.DefaultValue.useThawBar {
        didSet {
            guard oldValue != useThawBar else { return }
            Defaults.set(useThawBar, forKey: .useThawBar)
        }
    }

    /// A Boolean value that indicates whether to use the Thaw Bar
    /// only on displays with a notch.
    var useThawBarOnlyOnNotchedDisplay = Defaults.DefaultValue.useThawBarOnlyOnNotchedDisplay {
        didSet {
            guard oldValue != useThawBarOnlyOnNotchedDisplay else { return }
            Defaults.set(useThawBarOnlyOnNotchedDisplay, forKey: .useThawBarOnlyOnNotchedDisplay)
        }
    }

    /// The location where the Thaw Bar appears.
    var thawBarLocation = Defaults.DefaultValue.thawBarLocation {
        didSet {
            guard oldValue != thawBarLocation else { return }
            Defaults.set(thawBarLocation.rawValue, forKey: .thawBarLocation)
        }
    }

    /// A Boolean value that indicates whether the Thaw Bar should
    /// appear at the mouse pointer's location when shown by a hotkey.
    var thawBarLocationOnHotkey = Defaults.DefaultValue.thawBarLocationOnHotkey {
        didSet {
            guard oldValue != thawBarLocationOnHotkey else { return }
            Defaults.set(thawBarLocationOnHotkey, forKey: .thawBarLocationOnHotkey)
        }
    }

    @ObservationIgnored
    private var settingsURIChanges: AnyCancellable?

    func performSetup() {
        loadInitialState()
        settingsURIChanges = subscribeToSettingsURIChanges()
    }

    /// Reads the stored values.
    func loadInitialState() {
        Defaults.ifPresent(key: .lockThawBarPosition, assign: &lockThawBarPosition)
        Defaults.ifPresent(key: .openHiddenItemsInMenuBar, assign: &openHiddenItemsInMenuBar)
        Defaults.ifPresent(key: .useThawBar, assign: &useThawBar)
        Defaults.ifPresent(key: .useThawBarOnlyOnNotchedDisplay, assign: &useThawBarOnlyOnNotchedDisplay)
        Defaults.ifPresent(key: .thawBarLocationOnHotkey, assign: &thawBarLocationOnHotkey)
        Defaults.ifPresent(key: .thawBarLocation) { rawValue in
            if let location = ThawBarLocation(rawValue: rawValue) {
                thawBarLocation = location
            }
        }
    }

    /// The thaw:// keys of this page's Bool settings.
    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<ThawBarSettings, Bool>] = [
        "lockThawBarPosition": \.lockThawBarPosition,
        "openHiddenItemsInMenuBar": \.openHiddenItemsInMenuBar,
        "useThawBarOnlyOnNotchedDisplay": \.useThawBarOnlyOnNotchedDisplay,
        "thawBarLocationOnHotkey": \.thawBarLocationOnHotkey,
    ]

    /// Applies a thaw:// settings change for one of this page's keys.
    func handleExternalSettingsChange(_ notification: Notification) {
        applySettingsURIChange(notification, bools: Self.uriBoolKeys)
    }
}
