//
//  GeneralSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - GeneralSettings

/// Model for the app's General settings.
@MainActor
final class GeneralSettings: ObservableObject {
    private let diagLog = DiagLog(category: "GeneralSettings")
    /// A Boolean value that indicates whether the Ice icon
    /// should be shown.
    @Published var showIceIcon = Defaults.DefaultValue.showIceIcon

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    @Published var iceIcon = Defaults.DefaultValue.iceIcon

    /// The last user-selected custom Ice icon.
    @Published var lastCustomIceIcon: ControlItemImageSet?

    /// A Boolean value that indicates whether custom Ice icons
    /// should be rendered as template images.
    @Published var customIceIconIsTemplate = Defaults.DefaultValue.customIceIconIsTemplate

    // MARK: - Deprecated (Per-Display Migration)

    // These properties are kept for one release cycle for downgrade safety.
    // New code should use `AppSettings.displaySettings` instead.

    /// A Boolean value that indicates whether to show hidden items
    /// in a separate bar below the menu bar.
    @Published var useIceBar = Defaults.DefaultValue.useIceBar

    /// A Boolean value that indicates whether to use the Thaw Bar
    /// only on displays with a notch.
    @Published var useIceBarOnlyOnNotchedDisplay = Defaults.DefaultValue.useIceBarOnlyOnNotchedDisplay

    /// The location where the Thaw Bar appears.
    @Published var iceBarLocation = Defaults.DefaultValue.iceBarLocation

    /// A Boolean value that indicates whether the Thaw Bar should
    /// appear at the mouse pointer's location when shown by a hotkey.
    @Published var iceBarLocationOnHotkey = Defaults.DefaultValue.iceBarLocationOnHotkey

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    @Published var showOnClick = Defaults.DefaultValue.showOnClick

    /// A Boolean value that indicates whether the always-hidden section
    /// should be shown when the mouse pointer double-clicks in an
    /// empty area of the menu bar.
    @Published var showOnDoubleClick = Defaults.DefaultValue.showOnDoubleClick

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = Defaults.DefaultValue.showOnHover

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    @Published var showOnScroll = Defaults.DefaultValue.showOnScroll

    // The offset to apply to the menu bar item spacing and padding.

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    @Published var autoRehide = Defaults.DefaultValue.autoRehide

    /// A strategy that determines how the auto-rehide feature works.
    @Published var rehideStrategy = Defaults.DefaultValue.rehideStrategy

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    @Published var rehideInterval = Defaults.DefaultValue.rehideInterval

    /// Encoder for properties.
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .showIceIcon, assign: &showIceIcon)
        Defaults.ifPresent(key: .customIceIconIsTemplate, assign: &customIceIconIsTemplate)
        Defaults.ifPresent(key: .useIceBar, assign: &useIceBar)
        Defaults.ifPresent(key: .useIceBarOnlyOnNotchedDisplay, assign: &useIceBarOnlyOnNotchedDisplay)
        Defaults.ifPresent(key: .iceBarLocationOnHotkey, assign: &iceBarLocationOnHotkey)
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnDoubleClick, assign: &showOnDoubleClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
        Defaults.ifPresent(key: .autoRehide, assign: &autoRehide)
        Defaults.ifPresent(key: .rehideInterval, assign: &rehideInterval)

        Defaults.ifPresent(key: .iceBarLocation) { rawValue in
            if let location = IceBarLocation(rawValue: rawValue) {
                iceBarLocation = location
            }
        }
        Defaults.ifPresent(key: .rehideStrategy) { rawValue in
            if let strategy = RehideStrategy(rawValue: rawValue) {
                rehideStrategy = strategy
            }
        }

        if let data = Defaults.data(forKey: .iceIcon) {
            do {
                iceIcon = try decoder.decode(ControlItemImageSet.self, from: data)
            } catch {
                diagLog.error("Error decoding \(Constants.displayName) icon: \(error)")
            }
            if case .custom = iceIcon.name {
                lastCustomIceIcon = iceIcon
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $showIceIcon.persistToDefaults(key: .showIceIcon, in: &c)

        // iceIcon requires encoding + custom icon tracking - keep manual
        $iceIcon
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] iceIcon in
                guard let self else {
                    return
                }
                if case .custom = iceIcon.name {
                    lastCustomIceIcon = iceIcon
                }
                do {
                    let data = try encoder.encode(iceIcon)
                    Defaults.set(data, forKey: .iceIcon)
                } catch {
                    diagLog.error("Error encoding \(Constants.displayName) icon: \(error)")
                }
            }
            .store(in: &c)

        $customIceIconIsTemplate.persistToDefaults(key: .customIceIconIsTemplate, in: &c)
        $useIceBar.persistToDefaults(key: .useIceBar, in: &c)
        $useIceBarOnlyOnNotchedDisplay.persistToDefaults(key: .useIceBarOnlyOnNotchedDisplay, in: &c)
        $iceBarLocation.persistToDefaults(key: .iceBarLocation, transform: \.rawValue, in: &c)
        $iceBarLocationOnHotkey.persistToDefaults(key: .iceBarLocationOnHotkey, in: &c)
        $showOnClick.persistToDefaults(key: .showOnClick, in: &c)
        $showOnDoubleClick.persistToDefaults(key: .showOnDoubleClick, in: &c)
        $showOnHover.persistToDefaults(key: .showOnHover, in: &c)
        $showOnScroll.persistToDefaults(key: .showOnScroll, in: &c)
        $autoRehide.persistToDefaults(key: .autoRehide, in: &c)
        $rehideStrategy.persistToDefaults(key: .rehideStrategy, transform: \.rawValue, in: &c)
        $rehideInterval.persistToDefaults(key: .rehideInterval, in: &c)

        // Observe external settings changes via Settings URI
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

        // Handle boolean values
        if let boolValue = notification.userInfo?["value"] as? Bool {
            diagLog.debug("GeneralSettings: Received external change for \(key) = \(boolValue)")

            switch key {
            case "showIceIcon" where showIceIcon != boolValue:
                showIceIcon = boolValue
            case "customIceIconIsTemplate" where customIceIconIsTemplate != boolValue:
                customIceIconIsTemplate = boolValue
            case "useIceBar" where useIceBar != boolValue:
                useIceBar = boolValue
            case "useIceBarOnlyOnNotchedDisplay" where useIceBarOnlyOnNotchedDisplay != boolValue:
                useIceBarOnlyOnNotchedDisplay = boolValue
            case "iceBarLocationOnHotkey" where iceBarLocationOnHotkey != boolValue:
                iceBarLocationOnHotkey = boolValue
            case "showOnClick" where showOnClick != boolValue:
                showOnClick = boolValue
            case "showOnDoubleClick" where showOnDoubleClick != boolValue:
                showOnDoubleClick = boolValue
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

        // Handle double values
        if let doubleValue = notification.userInfo?["doubleValue"] as? Double {
            diagLog.debug("GeneralSettings: Received external change for \(key) = \(doubleValue)")

            if key == "rehideInterval", rehideInterval != doubleValue {
                rehideInterval = doubleValue
            }
        }

        // Handle enum values (raw integers)
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
