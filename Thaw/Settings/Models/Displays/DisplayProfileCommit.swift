//
//  DisplayProfileCommit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A change the Displays page makes with the profiles that keep it: one display's spacing, or the template on every display.
/// It is a value so the settings process can hand it to the app, which owns the profiles.
struct DisplayProfileCommit: Codable, Equatable {
    enum Change: Codable, Equatable {
        case spacing(displayID: String, offset: Double)
        case template(DisplayThawBarConfiguration)
    }

    var change: Change
    /// The profiles that keep the change. Nil saves it to none.
    var scope: SpacingProfileSaveScope?
    /// The profile that was active when the page asked where to save.
    var activeProfileID: UUID?

    /// The display whose spacing the commit changes, or nil for the template.
    var displayID: String? {
        if case let .spacing(displayID, _) = change { displayID } else { nil }
    }

    /// Runs the commit here, or has the app run it when Settings is in its own process, and hands a failure to failed.
    /// The app gets this process's display settings with it, so an edit made a moment ago is not lost.
    func perform(on appState: AppState, remote: SettingsRemote? = .current, failed: @escaping (DisplayCommitFailure) -> Void) {
        guard let remote else {
            if let failure = failure(runningOn: appState) {
                failed(failure)
            }
            return
        }
        let settings = appState.settings.displaySettings
        let request = DisplaysSettingsLink.CommitRequest(commit: self, settings: settings.snapshot)
        // Immediate, so the request leaves before anything else the page sends.
        Task.immediate {
            do {
                let result: DisplaysSettingsLink.CommitResult = try await remote.request(DisplaysSettingsLink.commit, request)
                settings.adopt(result.settings)
                if let failure = result.failure {
                    failed(failure)
                }
            } catch {
                failed(DisplayCommitFailure(message: error.localizedDescription, displayID: displayID))
            }
        }
    }

    /// Runs the commit and returns why the profiles didn't keep it, when they didn't.
    func failure(runningOn appState: AppState) -> DisplayCommitFailure? {
        do {
            try run(on: appState)
            return nil
        } catch {
            return DisplayCommitFailure(message: error.localizedDescription, displayID: displayID)
        }
    }

    /// Makes the change first, because saving to the active profile captures the live settings.
    /// A save that fails puts the old settings back and throws, or the next profile apply would revert the change.
    func run(on appState: AppState) throws {
        let settings = appState.settings.displaySettings
        let undo: () -> Void
        switch change {
        case let .spacing(displayID, offset):
            let previous = settings.configuration(forUUID: displayID).itemSpacingOffset
            settings.updateConfiguration(forDisplayUUID: displayID) { $0.withItemSpacingOffset(offset) }
            undo = { settings.updateConfiguration(forDisplayUUID: displayID) { $0.withItemSpacingOffset(previous) } }
        case let .template(template):
            let previous = settings.configurations
            if settings.globalConfiguration != template {
                settings.globalConfiguration = template
            }
            settings.applyGlobalToAllKnownDisplays()
            undo = { settings.configurations = previous }
        }
        do {
            try save(from: appState)
        } catch {
            undo()
            throw error
        }
    }

    private func save(from appState: AppState) throws {
        let profiles = appState.profileManager
        switch (scope, change) {
        case (nil, _):
            break
        case (.activeProfile, _):
            guard let activeProfileID else { return }
            try profiles.updateProfile(id: activeProfileID, scope: .configurationOnly, appState: appState)
        case let (.allProfiles, .spacing(displayID, offset)):
            guard activeProfileID != nil else { return }
            try profiles.updateAllProfilesItemSpacingOffset(displayUUID: displayID, offset: offset)
        case (.allProfiles, .template):
            try profiles.updateAllProfilesGlobalConfiguration(
                appState.settings.displaySettings.globalConfiguration,
                propagateToDisplays: true
            )
        }
    }
}

/// A commit the profiles could not keep, for the Displays page to say.
struct DisplayCommitFailure: Codable, Equatable {
    var message: String
    /// The display whose spacing went back to what it was, when the commit was one display's spacing.
    var displayID: String?
}
