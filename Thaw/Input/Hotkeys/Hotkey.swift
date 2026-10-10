//
//  Hotkey.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

// MARK: - Hotkey

/// Triggers actions from system-wide key-up or key-down events.
@MainActor
@Observable
final class Hotkey {
    fileprivate static nonisolated let diagLog = DiagLog(category: "Hotkey")
    var keyCombination: KeyCombination? {
        didSet {
            enable()
            keyCombinationDidChange?()
        }
    }

    /// Runs after the new keyCombination is stored and the listener is updated, allowing owners to persist changes.
    @ObservationIgnored
    var keyCombinationDidChange: (() -> Void)?

    private weak var appState: AppState?

    /// Manages the lifetime of the hotkey observation.
    private var listener: Listener?

    let action: HotkeyAction

    var isEnabled: Bool {
        listener != nil
    }

    init(action: HotkeyAction, keyCombination: KeyCombination? = nil) {
        self.action = action
        self.keyCombination = keyCombination
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        enable()
    }

    func enable() {
        disable()
        listener = Listener(hotkey: self, eventKind: .keyDown)
    }

    func disable() {
        listener?.invalidate()
        listener = nil
    }
}

// MARK: - Hotkey Listener

extension Hotkey {
    /// An object that manages the lifetime of a hotkey observation.
    private final class Listener {
        private weak var registry: HotkeyRegistry?
        private var id: UInt32?

        @MainActor
        init?(hotkey: Hotkey, eventKind: HotkeyRegistry.EventKind) {
            guard
                let appState = hotkey.appState,
                hotkey.keyCombination != nil
            else {
                return nil
            }
            let registry = appState.settings.hotkeys.registry
            let id = registry.register(hotkey: hotkey, eventKind: eventKind) { [weak hotkey, weak appState] in
                guard let hotkey, let appState else {
                    return
                }
                if hotkey.action == .profileApply {
                    guard appState.profileManager.layoutTask == nil else { return }
                    let key = ObjectIdentifier(hotkey)
                    if let profileID = appState.profileManager.hotkeyProfileMap[key],
                       profileID != appState.profileManager.activeProfileID
                    {
                        let profileManager = appState.profileManager
                        Task {
                            // Report failures so the hotkey does not appear unresponsive.
                            do {
                                let profile = try profileManager.loadProfile(id: profileID)
                                let previousID = profileManager.activeProfileID
                                profileManager.activeProfileID = profileID
                                profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
                            } catch {
                                Hotkey.diagLog.error("Could not apply profile \(profileID) from a hotkey: \(error)")
                                NSAlert(error: error).runModal()
                            }
                        }
                    }
                } else if hotkey.action == .openMenuBarItem {
                    let key = ObjectIdentifier(hotkey)
                    if let identifier = appState.menuBarManager.hotkeyItemMap[key] {
                        appState.menuBarManager.openItem(withIdentifier: identifier)
                    }
                } else {
                    hotkey.action.perform(appState: appState)
                }
            }
            guard let id else {
                return nil
            }
            self.registry = registry
            self.id = id
        }

        isolated deinit {
            invalidate()
        }

        func invalidate() {
            guard let id else {
                return
            }
            guard let registry else {
                Hotkey.diagLog.error("Error invalidating hotkey: missing HotkeyRegistry")
                return
            }
            defer {
                self.id = nil
            }
            registry.unregister(id)
        }
    }
}

// MARK: Hotkey: Equatable

extension Hotkey: @MainActor Equatable {
    static func == (lhs: Hotkey, rhs: Hotkey) -> Bool {
        lhs.keyCombination == rhs.keyCombination &&
            lhs.action == rhs.action
    }
}

// MARK: Hotkey: Hashable

extension Hotkey: @MainActor Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCombination)
        hasher.combine(action)
    }
}
