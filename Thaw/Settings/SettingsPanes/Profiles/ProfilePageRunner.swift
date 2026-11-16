//
//  ProfilePageRunner.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Has the Profiles page's actions run: on the profiles themselves in the app's own window, by
/// the app when the page is in the settings process. Failures show through errorMessage.
@MainActor
struct ProfilePageRunner {
    /// Acts at once in the app. In the settings process only its profile list is used, as what undo is registered against.
    let performer: ProfilePagePerformer
    /// Nil in the app.
    var remote: SettingsRemote? = .current
    let undoManager: UndoManager?
    let errorMessage: Binding<String?>

    /// Runs action and hands what it left to then, or nil once its failure is on the page.
    /// In the app everything but an apply has run by the time this returns.
    func run(_ action: ProfilePageAction, then: @escaping (ProfilePageOutcome?) -> Void = { _ in /* Most actions show in the list. */ }) {
        guard let remote else { return runHere(action, then: then) }
        Task {
            do {
                let performed = try await ProfilesLink.run(action, via: remote)
                if let step = performed.undo, let name = performed.outcome.undoName {
                    // The app keeps the step. Undo and redo both name it.
                    registerUndo(step, named: name) { [errorMessage] step in
                        Self.attempt(errorMessage) { let _: Bool = try await remote.request(ProfilesLink.undo, step) }
                        return step
                    }
                }
                then(performed.outcome)
            } catch {
                errorMessage.wrappedValue = error.localizedDescription
                then(nil)
            }
        }
    }

    private func runHere(_ action: ProfilePageAction, then: @escaping (ProfilePageOutcome?) -> Void) {
        do {
            let done = try performer.perform(action)
            if let step = done.undo, let name = done.outcome.undoName {
                registerUndo(step, named: name) { [profileManager = performer.profileManager] in try $0.apply(to: profileManager) }
            }
            guard let applying = done.applying else { return then(done.outcome) }
            Task { await then(applying.value) }
        } catch {
            errorMessage.wrappedValue = error.localizedDescription
            then(nil)
        }
    }

    /// Makes a change to the profile list: at once in the app, by the app for the settings process.
    static func make(_ edit: ProfileListEdit, on profileManager: ProfileManager, remote: SettingsRemote?, errorMessage: Binding<String?>) {
        guard let remote else {
            do {
                try edit.apply(to: profileManager)
            } catch {
                errorMessage.wrappedValue = error.localizedDescription
            }
            return
        }
        // The edit shows in the list the app sends anyway, so only a failure comes back.
        attempt(errorMessage) { _ = try await ProfilesLink.run(.edit(edit), via: remote) }
    }

    /// Waits for the app's answer without holding up the page, and shows a failure when one comes.
    private static func attempt(_ errorMessage: Binding<String?>, _ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                errorMessage.wrappedValue = error.localizedDescription
            }
        }
    }

    /// Registers a finished edit's undo against the manager, so it outlives the page. apply runs
    /// a step and returns the one that reverses it, which becomes the redo.
    private func registerUndo<Step: Sendable>(_ step: Step, named name: String, apply: @escaping @MainActor (Step) throws -> Step) {
        Self.registerUndo(step, named: name, target: performer.profileManager, in: undoManager, errorMessage: errorMessage, apply: apply)
    }

    private static func registerUndo<Step: Sendable>(
        _ step: Step,
        named name: String,
        target: ProfileManager,
        in undoManager: UndoManager?,
        errorMessage: Binding<String?>,
        apply: @escaping @MainActor (Step) throws -> Step
    ) {
        guard let undoManager else { return }
        // The undo stack retains this handler; capture its manager weakly to avoid a cycle.
        undoManager.registerUndo(withTarget: target) { [weak undoManager] target in
            do {
                try registerUndo(apply(step), named: name, target: target, in: undoManager, errorMessage: errorMessage, apply: apply)
            } catch {
                errorMessage.wrappedValue = error.localizedDescription
            }
        }
        undoManager.setActionName(name)
    }
}
