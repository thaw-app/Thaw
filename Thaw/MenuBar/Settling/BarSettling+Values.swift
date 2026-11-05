//
//  BarSettling+Values.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension BarSettling {
    /// How authoritative a settle is, so a weaker one cannot tear down a stronger one in flight.
    nonisolated enum Kind: Equatable, Sendable {
        /// Thaw's own launch. Only another launch or a relaunch wait can replace it.
        case cold
        /// Holds restores off while a spacing wave runs. The wave's end can call it off.
        case preflight
        /// Waits out a display change or app launch. A spacing preflight joins it rather than
        /// replacing it, so a wave that does nothing cannot skip its post-settle restore.
        case event
        /// Waits for specific relaunched bundle IDs to reattach.
        case expectedSet
    }

    /// Something that moved or may move the bar. The labels are only for the log.
    nonisolated enum Disturbance: Equatable, Sendable {
        case thawLaunched
        /// An app with a tracked item launched; the settle waits for its item to reattach.
        case appLaunched(bundleID: String)
        /// The display arrangement changed. Its settle also waits for the bar to stop re-laying.
        case displayChanged(label: String)
        /// A spacing wave is about to run and may relaunch apps.
        case spacingWaveStarted(cause: String?)
        /// The wave relaunched apps; the settle waits for the named ones to reattach.
        case appsRelaunched(expecting: Set<String>, cause: String?)
        /// The wave relaunched nothing, failed or was cancelled, so its preflight may be called off.
        case spacingWaveEnded(cause: String?, outcome: WaveOutcome)
        /// The screens woke, and MenuBarAgent re-lays the bar after that.
        case screensWoke
        /// The display environment dropped its snapshot.
        case displaysInvalidated
        /// A read of the bar found items arriving or leaving, a frame mid-layout or a section revealed.
        case barLayoutShifted
        /// The revealed section changed, so the bar reflows for a moment.
        case revealedSectionChanged
        /// The kit started or finished laying out a reveal or hide.
        case revealTransition(active: Bool)
    }

    /// What a caller is about to do that a disturbed bar should hold off.
    nonisolated enum Purpose: Equatable, Sendable {
        /// Nudging MenuBarAgent to re-read item widths, which flickers while the bar is already reflowing.
        case agentNudge
    }

    /// Why a purpose is held off.
    nonisolated enum Hold: Equatable, Sendable {
        case revealReflow
        case revealTransition
    }

    nonisolated enum WaveOutcome: String, Sendable {
        case noOp
        case cancelled
        case error
    }

    /// One look at the cached items, taken after a fresh cache pass.
    nonisolated struct Sample: Equatable, Sendable {
        var managedCount = 0
        var unresolvedPIDs = 0
        /// Whether MenuBarAgent or BentoBox items are cached yet.
        var hostReady = false
        var bundleIDs: Set<String> = []
    }

    /// How a settle ended, for the work owed afterwards.
    nonisolated struct Ending: Equatable, Sendable {
        let disturbance: Disturbance
        /// Whether to read sections from the bar's stored weights: only after Thaw's own launch.
        let adoptsObservedMembership: Bool
        let hitDeadline: Bool
    }

    /// What the owner of the item cache does for a settle.
    struct Host {
        var awaitInitialRead: @MainActor () async -> Void
        var sample: @MainActor () async -> Sample
        /// Runs when a settle starts or replaces another, not when one yields.
        var didStart: @MainActor () -> Void
        /// Runs inside the settle's task, so settled() also waits for it.
        var didSettle: @MainActor (Ending) async -> Void

        /// Never settles before the deadline: with no items cached the count never holds.
        static let idle = Host(
            awaitInitialRead: { /* Nothing to wait for. */ },
            sample: { Sample() },
            didStart: { /* Nothing to call off. */ },
            didSettle: { _ in /* Nothing owed. */ }
        )
    }

    /// Where a count-stability settle stands between polls.
    nonisolated struct Streak: Equatable, Sendable {
        var lastSeenCount = -1
        var stablePolls = 0
    }

    nonisolated enum Verdict: Equatable, Sendable {
        case settled
        case waiting(Wait)
    }

    /// Why a poll did not settle, for the log.
    nonisolated enum Wait: Equatable, Sendable {
        case missing(Set<String>)
        case counting
        case countChanged(from: Int, to: Int)
        case minimumNotElapsed
        case hostNotReady
        case barNotQuiet
        /// The count held but source PIDs are still unresolved.
        case pidsUnresolved
    }
}

nonisolated extension BarSettling.Disturbance {
    /// The log label, matching the reason strings the settle used to be started with.
    var label: String {
        switch self {
        case .thawLaunched: "performSetup"
        case .appLaunched: "appLaunch"
        case let .displayChanged(label): label
        case let .spacingWaveStarted(cause): Self.spacingLabel(cause) + ":preflight"
        case let .appsRelaunched(_, cause): Self.spacingLabel(cause)
        case let .spacingWaveEnded(cause, outcome): Self.spacingLabel(cause) + ":\(outcome.rawValue)"
        case .screensWoke: "screensWoke"
        case .displaysInvalidated: "displaysInvalidated"
        case .barLayoutShifted: "barLayoutShifted"
        case .revealedSectionChanged: "revealedSectionChanged"
        case let .revealTransition(active): active ? "revealTransitionBegan" : "revealTransitionEnded"
        }
    }

    /// The settle this disturbance starts, or nil when it only moves a clock or ends a wave.
    var kind: BarSettling.Kind? {
        switch self {
        case .thawLaunched: .cold
        case .appLaunched, .displayChanged: .event
        case .spacingWaveStarted: .preflight
        // Its own IDs, not the shared set: a launch that yielded leaves its ID there,
        // and a preflight counting it would replace the launch settle.
        case let .appsRelaunched(expecting, _): expecting.isEmpty ? .preflight : .expectedSet
        case .spacingWaveEnded, .screensWoke, .displaysInvalidated, .barLayoutShifted, .revealedSectionChanged, .revealTransition: nil
        }
    }

    var expectedBundleIDs: Set<String> {
        switch self {
        case let .appLaunched(bundleID): [bundleID]
        case let .appsRelaunched(expecting, _): expecting
        default: []
        }
    }

    /// Generous, because some apps take tens of seconds to reattach. An app launch settles on one item.
    var maxDuration: Duration {
        if case .appLaunched = self {
            .seconds(8)
        } else {
            .seconds(60)
        }
    }

    var waitsForQuietBar: Bool {
        if case .displayChanged = self {
            true
        } else {
            false
        }
    }

    private static func spacingLabel(_ cause: String?) -> String {
        cause.map { "spacingRelaunch:\($0)" } ?? "spacingRelaunch"
    }
}
