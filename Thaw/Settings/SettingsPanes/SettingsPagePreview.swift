//
//  SettingsPagePreview.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

#if DEBUG
    import Foundation
    import SwiftUI

    /// Only for the canvas: an app state for a settings page that is never started. It keeps
    /// settings, profiles, menu bar spacing and the settings link away from the Mac. A page's
    /// other actions still run, so read them before previewing a page with it.
    @MainActor
    enum SettingsPreviewApp {
        static let defaultSuiteName = "com.stonerl.Thaw.settings-previews"

        /// A folder in the temporary directory, emptied for each new app state.
        static var defaultProfilesDirectory: URL {
            FileManager.default.temporaryDirectory
                .appending(path: "ThawSettingsPreviews/Profiles", directoryHint: .isDirectory)
        }

        /// A link to an app that isn't there. With it a page acts as it does in the settings
        /// process: a save to the profiles, a color sample or a request to open the Thaw Bar goes
        /// over the link, which drops it, and a request counts as unanswered once its patience runs out.
        static let link = SettingsRemote { _ in /* Preview only: nothing listens. */ }

        /// Menu bar spacing kept nowhere, so the Mac's spacing is never read or written.
        static let spacingStore = SystemSpacingStore(read: { _ in nil }, write: { _, _ in /* Preview only. */ })

        /// Points settings, profiles, spacing and the settings link away from the Mac, then makes
        /// an app state. It is never started: starting it is what lets spacing relaunch apps and
        /// the menu bar be sampled.
        static func make(
            suiteName domain: String = defaultSuiteName,
            profilesDirectory: URL = defaultProfilesDirectory
        ) -> AppState {
            guard let store = UserDefaults(suiteName: domain) else {
                preconditionFailure("Could not create the settings preview preferences")
            }
            store.removePersistentDomain(forName: domain)
            Defaults.store = store
            SystemSpacingStore.current = spacingStore
            SettingsRemote.current = link
            try? FileManager.default.removeItem(at: profilesDirectory)
            let appState = ProfileManager.$directoryOverride.withValue(profilesDirectory) { AppState() }
            // A backstop: in write-only mode the spacing manager relaunches no app, whoever asks.
            appState.spacingManager.spacingApplyMode = .writeOnly
            return appState
        }
    }

    /// Draws a settings page as the Settings window shows it, against a preview app state.
    struct SettingsPagePreview<Page: View>: View {
        @State private var appState: AppState
        private let page: (AppState) -> Page

        init(
            suiteName: String = SettingsPreviewApp.defaultSuiteName,
            profilesDirectory: URL = SettingsPreviewApp.defaultProfilesDirectory,
            prepare: (AppState) -> Void = { _ in /* Nothing to add. */ },
            @ViewBuilder page: @escaping (AppState) -> Page
        ) {
            let appState = SettingsPreviewApp.make(suiteName: suiteName, profilesDirectory: profilesDirectory)
            prepare(appState)
            _appState = State(initialValue: appState)
            self.page = page
        }

        var body: some View {
            page(appState)
                .environment(appState)
                .environment(\.settingsPaneTitle, nil)
                .frame(width: 760, height: 720)
                .background(.windowBackground)
        }
    }
#endif
