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
        convergenceBudgetDeadline = .now + Self.convergenceBudget
        convergenceSuppressedUntil = nil
    }

    /// Whether automatic ordering passes are paused because the last authored
    /// edit's convergence budget ran out, so visible drags do not drip on for
    /// minutes. The next authored edit reopens the budget.
    func isConvergenceBudgetExhausted() -> Bool {
        guard let deadline = convergenceBudgetDeadline else { return false }
        let now = ContinuousClock.now
        if now < deadline {
            return false
        }
        if let suppressedUntil = convergenceSuppressedUntil, now < suppressedUntil {
            return true
        }
        convergenceSuppressedUntil = now + Self.convergencePostExpirySuppression
        Self.diagLog.info(
            "macOS 27 convergence budget exhausted; automatic section-order passes pause for " +
                "\(Int(Self.convergencePostExpirySuppression.components.seconds)) s or until the next authored edit"
        )
        return true
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
/// straight to the drag; a verified write clears it.
struct IgnoredPreferredWrites {
    static let strikes = 2

    private var counts: [String: Int] = [:]

    func skipsWrite(for identifier: String) -> Bool {
        counts[identifier, default: 0] >= Self.strikes
    }

    mutating func noteUnverified(_ identifier: String) {
        counts[identifier, default: 0] += 1
    }

    mutating func noteVerified(_ identifier: String) {
        counts[identifier] = nil
    }
}
