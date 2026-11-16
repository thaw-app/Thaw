//
//  SettingsLink+ThawBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The Thaw Bar page's share of the link. Its settings are stored preferences both ends read again, and its
/// preview draws the mirrored items. The app opens the real bar and names the apps the bar leaves out.
@MainActor
enum ThawBarSettingsLink {
    /// Sent by the app: the apps switched off in System Settings, whose items the bar and its preview leave out.
    static let switchedOffApps = "thawBar.switchedOffApps"
    /// Asked of the app: open the real Thaw Bar.
    static let open = "thawBar.open"

    struct Open: Codable, Equatable {
        var section: MenuBarSection.Name
        var displayID: CGDirectDisplayID
        /// The settings process's display settings, which the app takes first, so the bar opens as the page shows it.
        var settings: DisplaySettingsManager.Snapshot
    }

    /// Opens the Thaw Bar's panel on a display.
    typealias Show = @MainActor (_ section: MenuBarSection.Name, _ displayID: CGDirectDisplayID) -> Void

    static func app(_ appState: AppState) -> SettingsAppFeature {
        app(
            displaySettings: appState.settings.displaySettings,
            hiding: appState.menuBarManager.nativeAppHidingExperiment,
            show: showsBar(of: appState)
        )
    }

    static func child(_ appState: AppState) -> SettingsChildFeature {
        child(hiding: appState.menuBarManager.nativeAppHidingExperiment)
    }

    static func app(
        displaySettings: DisplaySettingsManager,
        hiding: NativeAppHidingExperiment,
        show: @escaping Show
    ) -> SettingsAppFeature {
        SettingsAppFeature(
            statuses: [
                // Sorted, because a set's order is not the same from one encoding to the next.
                switchedOffApps: { SettingsLinkPayload.encode(hiding.userSwitchedOffBundleIDs.sorted()) },
            ],
            commands: [
                open: { payload in
                    guard let request = SettingsLinkPayload.decode(Open.self, from: payload) else { return }
                    displaySettings.adopt(request.settings)
                    show(request.section, request.displayID)
                },
            ]
        )
    }

    static func child(hiding: NativeAppHidingExperiment) -> SettingsChildFeature {
        SettingsChildFeature(statuses: [
            switchedOffApps: { payload in
                SettingsLinkPayload.decode([String].self, from: payload).map { hiding.mirrorUserSwitchedOffApps(Set($0)) }
            },
        ])
    }

    /// Opens this process's own bar, on a display that is connected.
    static func showsBar(of appState: AppState) -> Show {
        { [weak appState] section, displayID in
            guard let screen = NSScreen.screen(for: displayID) else { return }
            appState?.menuBarManager.thawBarPanel.show(section: section, on: screen)
        }
    }

    /// The page's button that opens the real bar. The bar is the app's, so the settings process has the app
    /// open it, and sends its display settings along so an edit made a moment ago shows in the bar.
    static func openBar(
        _ section: MenuBarSection.Name,
        on displayID: CGDirectDisplayID,
        settings: DisplaySettingsManager,
        remote: SettingsRemote? = .current,
        show: Show
    ) {
        guard let remote else { return show(section, displayID) }
        remote.perform(open, Open(section: section, displayID: displayID, settings: settings.snapshot))
    }

    /// Has the colour of the preview's display sampled again. Only the app reads the screen, through the item mirror.
    static func sampleColors(
        for displayID: CGDirectDisplayID,
        remote: SettingsRemote? = .current,
        here: @MainActor (CGDirectDisplayID) async -> Void
    ) async {
        guard let remote else { return await here(displayID) }
        remote.perform(SettingsItemsLink.sampleColors, displayID)
    }
}
