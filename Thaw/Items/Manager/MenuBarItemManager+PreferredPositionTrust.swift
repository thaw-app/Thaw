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
    /// access cfprefsd refuses every read, so there is nothing to write.
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
            "Preferred-position write unverified (\(preferredPositionsIgnoredEvidence) this session)"
        )
    }

    /// Whether item is concealed, so the agent seats its written weight only at the next reveal
    /// (macOS 27.2) and polling now would just time out. A section crossing is still awaited.
    func preferredWriteAppliesOnReveal(
        _ item: MenuBarItem,
        to destination: MoveDestination,
        transitionSection: MenuBarSection.Name?
    ) -> Bool {
        guard transitionSection == nil, destination.sectionAcrossBoundary(from: item) == nil,
              let controller = appState?.menuBarManager.sectionController
        else { return false }
        let section = controller.section(for: item.uniqueIdentifier)
        guard section != .visible else { return false }
        let revealed = controller.revealedSection
        return !(revealed == section || (section == .hidden && revealed == .alwaysHidden))
    }
}
