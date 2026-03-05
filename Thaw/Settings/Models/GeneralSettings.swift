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

    /// A Boolean value that indicates whether to use the Ice Bar
    /// only on displays with a notch.
    @Published var useIceBarOnlyOnNotchedDisplay = Defaults.DefaultValue.useIceBarOnlyOnNotchedDisplay

    /// The location where the Ice Bar appears.
    @Published var iceBarLocation = Defaults.DefaultValue.iceBarLocation

    /// A Boolean value that indicates whether the Ice Bar should
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

    /// The offset to apply to the menu bar item spacing and padding.
    @Published var itemSpacingOffset = Defaults.DefaultValue.itemSpacingOffset

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
        Defaults.ifPresent(key: .itemSpacingOffset, assign: &itemSpacingOffset)
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

        $showIceIcon
            .receive(on: DispatchQueue.main)
            .sink { showIceIcon in
                Defaults.set(showIceIcon, forKey: .showIceIcon)
            }
            .store(in: &c)

        $iceIcon
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

        $customIceIconIsTemplate
            .receive(on: DispatchQueue.main)
            .sink { isTemplate in
                Defaults.set(isTemplate, forKey: .customIceIconIsTemplate)
            }
            .store(in: &c)

        $useIceBar
            .receive(on: DispatchQueue.main)
            .sink { useIceBar in
                Defaults.set(useIceBar, forKey: .useIceBar)
            }
            .store(in: &c)

        $useIceBarOnlyOnNotchedDisplay
            .receive(on: DispatchQueue.main)
            .sink { useIceBarOnlyOnNotchedDisplay in
                Defaults.set(useIceBarOnlyOnNotchedDisplay, forKey: .useIceBarOnlyOnNotchedDisplay)
            }
            .store(in: &c)

        $iceBarLocation
            .receive(on: DispatchQueue.main)
            .sink { location in
                Defaults.set(location.rawValue, forKey: .iceBarLocation)
            }
            .store(in: &c)

        $iceBarLocationOnHotkey
            .receive(on: DispatchQueue.main)
            .sink { iceBarLocationOnHotkey in
                Defaults.set(iceBarLocationOnHotkey, forKey: .iceBarLocationOnHotkey)
            }
            .store(in: &c)

        $showOnClick
            .receive(on: DispatchQueue.main)
            .sink { showOnClick in
                Defaults.set(showOnClick, forKey: .showOnClick)
            }
            .store(in: &c)

        $showOnDoubleClick
            .receive(on: DispatchQueue.main)
            .sink { showOnDoubleClick in
                Defaults.set(showOnDoubleClick, forKey: .showOnDoubleClick)
            }
            .store(in: &c)

        $showOnHover
            .receive(on: DispatchQueue.main)
            .sink { showOnHover in
                Defaults.set(showOnHover, forKey: .showOnHover)
            }
            .store(in: &c)

        $showOnScroll
            .receive(on: DispatchQueue.main)
            .sink { showOnScroll in
                Defaults.set(showOnScroll, forKey: .showOnScroll)
            }
            .store(in: &c)

        $itemSpacingOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] offset in
                Defaults.set(offset, forKey: .itemSpacingOffset)
                appState?.spacingManager.offset = Int(offset)
            }
            .store(in: &c)

        $autoRehide
            .receive(on: DispatchQueue.main)
            .sink { autoRehide in
                Defaults.set(autoRehide, forKey: .autoRehide)
            }
            .store(in: &c)

        $rehideStrategy
            .receive(on: DispatchQueue.main)
            .sink { strategy in
                Defaults.set(strategy.rawValue, forKey: .rehideStrategy)
            }
            .store(in: &c)

        $rehideInterval
            .receive(on: DispatchQueue.main)
            .sink { interval in
                Defaults.set(interval, forKey: .rehideInterval)
            }
            .store(in: &c)

        cancellables = c
    }
}
