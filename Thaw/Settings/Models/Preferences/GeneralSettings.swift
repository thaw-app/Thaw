//
//  GeneralSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import SwiftUI

// MARK: - GeneralSettings

/// Model for the app's General settings.
@MainActor
@Observable
final class GeneralSettings {
    @ObservationIgnored
    private let diagLog = DiagLog(category: "GeneralSettings")
    /// A Boolean value that indicates whether the Thaw icon
    /// should be shown.
    var showThawIcon = Defaults.DefaultValue.showThawIcon {
        didSet {
            guard oldValue != showThawIcon else { return }
            Defaults.set(showThawIcon, forKey: .showThawIcon)
        }
    }

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    var thawIcon = Defaults.DefaultValue.thawIcon {
        didSet {
            guard oldValue != thawIcon else { return }
            if case .custom = thawIcon.name {
                lastCustomThawIcon = thawIcon
            }
            do {
                let data = try encoder.encode(thawIcon)
                Defaults.set(data, forKey: .thawIcon)
            } catch {
                diagLog.error("Error encoding \(Constants.displayName) icon: \(error)")
                thawIconPersistenceError = error
            }
        }
    }

    /// The failure from the last icon that could not be written, or nil.
    ///
    /// Parked here because a didSet cannot throw; otherwise the bar shows an
    /// icon that is gone after the next launch.
    private(set) var thawIconPersistenceError: Error?

    /// Returns and clears the pending icon failure, so the picker reports it once.
    func takeThawIconPersistenceError() -> Error? {
        defer { thawIconPersistenceError = nil }
        return thawIconPersistenceError
    }

    /// The last user-selected custom Thaw icon.
    var lastCustomThawIcon: ControlItemImageSet?

    /// A Boolean value that indicates whether custom Thaw icons
    /// should be rendered as template images.
    var customThawIconIsTemplate = Defaults.DefaultValue.customThawIconIsTemplate {
        didSet {
            guard oldValue != customThawIconIsTemplate else { return }
            Defaults.set(customThawIconIsTemplate, forKey: .customThawIconIsTemplate)
        }
    }

    /// A Boolean value that indicates whether Simple Mode is active.
    ///
    /// Simple Mode hides advanced panes from the settings window; it never
    /// disables the features themselves or discards their configuration.
    var simpleMode = Defaults.DefaultValue.simpleMode {
        didSet {
            guard oldValue != simpleMode else { return }
            Defaults.set(simpleMode, forKey: .simpleMode)
        }
    }

    /// A Boolean value that indicates whether the settings window shows the
    /// explanatory captions below rows.
    var showSettingDescriptions = Defaults.DefaultValue.showSettingDescriptions {
        didSet {
            guard oldValue != showSettingDescriptions else { return }
            Defaults.set(showSettingDescriptions, forKey: .showSettingDescriptions)
        }
    }

    /// A Boolean value that indicates whether the Thaw Bar is pinned in
    /// place instead of being draggable by its background.
    var lockThawBarPosition = Defaults.DefaultValue.lockThawBarPosition {
        didSet {
            guard oldValue != lockThawBarPosition else { return }
            Defaults.set(lockThawBarPosition, forKey: .lockThawBarPosition)
        }
    }

    /// Whether every display's corners are drawn rounded, like a MacBook's
    /// top corners, with screenCornerRadius.
    var roundScreenCorners = Defaults.DefaultValue.roundScreenCorners {
        didSet {
            guard oldValue != roundScreenCorners else { return }
            Defaults.set(roundScreenCorners, forKey: .roundScreenCorners)
        }
    }

    var screenCornerRadius = Defaults.DefaultValue.screenCornerRadius {
        didSet {
            guard oldValue != screenCornerRadius else { return }
            Defaults.set(screenCornerRadius, forKey: .screenCornerRadius)
        }
    }

