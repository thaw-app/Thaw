//
//  HotkeysSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Model for the app's Hotkeys settings.
@MainActor
@Observable
final class HotkeysSettings {
    @ObservationIgnored
    private let diagLog = DiagLog(category: "HotkeysSettings")
    /// The app's hotkey registry.
    let registry = HotkeyRegistry()

    /// The app's hotkeys.
    let hotkeys = HotkeyAction.settingsActions.map { action in
        Hotkey(action: action)
    }

    /// Encoder for properties.
    @ObservationIgnored
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    @ObservationIgnored
    private let decoder = JSONDecoder()

    /// The shared app state.
    @ObservationIgnored
    private(set) weak var appState: AppState?

    /// Loads persisted bindings and begins observing subsequent edits.
    init() {
        loadInitialState()
        configureObservers()
    }

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        for hotkey in hotkeys {
            hotkey.performSetup(with: appState)
        }
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        guard
            let dictionary = Defaults.dictionary(forKey: .hotkeys) as? [String: Data],
            !dictionary.isEmpty
        else {
            return
        }
        for hotkey in hotkeys {
            guard let data = dictionary[hotkey.action.rawValue] else {
                continue
            }
            do {
                if let keyCombination = try decoder.decode(KeyCombination?.self, from: data) {
                    hotkey.keyCombination = keyCombination
                }
            } catch {
                diagLog.error("Error decoding hotkey: \(error)")
            }
        }
    }

    /// Configures the internal observers for the model.
    ///
    /// Callbacks are assigned after ``loadInitialState()``, so only later
    /// changes are persisted.
    private func configureObservers() {
        for hotkey in hotkeys {
            hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
                guard let self, let hotkey else { return }
                do {
                    // Remove cleared bindings; encoding the optional would
                    // store a dead `null` entry.
                    let data = try hotkey.keyCombination.map { try encoder.encode($0) }
                    withMutableCopy(of: Defaults.dictionary(forKey: .hotkeys) ?? [:]) { dictionary in
                        if let data {
                            dictionary[hotkey.action.rawValue] = data
                        } else {
                            dictionary.removeValue(forKey: hotkey.action.rawValue)
                        }
                        Defaults.set(dictionary, forKey: .hotkeys)
                    }
                } catch {
                    self.diagLog.error("Error encoding hotkey: \(error)")
                }
            }
        }
    }

    /// Returns the hotkey with the given action.
    func hotkey(withAction action: HotkeyAction) -> Hotkey? {
        hotkeys.first { $0.action == action }
    }
}
