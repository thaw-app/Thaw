//
//  SettingsLink+Profiles.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation
import ThawUI

/// The Profiles page's share of the link. The app owns the profiles: it sends the list and runs
/// everything the page does, so only one process ever writes the profile files.
@MainActor
enum ProfilesLink {
    /// Sent by the app: the profile list and each profile's shortcut.
    static let list = "profiles.list"
    /// Sent by the app: how one request ended.
    static let answer = "profiles.answer"
    /// Asked of the app: one action of the page, as a Request.
    static let perform = "profiles.perform"
    /// Asked of the app: undo or redo the edit an earlier request made, as an UndoRequest.
    static let undo = "profiles.undo"

    struct List: Codable, Equatable {
        var profiles: [ProfileMetadata]
        /// One for each profile the app has a hotkey for, in the list's order.
        var shortcuts: [Shortcut]
    }

    struct Shortcut: Codable, Equatable {
        var profile: UUID
        /// Nil while the profile has no shortcut, or the app isn't listening for it.
        var combination: KeyCombination?
    }

    /// An action with the number its answer comes back under.
    struct Request: Codable {
        var id: UUID
        var action: ProfilePageAction
    }

    struct UndoRequest: Codable, Equatable {
        var id: UUID
        /// The request that made the edit.
        var edit: UUID
    }

    struct Answer: Codable {
        var request: UUID
        var outcome: ProfilePageOutcome?
        /// The app's words for why the request failed.
        var failure: String?
    }

    static func app(_ appState: AppState) -> SettingsAppFeature {
        ProfilesAppLink(
            profileManager: appState.profileManager,
            performer: { [weak appState] in
                appState.map { ProfilePagePerformer(profileManager: $0.profileManager, appState: $0) }
            },
            send: { [weak appState] in appState?.settingsProcessHost.send(status: $0, payload: $1) }
        ).feature
    }

