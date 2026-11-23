//
//  AutomaticZenRequests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Which automatic sources want Zen Mode, and which the user has overruled.
///
/// Sources reevaluate their signal on every poll rather than report edges, so a
/// repeated request is not a new one. A manual toggle declines the sources that
/// are asking at that moment until their signal ends.
struct AutomaticZenRequests {
    /// Zen stays engaged until the last automatic source clears, so presenting and recording cannot cancel each other.
    enum Reason: Sendable, Hashable {
        /// PresentationMonitor sees mirroring or screen sharing.
        case screenSharing
        /// RecordingWatchManager sees the camera or microphone in use.
        case recording
    }

    /// What Zen Mode should do after a request.
    enum Change: Equatable {
        case none
        case engage
        case withdraw
    }

    /// The sources currently asking for Zen Mode.
    private(set) var reasons: Set<Reason> = []

    /// Sources that were asking when the user toggled by hand; ignored until they clear.
    private var declined: Set<Reason> = []

    /// Only automatic engagements withdraw automatically; ending a recording or presentation cannot cancel manual zen.
    private var engagedAutomatically = false

    /// Records one source's current answer. Records reasons during manual zen too, but never withdraws a manual engagement.
    mutating func set(_ isActive: Bool, reason: Reason, isZenModeActive: Bool) -> Change {
        if isActive {
            guard !declined.contains(reason) else { return .none }
            reasons.insert(reason)
            guard !isZenModeActive else { return .none }
            engagedAutomatically = true
            return .engage
        }
        declined.remove(reason)
        reasons.remove(reason)
        guard isZenModeActive, engagedAutomatically, reasons.isEmpty else { return .none }
        engagedAutomatically = false
        return .withdraw
    }

    /// Manual ownership outlives automatic presentation or recording requests.
    mutating func takeManualOwnership() {
        engagedAutomatically = false
        declined.formUnion(reasons)
        reasons.removeAll()
    }
}
