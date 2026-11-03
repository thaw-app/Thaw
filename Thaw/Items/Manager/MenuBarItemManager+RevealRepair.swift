//
//  MenuBarItemManager+RevealRepair.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

extension MenuBarItemManager {
    /// Runs before the reveal switches Native's apps back on, while they still read as hidden.
    func prepareReveal(cause: RepairOrchestrator.Cause) {
        if let menuBarManager = appState?.menuBarManager {
            menuBarManager.nativeAppHidingExperiment.noteRevealStarting(
                hiddenBundleIDs: menuBarManager.nativeHiddenBundleIDs,
                alreadyRevealed: menuBarManager.sectionController.revealedSection != nil
            )
        }
        applySavedOrderBeforeReveal(cause: cause)
    }

    /// Skips apps Native hiding switched back on for the reveal, and items whose last write
    /// MenuBarAgent ignored with nothing changed since.
    func revealRepairMoves(_ item: MenuBarItem, isMisplaced: Bool, logging: Bool = true) -> Bool {
        guard isMisplaced else { return false }
        guard RevealRepairDecision.shouldMove(
            method: currentHidingMethod,
            switchedOnForReveal: isSwitchedOnForReveal(item),
            isMisplaced: isMisplaced
        ) else {
            if logging {
                MenuBarItemManager.diagLog.debug("boundary repair: Native hiding switched \(item.logString) back on for the reveal; macOS places it")
            }
            return false
        }
        guard !failureLedger.ignoredPreferredWrites.skips(item.uniqueIdentifier, under: ignoredWriteCircumstances(for: item)) else {
            if logging {
                MenuBarItemManager.diagLog.debug("boundary repair: MenuBarAgent ignored the last write for \(item.logString) and nothing has changed; skipping")
            }
            return false
        }
        return true
    }

    /// Whether a reveal leaves the section's order to macOS: under Native hiding, a section holding an
    /// app switched back on for the reveal can't be put in order, since its writes are ignored.
    func revealLeavesOrderToMacOS(_ section: MenuBarSection.Name, items: [MenuBarItem]) -> Bool {
        guard let controller = appState?.menuBarManager.sectionController else { return false }
        return items.contains { item in
            controller.section(for: item) == section && !RevealRepairDecision.shouldMove(
                method: currentHidingMethod,
                switchedOnForReveal: isSwitchedOnForReveal(item),
                isMisplaced: true
            )
        }
    }

    /// Counts the ignored write against the move breaker, and remembers it so reveals stop retrying it.
    func noteIgnoredPreferredWrite(for item: MenuBarItem) {
        _ = moveCircuitBreaker.note(.failedVerification)
        failureLedger.ignoredPreferredWrites.noteIgnored(item.uniqueIdentifier, under: ignoredWriteCircumstances(for: item))
    }

    /// The method running now, which is Standard when Native is chosen but could not start.
    private var currentHidingMethod: HidingMethod {
        HidingMethod(nativeAppHidingEnabled: appState?.menuBarManager.nativeAppHidingExperiment.isActive == true)
    }

    private func isSwitchedOnForReveal(_ item: MenuBarItem) -> Bool {
        let switchedOn = appState?.menuBarManager.nativeAppHidingExperiment.switchedOnForReveal ?? []
        guard !switchedOn.isEmpty else { return false }
        if switchedOn.contains(item.tag.namespace.description) {
            return true
        }
        return item.sourceApplication?.bundleIdentifier.map(switchedOn.contains) == true
    }

    private func ignoredWriteCircumstances(for item: MenuBarItem) -> IgnoredPreferredWrites.Circumstances {
        IgnoredPreferredWrites.Circumstances(
            layout: appState?.menuBarManager.sectionController.sectionItemOrder ?? [:],
            frame: item.bounds,
            displayID: NSScreen.screenWithActiveMenuBar?.displayID ?? 0
        )
    }
}
