//
//  OnboardingSequencerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers permission-window stage precedence across all flags, replay requests, and stale tour versions.
@Suite("Onboarding sequencer")
struct OnboardingSequencerTests {
    private static let bools = [false, true]

    /// A literal keeps test cases stable when Constants.currentOnboardingVersion changes.
    private static let currentVersion = 2

    /// A stored version behind the current one, as an upgrader reports.
    private static let staleVersion = currentVersion - 1

    /// Combine three flags because Swift Testing accepts at most two argument collections.
    private static let allFlagCombinations: [(Bool, Bool, Bool)] = bools.flatMap { first in
        bools.flatMap { seen in
            bools.map { granted in (first, seen, granted) }
        }
    }

    /// Pair flags with both versions to prove replay overrides the version gate.
    private static let allFlagAndVersionCombinations: [(Bool, Bool, Bool, Int)] = allFlagCombinations.flatMap { flags in
        [staleVersion, currentVersion].map { seenVersion in
            (flags.0, flags.1, flags.2, seenVersion)
        }
    }

    @Test(
        "a replay request always yields onboarding, skipping access only when granted",
        arguments: allFlagAndVersionCombinations
    )
    func replayWinsOverEveryFlag(flags: (Bool, Bool, Bool, Int)) {
        let (hasCompletedFirstLaunch, hasSeenOnboarding, accessibilityGranted, seenVersion) = flags
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: hasCompletedFirstLaunch,
            hasSeenOnboarding: hasSeenOnboarding,
            accessibilityGranted: accessibilityGranted,
            seenOnboardingVersion: seenVersion,
            currentOnboardingVersion: Self.currentVersion,
            replayRequested: true
        )
        #expect(stage == .onboarding(skipsAccessStep: accessibilityGranted))
    }

    @Test(
        "an unfinished tour yields onboarding regardless of the first-launch flag",
        arguments: bools, bools
    )
    func unseenTourYieldsOnboarding(
        hasCompletedFirstLaunch: Bool,
        accessibilityGranted: Bool
    ) {
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: hasCompletedFirstLaunch,
            hasSeenOnboarding: false,
            accessibilityGranted: accessibilityGranted,
            seenOnboardingVersion: Self.currentVersion,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == .onboarding(skipsAccessStep: accessibilityGranted))
    }

    @Test(
        "a finished tour with the grant missing yields recovery",
        arguments: bools
    )
    func seenAndUngrantedYieldsRecovery(hasCompletedFirstLaunch: Bool) {
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: hasCompletedFirstLaunch,
            hasSeenOnboarding: true,
            accessibilityGranted: false,
            seenOnboardingVersion: Self.currentVersion,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == .recovery)
    }

    @Test(
        "a finished tour with the grant in place yields nothing to show",
        arguments: bools
    )
    func seenAndGrantedYieldsNone(hasCompletedFirstLaunch: Bool) {
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: hasCompletedFirstLaunch,
            hasSeenOnboarding: true,
            accessibilityGranted: true,
            seenOnboardingVersion: Self.currentVersion,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == .none)
    }

    @Test("replay defaults to off")
    func replayDefaultsToOff() {
        // Seen and granted distinguishes the default from replay.
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: true,
            hasSeenOnboarding: true,
            accessibilityGranted: true,
            seenOnboardingVersion: Self.currentVersion,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == .none)
    }

    // MARK: Upgraders

    @Test(
        "a finished tour at an older version yields onboarding with the access step skipped when granted",
        arguments: bools
    )
    func staleVersionAndGrantedYieldsOnboardingWithoutAccess(hasCompletedFirstLaunch: Bool) {
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: hasCompletedFirstLaunch,
            hasSeenOnboarding: true,
            accessibilityGranted: true,
            seenOnboardingVersion: Self.staleVersion,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == .onboarding(skipsAccessStep: true))
    }

    @Test(
        "a finished tour at an older version with the grant missing yields onboarding with the access step",
        arguments: bools
    )
    func staleVersionAndUngrantedYieldsOnboardingWithAccess(hasCompletedFirstLaunch: Bool) {
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: hasCompletedFirstLaunch,
            hasSeenOnboarding: true,
            accessibilityGranted: false,
            seenOnboardingVersion: Self.staleVersion,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == .onboarding(skipsAccessStep: false))
    }

    @Test("an install that predates the versioned flow reads as version zero and is welcomed once")
    func unversionedInstallIsAnUpgrader() {
        // Unversioned installs retain hasSeenOnboarding but read tour version as the integer default, 0.
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: true,
            hasSeenOnboarding: true,
            accessibilityGranted: true,
            seenOnboardingVersion: 0,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == .onboarding(skipsAccessStep: true))
    }

    @Test(
        "a finished tour at the current version behaves as before: recovery when ungranted, nothing when granted",
        arguments: bools
    )
    func currentVersionIsNotAnUpgrade(accessibilityGranted: Bool) {
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: true,
            hasSeenOnboarding: true,
            accessibilityGranted: accessibilityGranted,
            seenOnboardingVersion: Self.currentVersion,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == (accessibilityGranted ? .none : .recovery))
    }

    @Test(
        "a stored version ahead of the current one is not an upgrade",
        arguments: bools
    )
    func newerStoredVersionIsNotAnUpgrade(accessibilityGranted: Bool) {
        // A downgrade after trying a newer build should not replay the tour.
        let stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: true,
            hasSeenOnboarding: true,
            accessibilityGranted: accessibilityGranted,
            seenOnboardingVersion: Self.currentVersion + 1,
            currentOnboardingVersion: Self.currentVersion
        )
        #expect(stage == (accessibilityGranted ? .none : .recovery))
    }

    @Test("the first-launch flag never changes the answer on its own")
    func firstLaunchFlagIsInert() {
        for hasSeenOnboarding in Self.bools {
            for accessibilityGranted in Self.bools {
                for replayRequested in Self.bools {
                    for seenVersion in [Self.staleVersion, Self.currentVersion] {
                        let withFlag = OnboardingSequencer.stage(
                            hasCompletedFirstLaunch: true,
                            hasSeenOnboarding: hasSeenOnboarding,
                            accessibilityGranted: accessibilityGranted,
                            seenOnboardingVersion: seenVersion,
                            currentOnboardingVersion: Self.currentVersion,
                            replayRequested: replayRequested
                        )
                        let withoutFlag = OnboardingSequencer.stage(
                            hasCompletedFirstLaunch: false,
                            hasSeenOnboarding: hasSeenOnboarding,
                            accessibilityGranted: accessibilityGranted,
                            seenOnboardingVersion: seenVersion,
                            currentOnboardingVersion: Self.currentVersion,
                            replayRequested: replayRequested
                        )
                        #expect(
                            withFlag == withoutFlag,
                            "seen=\(hasSeenOnboarding) granted=\(accessibilityGranted) version=\(seenVersion) replay=\(replayRequested)"
                        )
                    }
                }
            }
        }
    }
}
