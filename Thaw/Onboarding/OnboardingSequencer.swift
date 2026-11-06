//
//  OnboardingSequencer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The one decision about what the permissions window shows when it opens.
///
/// One pure function so its three callers cannot disagree. The access step
/// rests on the live grant, never a stored flag, because a TCC grant survives
/// a defaults wipe.
///
/// The version comparison is for upgraders: the original Thaw set
/// hasSeenOnboarding under the same bundle identifier, with version 0.
nonisolated enum OnboardingSequencer {
    /// What the permissions window renders.
    enum Stage: Equatable, Sendable {
        /// The full onboarding sequence. skipsAccessStep is true when the
        /// required grant is already in place.
        case onboarding(skipsAccessStep: Bool)

        /// The standalone access screen for a user who finished onboarding
        /// earlier and has since lost the required grant.
        case recovery

        /// Nothing to show; the window should not have been opened.
        case none
    }

    /// Resolves the stage from the stored flags and the live grant.
    ///
    /// - Parameters:
    ///   - hasCompletedFirstLaunch: Accepted but never consulted: a completed
    ///     first launch without a finished tour still owes the user the tour.
    ///   - hasSeenOnboarding: Whether the user has finished the tour once,
    ///     under any version of it.
    ///   - accessibilityGranted: Whether the required grant is in place
    ///     right now, never a persisted value.
    ///   - seenOnboardingVersion: The tour version the user last finished;
    ///     0 for installs that predate the versioned flow.
    ///   - currentOnboardingVersion: The tour version this build ships,
    ///     normally Constants.currentOnboardingVersion.
    ///   - replayRequested: true when the user asked to see onboarding
    ///     again from Settings, which wins over every stored flag.
    static func stage(
        hasCompletedFirstLaunch _: Bool,
        hasSeenOnboarding: Bool,
        accessibilityGranted: Bool,
        seenOnboardingVersion: Int,
        currentOnboardingVersion: Int,
        replayRequested: Bool = false
    ) -> Stage {
        if replayRequested {
            return .onboarding(skipsAccessStep: accessibilityGranted)
        }
        let owesTour = !hasSeenOnboarding || seenOnboardingVersion < currentOnboardingVersion
        if owesTour {
            return .onboarding(skipsAccessStep: accessibilityGranted)
        }
        if !accessibilityGranted {
            return .recovery
        }
        return .none
    }
}
