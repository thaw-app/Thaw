//
//  SettingsLink+Displays.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// The Displays page's share of the link. The page's settings are stored preferences both ends
/// read again; the app also sends what only it knows, and makes the changes only it can make.
@MainActor
enum DisplaysSettingsLink {
    /// Sent by the app: a spacing apply's progress and its failure.
    static let spacingApply = "displays.spacingApply"
    /// Sent by the app: the active Space, the Spaces listed and whether the menu bar agent takes requests.
    static let spaces = "displays.spaces"
    /// Sent by the app: the active profile.
    static let activeProfile = "displays.activeProfile"
    /// Sent by the app after a commit: the display settings it left, and the failure if the profiles didn't keep it.
    static let commitResult = "displays.commitResult"
    /// Sent by the app: the answer to one presentation call.
    static let presentationAnswer = "displays.presentationAnswer"
    /// Asked of the app: a DisplayProfileCommit.
    static let commit = "displays.commit"
    /// Asked of the app: restart the menu bar apps so they read the saved spacing.
    static let reapplySpacing = "displays.reapplySpacing"
    /// Asked of the app: one request of the menu bar agent.
    static let presentation = "displays.presentation"

    struct SpacingApply: Codable, Equatable {
        var isReapplying: Bool
        var failure: String?
    }

    struct Spaces: Codable, Equatable {
        var active: CGSSpaceID
        /// Only tells the settings process to read the list again, which it can do itself.
        var listed: [CGSSpaceID]
        var takesPresentationRequests: Bool
    }

    struct ActiveProfile: Codable, Equatable {
        var id: UUID?
    }

    struct CommitRequest: Codable, Equatable {
        var commit: DisplayProfileCommit
        /// The settings process's display settings, which the app takes before it runs the commit.
        var settings: DisplaySettingsManager.Snapshot
    }

    struct CommitResult: Codable, Equatable {
        var settings: DisplaySettingsManager.Snapshot
        var failure: DisplayCommitFailure?
    }

    /// What the app sends and does for the Displays page. Answers go back through reply.
    static func app(
        _ appState: AppState,
        presentation: any MenuBarPresentationControlling = MenuBarPresentationProvider.current,
        reply: (@MainActor (_ topic: String, _ payload: Data) -> Void)? = nil
    ) -> SettingsAppFeature {
        let reply = reply ?? { [weak appState] in appState?.settingsProcessHost.send(status: $0, payload: $1) }
        func answer(_ topic: String, _ value: some Encodable) {
            if let payload = SettingsLinkPayload.encode(value) {
                reply(topic, payload)
            }
        }
        return SettingsAppFeature(
            statuses: [
                spacingApply: { [weak appState] in
                    guard let settings = appState?.settings.displaySettings else { return nil }
                    return SettingsLinkPayload.encode(SpacingApply(isReapplying: settings.isReapplyingSpacing, failure: settings.lastSpacingApplyFailure))
                },
                spaces: { [weak appState] in
                    guard let appState else { return nil }
                    return SettingsLinkPayload.encode(Spaces(
                        active: appState.activeSpace.spaceID,
                        listed: appState.spaceDirectory.spaces.map(\.spaceID),
                        takesPresentationRequests: presentation.isSupported
                    ))
                },
                activeProfile: { [weak appState] in
                    guard let appState else { return nil }
                    return SettingsLinkPayload.encode(ActiveProfile(id: appState.profileManager.activeProfileID))
                },
            ],
            commands: [
                commit: { [weak appState] payload in
                    guard let appState, let request = SettingsLinkPayload.decode(CommitRequest.self, from: payload) else { return }
                    answer(commitResult, run(request, on: appState))
                },
                reapplySpacing: { [weak appState] payload in
                    guard let displayID = SettingsLinkPayload.decode(String.self, from: payload) else { return }
                    appState?.settings.displaySettings.reapplySpacingConfirmedInSettingsProcess(forDisplayUUID: displayID)
                },
                Self.presentation: { payload in
                    guard let call = SettingsLinkPayload.decode(RemoteMenuBarPresentation.Call.self, from: payload) else { return }
                    Task {
                        let succeeded = await call.request.send(to: presentation)
                        answer(presentationAnswer, RemoteMenuBarPresentation.Answer(id: call.id, succeeded: succeeded))
                    }
                },
            ],
            reload: { [weak appState] in appState?.settings.displaySettings.loadStoredValues() }
        )
    }

    /// Takes the settings process's display settings, runs its commit and says what the settings are now.
    private static func run(_ request: CommitRequest, on appState: AppState) -> CommitResult {
        let settings = appState.settings.displaySettings
        settings.adopt(request.settings)
        var failure: DisplayCommitFailure?
        do {
            try request.commit.run(on: appState)
        } catch {
            failure = DisplayCommitFailure(message: error.localizedDescription, displayID: request.commit.displayID)
        }
        return CommitResult(settings: settings.snapshot, failure: failure)
    }

    /// What the settings process does with what the app sends for the Displays page: it sets the
    /// same objects the app's own window reads, so the page reads them as it does there.
    static func child(
        _ appState: AppState,
        presentation: RemoteMenuBarPresentation = .shared,
        reports: DisplayCommitReports = .shared
    ) -> SettingsChildFeature {
        let settings = appState.settings.displaySettings
        return SettingsChildFeature(
            statuses: [
                spacingApply: { payload in
                    guard let state = SettingsLinkPayload.decode(SpacingApply.self, from: payload) else { return }
                    assign(state.isReapplying, to: \.isReapplyingSpacing, of: settings)
                    assign(state.failure, to: \.lastSpacingApplyFailure, of: settings)
                },
                spaces: { payload in
                    guard let state = SettingsLinkPayload.decode(Spaces.self, from: payload) else { return }
                    assign(SpaceInfo(spaceID: state.active), to: \.activeSpace, of: appState)
                    appState.spaceDirectory.refresh()
                    // A choice made for a Space that wasn't listed yet is stored once it is.
                    appState.spaceMenuBarKeeper.resolvePending(in: appState.spaceDirectory.spaces)
                    assign(state.takesPresentationRequests, to: \.isSupported, of: presentation)
                },
                activeProfile: { payload in
                    guard let state = SettingsLinkPayload.decode(ActiveProfile.self, from: payload) else { return }
                    assign(state.id, to: \.activeProfileID, of: appState.profileManager)
                },
                commitResult: { payload in
                    guard let result = SettingsLinkPayload.decode(CommitResult.self, from: payload) else { return }
                    settings.adopt(result.settings)
                    if let failure = result.failure {
                        reports.failure = failure
                    }
                },
                presentationAnswer: { payload in
                    guard let answer = SettingsLinkPayload.decode(RemoteMenuBarPresentation.Answer.self, from: payload) else { return }
                    presentation.answer(answer)
                },
            ],
            reload: { settings.loadStoredValues() }
        )
    }

    /// Assigns only a value that differs, so whoever watches the object hears real changes alone.
    private static func assign<Root: AnyObject, Value: Equatable>(
        _ value: Value,
        to keyPath: ReferenceWritableKeyPath<Root, Value>,
        of root: Root
    ) {
        if root[keyPath: keyPath] != value {
            root[keyPath: keyPath] = value
        }
    }
}
