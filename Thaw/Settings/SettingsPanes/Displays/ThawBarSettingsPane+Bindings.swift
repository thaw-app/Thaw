//
//  ThawBarSettingsPane+Bindings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The pane's per-context bindings, moved here from ThawBarSettingsPane.swift so
/// that file stays under SwiftLint's type body limit.
extension ThawBarSettingsPane {
    func useThawBarBinding(for context: EditingContext) -> Binding<Bool> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).useThawBar },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withUseThawBar(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.useThawBar },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withUseThawBar(newValue)
                }
            )
        }
    }

    func locationBinding(for context: EditingContext) -> Binding<ThawBarLocation> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).thawBarLocation },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withThawBarLocation(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.thawBarLocation },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withThawBarLocation(newValue)
                }
            )
        }
    }

    func layoutBinding(for context: EditingContext) -> Binding<ThawBarLayout> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).thawBarLayout },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withThawBarLayout(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.thawBarLayout },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withThawBarLayout(newValue)
                }
            )
        }
    }

    func gridColumnsBinding(for context: EditingContext) -> Binding<Int> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).gridColumns },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withGridColumns(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.gridColumns },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withGridColumns(newValue)
                }
            )
        }
    }

    func alwaysShowHiddenItemsBinding(for context: EditingContext) -> Binding<Bool> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).alwaysShowHiddenItems },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withAlwaysShowHiddenItems(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.alwaysShowHiddenItems },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withAlwaysShowHiddenItems(newValue)
                }
            )
        }
    }

    func itemScaleBinding(for context: EditingContext) -> Binding<Double> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).thawBarItemScale },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withThawBarItemScale(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.thawBarItemScale },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withThawBarItemScale(newValue)
                }
            )
        }
    }
}
