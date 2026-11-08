//
//  SettingsPageModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Observation

/// One Settings page's model. Each persists its own properties under their
/// Defaults keys, so a setting moving between pages keeps its stored value.
@MainActor
protocol SettingsPageModel: AnyObject, Observable {}

extension SettingsPageModel {
    /// Calls onChange on the main actor for each change at keyPath, until
    /// the cancellable is cancelled. The current value is delivered first.
    func observe<Value: Equatable & Sendable>(
        _ keyPath: KeyPath<Self, Value>,
        onChange: @escaping @MainActor (Value) -> Void
    ) -> AnyCancellable {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let changes = Observations { self[keyPath: keyPath] }
            for await value in changes {
                onChange(value)
            }
        }
        return AnyCancellable { task.cancel() }
    }
}

/// A page model that takes thaw:// settings changes for its own keys.
@MainActor
protocol SettingsURIHandling: SettingsPageModel {
    /// Applies a thaw:// settings change if the key is one of this page's.
    func handleExternalSettingsChange(_ notification: Notification)
}

extension SettingsURIHandling {
    /// Applies a thaw:// change to the Bool or Double property its key names
    /// in this page's tables, leaving an unchanged value alone so observers
    /// only see real changes. Returns false for another page's key.
    @discardableResult
    func applySettingsURIChange(
        _ notification: Notification,
        bools: [String: ReferenceWritableKeyPath<Self, Bool>],
        doubles: [String: ReferenceWritableKeyPath<Self, Double>] = [:]
    ) -> Bool {
        guard let key = notification.userInfo?["key"] as? String else {
            return false
        }
        if let value = notification.userInfo?["value"] as? Bool, let keyPath = bools[key] {
            if self[keyPath: keyPath] != value {
                self[keyPath: keyPath] = value
            }
            return true
        }
        if let value = notification.userInfo?["doubleValue"] as? Double, let keyPath = doubles[key] {
            if self[keyPath: keyPath] != value {
                self[keyPath: keyPath] = value
            }
            return true
        }
        return false
    }

    /// Delivers thaw:// settings changes to handleExternalSettingsChange until cancelled.
    func subscribeToSettingsURIChanges() -> AnyCancellable {
        NotificationCenter.default
            .publisher(for: .settingsDidChangeViaURI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleExternalSettingsChange(notification)
            }
    }
}