    /// What the settings process does with what the app sends for the Profiles page.
    static func child(profiles: ProfileManager, report: ProfilesAppReport = .shared) -> SettingsChildFeature {
        SettingsChildFeature(statuses: [
            list: { payload in
                guard let list = SettingsLinkPayload.decode(List.self, from: payload) else { return }
                profiles.mirror(list.profiles)
                report.show(list.shortcuts)
            },
            answer: { payload in
                if let answer = SettingsLinkPayload.decode(Answer.self, from: payload) {
                    report.received(answer)
                }
            },
        ])
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

// MARK: - In the app

/// The Profiles page's share of the link in the app: it sends the list, runs what the settings
/// process asks, and keeps each edit's undo step so the settings process only has to name the edit.
@MainActor
final class ProfilesAppLink {
    private let profileManager: ProfileManager
    /// Nil once the app's state has gone, when there is nothing left to act on.
    private let performer: () -> ProfilePagePerformer?
    private let send: (_ topic: String, _ payload: Data) -> Void
    /// The step that undoes the edit each request made or, once undone, that redoes it.
    private var undoSteps = [UUID: ProfileUndoStep]()
    /// The profiles whose shortcut stands down while the settings process records a new one.
    private var recording = Set<UUID>()

    init(
        profileManager: ProfileManager,
        performer: @escaping () -> ProfilePagePerformer?,
        send: @escaping (_ topic: String, _ payload: Data) -> Void
    ) {
        self.profileManager = profileManager
        self.performer = performer
        self.send = send
    }

    var feature: SettingsAppFeature {
        SettingsAppFeature(
            statuses: [ProfilesLink.list: { [profileManager] in SettingsLinkPayload.encode(Self.list(of: profileManager)) }],
            commands: [
                ProfilesLink.perform: { [self] in perform($0) },
                ProfilesLink.undo: { [self] in undo($0) },
            ],
            processEnded: { [self] in
                undoSteps = [:]
                // A recording the settings process never ended must not leave the shortcut off.
                recording.forEach { profileManager.profileHotkeys[$0]?.enable() }
                recording = []
            }
        )
    }

    private static func list(of profileManager: ProfileManager) -> ProfilesLink.List {
        let profiles = profileManager.profiles
        return ProfilesLink.List(profiles: profiles, shortcuts: profiles.compactMap { profile in
            profileManager.profileHotkeys[profile.id].map {
                ProfilesLink.Shortcut(profile: profile.id, combination: $0.isEnabled ? $0.keyCombination : nil)
            }
        })
    }

    private func perform(_ payload: Data) {
        guard let request = SettingsLinkPayload.decode(ProfilesLink.Request.self, from: payload), let performer = performer() else { return }
        do {
            let done = try performer.perform(request.action)
            undoSteps[request.id] = done.undo
            if case let .recordingShortcut(isRecording, profile) = request.action {
                recording = isRecording ? recording.union([profile]) : recording.subtracting([profile])
            }
            guard let applying = done.applying else { return answer(request.id, done.outcome) }
            // An apply answers once its layout has run, so the page's Apply buttons stay off until then.
            Task { await answer(request.id, applying.value) }
        } catch {
            fail(request.id, error)
        }
    }

    private func undo(_ payload: Data) {
        guard let request = SettingsLinkPayload.decode(ProfilesLink.UndoRequest.self, from: payload) else { return }
        // A step that failed is gone, so asking for it again changes nothing.
        guard let step = undoSteps.removeValue(forKey: request.edit) else { return answer(request.id, ProfilePageOutcome()) }
        do {
            undoSteps[request.edit] = try step.apply(to: profileManager)
            answer(request.id, ProfilePageOutcome())
        } catch {
            fail(request.id, error)
        }
    }

    private func answer(_ request: UUID, _ outcome: ProfilePageOutcome) {
        reply(ProfilesLink.Answer(request: request, outcome: outcome))
    }

    private func fail(_ request: UUID, _ error: any Error) {
        reply(ProfilesLink.Answer(request: request, failure: error.localizedDescription))
    }

    private func reply(_ answer: ProfilesLink.Answer) {
        if let payload = SettingsLinkPayload.encode(answer) {
            send(ProfilesLink.answer, payload)
        }
    }
}

// MARK: - In the settings process

/// In the settings process, what the running app says for the Profiles page: each profile's
/// shortcut, and how each request the page made ended.
@MainActor
@Observable
final class ProfilesAppReport {
    static let shared = ProfilesAppReport()

    private(set) var shortcuts = [ProfilesLink.Shortcut]()
    @ObservationIgnored
    private var waiting = [UUID: CheckedContinuation<ProfilesLink.Answer, Never>]()

    func show(_ shortcuts: [ProfilesLink.Shortcut]) {
        if self.shortcuts != shortcuts {
            self.shortcuts = shortcuts
        }
    }

    func received(_ answer: ProfilesLink.Answer) {
        waiting.removeValue(forKey: answer.request)?.resume(returning: answer)
    }

    /// Has the app run action and returns what it left. Throws a ProfilePageFailure with the
    /// app's words when it failed.
    func perform(_ action: ProfilePageAction, id: UUID = UUID(), via remote: SettingsRemote) async throws -> ProfilePageOutcome {
        try await answer(to: id) { remote.perform(ProfilesLink.perform, ProfilesLink.Request(id: id, action: action)) }
    }

    /// Has the app undo the edit that request made or, when it is undone, redo it.
    func undo(edit: UUID, via remote: SettingsRemote) async throws {
        let id = UUID()
        _ = try await answer(to: id) { remote.perform(ProfilesLink.undo, ProfilesLink.UndoRequest(id: id, edit: edit)) }
    }

    private func answer(to request: UUID, ask: () -> Void) async throws -> ProfilePageOutcome {
        let answer = await withCheckedContinuation { continuation in
            waiting[request] = continuation
            ask()
        }
        if let failure = answer.failure {
            throw ProfilePageFailure(message: failure)
        }
        return answer.outcome ?? ProfilePageOutcome()
    }
}