    /// Whether Thaw Bar Only is in use at all. Off, its items are ordinary
    /// Hidden items again; the list is kept for when it comes back on.
    var enableThawBarOnly = Defaults.DefaultValue.enableThawBarOnly {
        didSet {
            guard oldValue != enableThawBarOnly else { return }
            Defaults.set(enableThawBarOnly, forKey: .enableThawBarOnly)
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

    /// Whether a menu bar icon opens a small Thaw Bar with the Thaw Bar Only
    /// items, which macOS never draws in the menu bar.
    var showThawBarOnlyLauncher = Defaults.DefaultValue.showThawBarOnlyLauncher {
        didSet {
            guard oldValue != showThawBarOnlyLauncher else { return }
            Defaults.set(showThawBarOnlyLauncher, forKey: .showThawBarOnlyLauncher)
        }
    }

    /// Whether items kept to the Thaw Bar come up in a small Thaw Bar when
    /// hidden items open on the menu bar, where they never appear.
    var showThawBarOnlyWithInlineReveal = Defaults.DefaultValue.showThawBarOnlyWithInlineReveal {
        didSet {
            guard oldValue != showThawBarOnlyWithInlineReveal else { return }
            Defaults.set(showThawBarOnlyWithInlineReveal, forKey: .showThawBarOnlyWithInlineReveal)
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

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    var showOnClick = Defaults.DefaultValue.showOnClick {
        didSet {
            guard oldValue != showOnClick else { return }
            Defaults.set(showOnClick, forKey: .showOnClick)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    var showOnHover = Defaults.DefaultValue.showOnHover {
        didSet {
            guard oldValue != showOnHover else { return }
            Defaults.set(showOnHover, forKey: .showOnHover)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    var showOnScroll = Defaults.DefaultValue.showOnScroll {
        didSet {
            guard oldValue != showOnScroll else { return }
            Defaults.set(showOnScroll, forKey: .showOnScroll)
        }
    }

    // The offset to apply to the menu bar item spacing and padding.

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    var autoRehide = Defaults.DefaultValue.autoRehide {
        didSet {
            guard oldValue != autoRehide else { return }
            Defaults.set(autoRehide, forKey: .autoRehide)
        }
    }

    /// A strategy that determines how the auto-rehide feature works.
    var rehideStrategy = Defaults.DefaultValue.rehideStrategy {
        didSet {
            guard oldValue != rehideStrategy else { return }
            Defaults.set(rehideStrategy.rawValue, forKey: .rehideStrategy)
        }
    }

    /// A time interval for the auto-rehide feature when its rule
    /// is RehideStrategy.timed.
    var rehideInterval = Defaults.DefaultValue.rehideInterval {
        didSet {
            guard oldValue != rehideInterval else { return }
            Defaults.set(rehideInterval, forKey: .rehideInterval)
        }
    }

    /// Time interval temporarily shown menu bar items remain visible.
    var tempShowInterval = Defaults.DefaultValue.tempShowInterval {
        didSet {
            guard oldValue != tempShowInterval else { return }
            Defaults.set(tempShowInterval, forKey: .tempShowInterval)
        }
    }

    /// Encoder for properties.
    @ObservationIgnored
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    @ObservationIgnored
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    @ObservationIgnored
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureObservers()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .showThawIcon, assign: &showThawIcon)
        Defaults.ifPresent(key: .customThawIconIsTemplate, assign: &customThawIconIsTemplate)
        Defaults.ifPresent(key: .simpleMode, assign: &simpleMode)
        Defaults.ifPresent(key: .showSettingDescriptions, assign: &showSettingDescriptions)
        Defaults.ifPresent(key: .lockThawBarPosition, assign: &lockThawBarPosition)
        Defaults.ifPresent(key: .enableThawBarOnly, assign: &enableThawBarOnly)
        Defaults.ifPresent(key: .openHiddenItemsInMenuBar, assign: &openHiddenItemsInMenuBar)
        Defaults.ifPresent(key: .roundScreenCorners, assign: &roundScreenCorners)
        Defaults.ifPresent(key: .screenCornerRadius, assign: &screenCornerRadius)
        Defaults.ifPresent(key: .showThawBarOnlyWithInlineReveal, assign: &showThawBarOnlyWithInlineReveal)
        Defaults.ifPresent(key: .showThawBarOnlyLauncher, assign: &showThawBarOnlyLauncher)
        Defaults.ifPresent(key: .useThawBar, assign: &useThawBar)
        Defaults.ifPresent(key: .useThawBarOnlyOnNotchedDisplay, assign: &useThawBarOnlyOnNotchedDisplay)
        Defaults.ifPresent(key: .thawBarLocationOnHotkey, assign: &thawBarLocationOnHotkey)
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
        Defaults.ifPresent(key: .autoRehide, assign: &autoRehide)
        Defaults.ifPresent(key: .rehideInterval, assign: &rehideInterval)
        Defaults.ifPresent(key: .tempShowInterval, assign: &tempShowInterval)

        Defaults.ifPresent(key: .thawBarLocation) { rawValue in
            if let location = ThawBarLocation(rawValue: rawValue) {
                thawBarLocation = location
            }
        }
        Defaults.ifPresent(key: .rehideStrategy) { rawValue in
            if let strategy = RehideStrategy(rawValue: rawValue) {
                rehideStrategy = strategy
            }
        }

        if let data = Defaults.data(forKey: .thawIcon) {
            do {
                thawIcon = try decoder.decode(ControlItemImageSet.self, from: data)
            } catch {
                diagLog.error("Error decoding \(Constants.displayName) icon: \(error)")
            }
            if case .custom = thawIcon.name {
                lastCustomThawIcon = thawIcon
            }
        }
    }

    /// Configures the internal observers for the model.
    ///
    /// Properties persist through didSet; only the Settings URI subscription
    /// is Combine-based.
    private func configureObservers() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: .settingsDidChangeViaURI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleExternalSettingsChange(notification)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Handles settings changed externally via Settings URI scheme.
    private func handleExternalSettingsChange(_ notification: Notification) {
        guard let key = notification.userInfo?["key"] as? String else {
            return
        }

        if let boolValue = notification.userInfo?["value"] as? Bool {
            diagLog.debug("GeneralSettings: Received external change for \(key) = \(boolValue)")

            switch key {
            case "showThawIcon" where showThawIcon != boolValue:
                showThawIcon = boolValue
            case "customThawIconIsTemplate" where customThawIconIsTemplate != boolValue:
                customThawIconIsTemplate = boolValue
            case "simpleMode" where simpleMode != boolValue:
                simpleMode = boolValue
            case "showSettingDescriptions" where showSettingDescriptions != boolValue:
                showSettingDescriptions = boolValue
            case "lockThawBarPosition" where lockThawBarPosition != boolValue:
                lockThawBarPosition = boolValue
            case "enableThawBarOnly" where enableThawBarOnly != boolValue:
                enableThawBarOnly = boolValue
            case "openHiddenItemsInMenuBar" where openHiddenItemsInMenuBar != boolValue:
                openHiddenItemsInMenuBar = boolValue
            case "showThawBarOnlyWithInlineReveal" where showThawBarOnlyWithInlineReveal != boolValue:
                showThawBarOnlyWithInlineReveal = boolValue
            case "showThawBarOnlyLauncher" where showThawBarOnlyLauncher != boolValue:
                showThawBarOnlyLauncher = boolValue
            case "useThawBarOnlyOnNotchedDisplay" where useThawBarOnlyOnNotchedDisplay != boolValue:
                useThawBarOnlyOnNotchedDisplay = boolValue
            case "thawBarLocationOnHotkey" where thawBarLocationOnHotkey != boolValue:
                thawBarLocationOnHotkey = boolValue
            case "showOnClick" where showOnClick != boolValue:
                showOnClick = boolValue
            case "showOnHover" where showOnHover != boolValue:
                showOnHover = boolValue
            case "showOnScroll" where showOnScroll != boolValue:
                showOnScroll = boolValue
            case "autoRehide" where autoRehide != boolValue:
                autoRehide = boolValue
            default:
                // Key not handled by GeneralSettings or value unchanged
                break
            }
        }

        if let doubleValue = notification.userInfo?["doubleValue"] as? Double {
            diagLog.debug("GeneralSettings: Received external change for \(key) = \(doubleValue)")

            if key == "rehideInterval", rehideInterval != doubleValue {
                rehideInterval = doubleValue
            } else if key == "tempShowInterval", tempShowInterval != doubleValue {
                tempShowInterval = doubleValue
            }
        }

        // Enums arrive as raw integers.
        if let rawEnumValue = notification.userInfo?["rawEnumValue"] as? Int {
            diagLog.debug("GeneralSettings: Received external change for \(key) = \(rawEnumValue)")

            if key == "rehideStrategy",
               let strategy = RehideStrategy(rawValue: rawEnumValue),
               rehideStrategy != strategy
            {
                rehideStrategy = strategy
            }
        }
    }
}
