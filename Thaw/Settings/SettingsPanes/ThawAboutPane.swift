//
//  ThawAboutPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The shared About page with Thaw's build, links and menu. Floe and the
/// community links sit in the actions' menu.
struct ThawAboutPane: View {
    let updatesManager: UpdatesManager
    @Environment(AppState.self) private var appState

    var body: some View {
        let appState = appState
        AboutSettingsPane(
            appName: "Thaw",
            version: AboutVersionDetails(
                version: Constants.versionString,
                build: Constants.buildString,
                commit: Constants.commitString,
                report: Constants.buildDescription
            ),
            links: AboutLinks(
                sourceCode: Constants.repositoryURL,
                reportBug: Constants.issuesURL,
                support: Constants.donateURL
            ),
            moreMenu: [
                [
                    AboutMenuItem("Frequent Issues", systemImage: "questionmark.circle", url: Constants.frequentIssuesURL),
                    AboutMenuItem("Show Welcome Screens Again", systemImage: "hand.wave") { appState.replayOnboarding() },
                ],
                [
                    AboutMenuItem("Join the Discord", systemImage: "bubble.left.and.bubble.right", url: Constants.discordURL),
                    AboutMenuItem("Help Translate", systemImage: "globe", url: Constants.translateURL),
                ],
                [
                    AboutMenuItem(LocalizedStringResource(stringLiteral: "Floe"), systemImage: "snowflake", url: Constants.floeURL),
                ],
            ],
            updates: AboutUpdateControls(
                model: updatesManager,
                channels: UpdateChannel.selectable,
                strings: .thaw
            ),
            copyright: Text(Constants.copyrightString),
            strings: .thaw,
            showWhatsNew: { appState.openWindow(.whatsNew) },
            showCredits: { appState.openWindow(.acknowledgements) }
        )
    }
}
