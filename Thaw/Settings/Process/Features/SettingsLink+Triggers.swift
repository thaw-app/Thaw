//
//  SettingsLink+Triggers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

extension SettingsChildFeature {
    /// The Triggers page's share in the settings process. The page saves its choice to the
    /// defaults, which the app reads at each capture, so the app has no share of its own.
    static func triggers(_ appState: AppState) -> SettingsChildFeature {
        triggers(choices: appState.alertRevealWatcher.choices)
    }

    /// The page's list follows the choice the app saved, and learns when the app's items are here.
    static func triggers(choices: AlertRevealChoices) -> SettingsChildFeature {
        SettingsChildFeature(
            statuses: [
                // The item mirror shows the list. The page only has to know that it has come.
                SettingsItemsLink.cache: { payload in
                    guard !choices.hasAppItems, SettingsLinkPayload.decode(MenuBarItemCache.self, from: payload) != nil else { return }
                    choices.appItemsArrived()
                },
            ],
            reload: { choices.reload() }
        )
    }
}
