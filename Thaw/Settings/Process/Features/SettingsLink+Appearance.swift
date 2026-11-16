//
//  SettingsLink+Appearance.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// The Appearance page's share of the link. The settings process edits and saves the look. The
/// app draws it on the menu bar, follows the Spaces and shows the preview.
@MainActor
enum AppearanceSettingsLink {
    /// The status that says which menu bar the editor is editing.
    static let surroundings = "appearance.surroundings"
    /// The command that carries the look the settings process just saved, so the menu bar
    /// follows an edit at once instead of when the saved defaults are next read.
    static let look = "appearance.look"
    /// The command that shows a look on the menu bar for now, or stops showing one.
    static let preview = "appearance.preview"

    /// What the editor needs to know about the menu bar, which only the app follows.
    nonisolated struct Surroundings: Codable, Equatable {
        var activeSpaceID: CGSSpaceID
        var activeSpaceKey: String?
        /// Whether macOS hides the menu bar by itself, which leaves nothing to edit.
        var isMenuBarHiddenBySystem: Bool
    }

    /// The shared look and each Space's own, as they are saved.
    nonisolated struct Look: Codable, Equatable {
        var configuration: MenuBarAppearanceConfigurationV2
        var spaceOverrides: [String: MenuBarAppearanceConfigurationV2]
    }

    /// The look to show while the preview button is held, and none once it is let go.
    nonisolated struct Preview: Codable, Equatable {
        var configuration: MenuBarAppearancePartialConfiguration?
    }

    static func app(_ appState: AppState) -> SettingsAppFeature {
        app(appearance: appState.appearanceManager, menuBar: appState.menuBarManager)
    }

    static func child(_ appState: AppState) -> SettingsChildFeature {
        child(appearance: appState.appearanceManager, menuBar: appState.menuBarManager)
    }

    /// What the app does for the page: it says which menu bar is being edited, and shows each look the
    /// settings process saves or previews. The item mirror has it sample the bar's colours while the page is up.
    static func app(appearance: MenuBarAppearanceManager, menuBar: MenuBarManager) -> SettingsAppFeature {
        SettingsAppFeature(
            statuses: [
                surroundings: {
                    SettingsLinkPayload.encode(Surroundings(
                        activeSpaceID: appearance.activeSpaceID,
                        activeSpaceKey: appearance.activeSpaceKey,
                        isMenuBarHiddenBySystem: menuBar.isMenuBarHiddenBySystemUserDefaults
                    ))
                },
            ],
            commands: [
                look: { payload in
                    guard let look = SettingsLinkPayload.decode(Look.self, from: payload) else { return }
                    appearance.adopt(configuration: look.configuration, spaceOverrides: look.spaceOverrides)
                },
                preview: { payload in
                    guard let preview = SettingsLinkPayload.decode(Preview.self, from: payload) else { return }
                    appearance.previewConfiguration = preview.configuration
                },
            ],
            reload: { readSavedLook(into: appearance) },
            processEnded: {
                // A preview lasts while its button is held, and a process that has gone can't let go of it.
                if appearance.previewConfiguration != nil {
                    appearance.previewConfiguration = nil
                }
            }
        )
    }

    /// What the settings process does for the page. Its appearance manager is never set up, so
    /// the saved look is first read here, and each look saved from then on goes to the app.
    static func child(
        appearance: MenuBarAppearanceManager,
        menuBar: MenuBarManager,
        remote: @escaping @MainActor () -> SettingsRemote? = { .current }
    ) -> SettingsChildFeature {
        readSavedLook(into: appearance)
        appearance.onLookSaved = { [weak appearance] in
            guard let appearance else { return }
            remote()?.perform(look, Look(configuration: appearance.configuration, spaceOverrides: appearance.spaceOverrides))
        }
        return SettingsChildFeature(
            statuses: [
                surroundings: { payload in
                    guard let surroundings = SettingsLinkPayload.decode(Surroundings.self, from: payload) else { return }
                    appearance.mirrorActiveSpace(id: surroundings.activeSpaceID, key: surroundings.activeSpaceKey)
                    if menuBar.isMenuBarHiddenBySystemUserDefaults != surroundings.isMenuBarHiddenBySystem {
                        menuBar.isMenuBarHiddenBySystemUserDefaults = surroundings.isMenuBarHiddenBySystem
                    }
                },
            ],
            reload: { readSavedLook(into: appearance) }
        )
    }

    /// Has the manager take over the look as the defaults hold it now, after the other process
    /// wrote them. A key that was never saved or can't be read keeps what the manager has.
    static func readSavedLook(into appearance: MenuBarAppearanceManager) {
        appearance.adopt(
            configuration: saved(.menuBarAppearanceConfigurationV2) ?? appearance.configuration,
            spaceOverrides: saved(.menuBarAppearanceSpaceOverrides) ?? appearance.spaceOverrides
        )
    }

    private static func saved<Value: Decodable>(_ key: Defaults.Key) -> Value? {
        Defaults.data(forKey: key).flatMap { SettingsLinkPayload.decode(Value.self, from: $0) }
    }
}

extension MenuBarAppearanceManager {
    /// Shows a look on the real menu bar until nil clears it. The overlay that draws it is the
    /// app's, so the settings process asks the app to show it.
    func showPreview(_ configuration: MenuBarAppearancePartialConfiguration?, remote: SettingsRemote? = .current) {
        guard let remote else {
            previewConfiguration = configuration
            return
        }
        remote.perform(AppearanceSettingsLink.preview, AppearanceSettingsLink.Preview(configuration: configuration))
    }
}
