//
//  SettingsLink+Onboarding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The welcome and access window in the settings process. Finishing it launches Thaw, which only the
/// app may do, so the process hands the outcome to the app and closes the window when the app says so.
enum OnboardingLink {
    /// Asked of the app: finish the welcome or the access screen.
    static let finish = "onboarding.finish"

    struct Finish: Codable, Equatable {
        /// The welcome's choices, or nil for the access screen alone.
        var outcome: Outcome?
        /// The Settings pane the welcome opens on.
        var pane: String?
    }

    struct Outcome: Codable, Equatable {
        var simpleMode: Bool
        var automaticUpdates: Bool
    }

    struct Answer: Codable, Equatable {
        /// False when the app still lacks the access it needs and keeps asking for it.
        var closesWindow: Bool
    }

    static func app(_ appState: AppState) -> SettingsAppFeature {
        SettingsAppFeature(requests: [
            finish: { [weak appState] payload in
                guard let appState, let request = SettingsLinkPayload.decode(Finish.self, from: payload),
                      let answer = SettingsLinkPayload.encode(appState.completeFinish(request))
                else { throw SettingsRequestError.unreadable }
                return answer
            },
        ])
    }
}

extension AppState {
    /// Finishes the welcome, through the app when called in the settings process.
    func finishOnboarding(outcome: OnboardingOutcome, opening pane: SettingsNavigationIdentifier?) {
        finish(OnboardingLink.Finish(
            outcome: OnboardingLink.Outcome(simpleMode: outcome.simpleMode, automaticUpdates: outcome.automaticUpdates),
            pane: pane?.rawValue
        ))
    }

    /// Finishes the access screen, with access granted or Reduced mode chosen.
    func finishAccessRecovery() {
        finish(OnboardingLink.Finish())
    }

    private func finish(_ request: OnboardingLink.Finish) {
        guard SettingsProcessApp.isRequested else {
            _ = completeFinish(request)
            return
        }
        Task { [weak self] in
            // Settings, when finishing opens it, arrives before this answer, so the process always keeps a window.
            let answer: OnboardingLink.Answer? = try? await SettingsRemote.current?.request(OnboardingLink.finish, request)
            if answer?.closesWindow == true {
                self?.dismissWindow(.permissions)
            }
        }
    }

    /// The app's side: reads the access granted meanwhile, finishes, and says whether the window closes.
    func completeFinish(_ request: OnboardingLink.Finish) -> OnboardingLink.Answer {
        permissions.refreshPermissionsState()
        if let outcome = request.outcome {
            let pane = request.pane.flatMap(SettingsNavigationIdentifier.init(storedValue:))
            completeOnboarding(outcome: OnboardingOutcome(simpleMode: outcome.simpleMode, automaticUpdates: outcome.automaticUpdates), opening: pane)
        } else {
            completeFirstLaunchSetup()
        }
        return OnboardingLink.Answer(closesWindow: permissions.permissionsState != .missing || ReducedModeController.isChosen)
    }
}
