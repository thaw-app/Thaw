//
//  HotkeysSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel

/// Model for the app's Hotkeys settings.
@MainActor
@Observable
final class HotkeysSettings {
    @ObservationIgnored
    private let diagLog = DiagLog(category: "HotkeysSettings")
    /// The app's hotkey registry.
    let registry = HotkeyRegistry()

    /// The failure from the last shortcut that could not be written, or nil.
    ///
    /// Parked here because the change callback cannot throw; otherwise the
    /// recorder shows a shortcut that is gone after the next launch.
    private(set) var lastPersistenceError: String?

    /// Clears the pending failure once the pane has reported it.
    func clearPersistenceError() {
        lastPersistenceError = nil
    }

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

    /// Storage for internal observers.
    ///
    /// Hotkey is still a Combine ObservableObject, so the persistence
    /// pipeline over each hotkey's $keyCombination stays Combine-based
    /// even though this model itself is @Observable.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    @ObservationIgnored
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        for hotkey in hotkeys {
            hotkey.performSetup(with: appState)
        }
        loadInitialState()
        configureCancellables()
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

    /// Persists each hotkey's key combination when it changes.
    ///
    /// The callback only fires for changes made after it is assigned, so the
    /// just-loaded value is not persisted again.
    private func configureCancellables() {
        for hotkey in hotkeys {
            hotkey.keyCombinationDidChange = { [weak self, weak hotkey] in
                guard let self, let hotkey else { return }
                do {
                    // A cleared binding removes the key; encoding the optional
                    // would store a dead JSON null.
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
                    diagLog.error("Error encoding hotkey: \(error)")
                    lastPersistenceError = error.localizedDescription
                }
            }
        }
    }

    /// Returns the hotkey with the given action.
    func hotkey(withAction action: HotkeyAction) -> Hotkey? {
        hotkeys.first { $0.action == action }
    }
}
