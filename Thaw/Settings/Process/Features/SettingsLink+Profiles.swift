//
//  SettingsLink+Profiles.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The Profiles page's share of the link. The app owns the profiles: it sends the list and runs
/// everything the page does, so only one process ever writes the profile files.
@MainActor
enum ProfilesLink {
    /// Sent by the app: the profile list.
    static let list = "profiles.list"
    /// Asked of the app: one ProfilePageAction, answered with a Performed.
    static let perform = "profiles.perform"
    /// Asked of the app: undo or redo the edit a Performed named, answered with whether the app still had it.
    static let undo = "profiles.undo"
    /// How long an apply is waited for. Restarting apps for spacing, the bar settling for up to a
    /// minute and the layout's moves can add up to about two minutes.
    static let applyPatience = Duration.seconds(180)

    /// What the app answers an action with.
    struct Performed: Codable {
        var outcome: ProfilePageOutcome
        /// The app's name for the step that undoes the action, when it kept one.
        var undo: UUID?
    }

    static func app(_ appState: AppState) -> SettingsAppFeature {
        ProfilesAppLink(profileManager: appState.profileManager) { [weak appState] in
            appState.map { ProfilePagePerformer(profileManager: $0.profileManager, appState: $0) }
        }.feature
    }

    /// What the settings process does with what the app sends for the Profiles page.
    static func child(profiles: ProfileManager) -> SettingsChildFeature {
        SettingsChildFeature(statuses: [
            list: { payload in
                SettingsLinkPayload.decode([ProfileMetadata].self, from: payload).map(profiles.mirror)
            },
        ])
    }

    /// Has the app run action and returns what it left. Throws the app's words when it failed.
    static func run(_ action: ProfilePageAction, via remote: SettingsRemote) async throws -> Performed {
        guard case .apply = action else { return try await remote.request(perform, action) }
        return try await remote.request(perform, action, patience: applyPatience)
    }
}

extension ProfileManager {
    /// Shows the app's profile list in the settings process, which never writes the list itself.
    func mirror(_ list: [ProfileMetadata]) {
        if profiles != list {
            profiles = list
        }
    }
}

/// The Profiles page's share of the link in the app: it sends the list, runs what the settings
/// process asks, and keeps each edit's undo step so the settings process only has to name it.
@MainActor
final class ProfilesAppLink {
    private let profileManager: ProfileManager
    /// Nil once the app's state has gone, when there is nothing left to act on.
    private let performer: () -> ProfilePagePerformer?
    /// The step that undoes each edit or, once undone, that redoes it, by the name the answer gave it.
    private var undoSteps = [UUID: ProfileUndoStep]()

    init(profileManager: ProfileManager, performer: @escaping () -> ProfilePagePerformer?) {
        self.profileManager = profileManager
        self.performer = performer
    }

    var feature: SettingsAppFeature {
        SettingsAppFeature(
            statuses: [ProfilesLink.list: { [profileManager] in SettingsLinkPayload.encode(profileManager.profiles) }],
            requests: [
                ProfilesLink.perform: { [self] in try await perform($0) },
                ProfilesLink.undo: { [self] in try undo($0) },
            ],
            processEnded: { [self] in undoSteps = [:] }
        )
    }

    private func perform(_ payload: Data) async throws -> Data {
        guard let action = SettingsLinkPayload.decode(ProfilePageAction.self, from: payload), let performer = performer() else {
            throw SettingsRequestError.unreadable
        }
        let done = try performer.perform(action)
        var performed = ProfilesLink.Performed(outcome: done.outcome)
        if let step = done.undo {
            let name = UUID()
            undoSteps[name] = step
            performed.undo = name
        }
        // An apply answers once its layout has run, so the page's Apply buttons stay off until then.
        if let applying = done.applying {
            performed.outcome = await applying.value
        }
        return SettingsLinkPayload.encode(performed) ?? Data()
    }

    private func undo(_ payload: Data) throws -> Data {
        // A step that failed is gone, so asking for it again changes nothing.
        let name = SettingsLinkPayload.decode(UUID.self, from: payload)
        guard let name, let step = undoSteps.removeValue(forKey: name) else { return SettingsLinkPayload.encode(false) ?? Data() }
        undoSteps[name] = try step.apply(to: profileManager)
        return SettingsLinkPayload.encode(true) ?? Data()
    }
}
