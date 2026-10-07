//
//  MenuBarItemManager+PreferredPositionTrust.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - Preferred-position trust

extension MenuBarItemManager {
    /// Whether the store path should be skipped for this move.
    ///
    /// On macOS 27 the table lives in a protected group container. Without
    /// access cfprefsd refuses every read, so go straight to the synthetic drag.
    var menuBarAgentIgnoresPreferredPositions: Bool {
        !positionsDomainAccessible
    }

    private var positionsDomainAccessible: Bool {
        let now = ContinuousClock.now
        if let cached = positionsDomainAccessCache,
           cached.at.duration(to: now) < Self.positionsDomainAccessTTL
        {
            return cached.value
        }
        let value = MenuBarPositionStoreProvider.current.positionsDomainIsAccessible()
        positionsDomainAccessCache = (value, now)
        return value
    }

    /// Opens a fresh convergence budget of visible drags after an authored
    /// pane edit commits.
    func noteAuthoredEditCommitted() {
        layoutPublication.invalidate()
        convergence.open()
    }

    /// Whether automatic ordering passes are paused because the last authored
    /// edit's convergence budget ran out, so visible drags do not drip on for
    /// minutes. See ``ConvergenceBudget``.
    func isConvergenceBudgetExhausted() -> Bool {
        switch convergence.verdict() {
        case .open:
            return false
        case .paused:
            return true
        case .pauseBegan:
            Self.diagLog.info(
                "macOS 27 convergence budget exhausted; automatic section-order passes pause for "
                    + "\(Int(ConvergenceBudget.pause.components.seconds)) s or until the next authored edit"
            )
            return true
        }
    }

    func loadPreferredPositionsVerdict() {
        // No persisted "agent ignores the store" verdict: AX bounds lag a
        // reorder, so one false positive would disable the store path for good.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.preferredPositionsIgnoredKey)
        defaults.removeObject(forKey: Self.preferredPositionsIgnoredBuildKey)
    }

    /// Records that a preferred-position write was not observed to move the bar.
    ///
    /// Diagnostic only: AX bounds lag a reorder, so successful writes can look
    /// ignored.
    func noteMenuBarAgentIgnoredPreferredPositions() {
        preferredPositionsIgnoredEvidence += 1
        MenuBarItemManager.diagLog.debug(
            "Preferred-position write unverified (\(preferredPositionsIgnoredEvidence) this session); falling back per move"
        )
    }
}

/// Items whose preferred-position writes MenuBarAgent keeps ignoring. Some
/// items are never laid out by their weight (seen for a helper without a
/// registered bundle), so every move paid the verification wait before its
/// drag. Whether the bar moved is no verdict: items with live-width titles
/// shift it all the time. After two unverified writes in a row the item goes
/// straight to the drag. A verified write clears it, and after ``retryAfter``
/// the write gets one more try.
struct IgnoredPreferredWrites {
    static let strikes = 2

    /// How long an item stays on the drag before its writes get one more try.
    /// The agent can start honouring an item again, after its app relaunches
    /// or the bar re-lays, and without a retry the item would stay on the
    /// drag, and out of every automatic move, for the rest of the session.
    static let retryAfter: Duration = .seconds(600)

    private struct Record {
        var count: Int
        var skipUntil: ContinuousClock.Instant?
    }

    private var records: [String: Record] = [:]

    func skipsWrite(for identifier: String, at now: ContinuousClock.Instant = .now) -> Bool {
        guard let skipUntil = records[identifier]?.skipUntil else { return false }
        return now < skipUntil
    }

    mutating func noteUnverified(_ identifier: String, at now: ContinuousClock.Instant = .now) {
        var record = records[identifier] ?? Record(count: 0)
        if let skipUntil = record.skipUntil, now >= skipUntil {
            // The retry failed too: one strike is enough to go back to the drag.
            record.count = Self.strikes - 1
        }
        record.count += 1
        record.skipUntil = record.count >= Self.strikes ? now + Self.retryAfter : nil
        records[identifier] = record
    }

    mutating func noteVerified(_ identifier: String) {
        records[identifier] = nil
    }
}
