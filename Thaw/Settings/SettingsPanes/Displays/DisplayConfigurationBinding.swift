//
//  DisplayConfigurationBinding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension DisplaySettingsManager {
    /// Which saved configuration a settings control edits: one display's, or the template for new displays.
    enum ConfigurationTarget: Hashable {
        case display(String)
        case template
    }

    func configuration(for target: ConfigurationTarget) -> DisplayThawBarConfiguration {
        switch target {
        case let .display(uuid): configuration(forUUID: uuid)
        case .template: globalConfiguration
        }
    }

    /// A binding to one field of a display's or the template's configuration.
    /// A template edit never changes a display; a display edit goes through updateConfiguration(forDisplayUUID:).
    func binding<Value>(
        for target: ConfigurationTarget,
        _ keyPath: KeyPath<DisplayThawBarConfiguration, Value>,
        update: @escaping (DisplayThawBarConfiguration, Value) -> DisplayThawBarConfiguration
    ) -> Binding<Value> {
        Binding(
            get: { self.configuration(for: target)[keyPath: keyPath] },
            set: { newValue in
                switch target {
                case let .display(uuid):
                    self.updateConfiguration(forDisplayUUID: uuid) { update($0, newValue) }
                case .template:
                    self.globalConfiguration = update(self.globalConfiguration, newValue)
                }
            }
        )
    }
}
