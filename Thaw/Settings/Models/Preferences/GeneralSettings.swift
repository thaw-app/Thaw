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
final class GeneralSettings: SettingsURIHandling {
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

    /// System, Light, Dark or Black for Thaw's own windows.
    var settingsAppearance = SettingsAppearance.system {
        didSet {
            guard oldValue != settingsAppearance else { return }
            Defaults.set(settingsAppearance.rawValue, forKey: .settingsAppearance)
        }
    }

    /// A Boolean value that indicates whether Simple Mode's page shows the
    /// preview of the Visible, Hidden and Always Hidden sections.
    var simpleModeShowsPreview = Defaults.DefaultValue.simpleModeShowsPreview {
        didSet {
            guard oldValue != simpleModeShowsPreview else { return }
            Defaults.set(simpleModeShowsPreview, forKey: .simpleModeShowsPreview)
        }
    }

    /// Hide application menus when needed to fit menu bar items.
    var hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus {
        didSet {
            guard oldValue != hideApplicationMenus else { return }
            Defaults.set(hideApplicationMenus, forKey: .hideApplicationMenus)
        }
    }

    var enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu {
        didSet {
            guard oldValue != enableSecondaryContextMenu else { return }
            Defaults.set(enableSecondaryContextMenu, forKey: .enableSecondaryContextMenu)
        }
    }

    /// Cover Finder titles while the desktop is frontmost, leaving the Apple menu and Finder state unchanged.
    /// See ApplicationMenuCover for why this differs from hideApplicationMenus.
    var enableDesktopMenuHiding = Defaults.DefaultValue.enableDesktopMenuHiding {
        didSet {
            guard oldValue != enableDesktopMenuHiding else { return }
            Defaults.set(enableDesktopMenuHiding, forKey: .enableDesktopMenuHiding)
        }
    }

    /// Encoder for properties.
    @ObservationIgnored
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    @ObservationIgnored
    private let decoder = JSONDecoder()

    /// The thaw:// settings subscription.
    @ObservationIgnored
    private var settingsURIChanges: AnyCancellable?

    /// The shared app state.
    @ObservationIgnored
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        settingsURIChanges = subscribeToSettingsURIChanges()
    }

    /// Loads the model's initial state.
    func loadInitialState() {
        Defaults.ifPresent(key: .showThawIcon, assign: &showThawIcon)
        Defaults.ifPresent(key: .customThawIconIsTemplate, assign: &customThawIconIsTemplate)
        Defaults.ifPresent(key: .simpleMode, assign: &simpleMode)
        Defaults.ifPresent(key: .showSettingDescriptions, assign: &showSettingDescriptions)
        settingsAppearance = SettingsAppearance.stored()
        Defaults.ifPresent(key: .simpleModeShowsPreview, assign: &simpleModeShowsPreview)
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .enableSecondaryContextMenu, assign: &enableSecondaryContextMenu)
        Defaults.ifPresent(key: .enableDesktopMenuHiding, assign: &enableDesktopMenuHiding)

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

    /// The thaw:// keys of this page's Bool settings.
    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<GeneralSettings, Bool>] = [
        "showThawIcon": \.showThawIcon,
        "customThawIconIsTemplate": \.customThawIconIsTemplate,
        "simpleMode": \.simpleMode,
        "showSettingDescriptions": \.showSettingDescriptions,
        "hideApplicationMenus": \.hideApplicationMenus,
        "enableSecondaryContextMenu": \.enableSecondaryContextMenu,
        "enableDesktopMenuHiding": \.enableDesktopMenuHiding,
    ]

    /// Handles settings changed externally via Settings URI scheme.
    func handleExternalSettingsChange(_ notification: Notification) {
        if applySettingsURIChange(notification, bools: Self.uriBoolKeys) {
            return
        }
        // Enums arrive as raw integers.
        if notification.userInfo?["key"] as? String == "settingsAppearance", let rawEnumValue = notification.userInfo?["rawEnumValue"] as? Int, let appearance = SettingsAppearance(rawValue: rawEnumValue) {
            settingsAppearance = appearance
        }
    }
}
