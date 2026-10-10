//
//  MenuBarItemManager+VisibleControlDiagnostics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

extension MenuBarItemManager {
    func recordVisibleControlObservation(items: [MenuBarItem], displayID: CGDirectDisplayID) {
        let item = items.first { $0.tag.matchesVisibleControlItem }
        let placement = if let item {
            if item.bounds.minX == MenuBarItemGeometry.transientSentinelX {
                "blocked"
            } else if item.isParkedOffMenuBarBand(among: items) {
                "parked"
            } else {
                "on-bar"
            }
        } else {
            "not-enumerated"
        }
        // Record state transitions, not every frame change during a reflow.
        let state = "display=\(displayID) placement=\(placement) window=\(item?.windowID.description ?? "nil")"
        guard state != lastVisibleControlDiagnosticState else { return }
        lastVisibleControlDiagnosticState = state
        let axFrame = item.map { NSStringFromRect($0.bounds) } ?? "nil"
        Self.diagLog.info("VisibleControlLifecycle[observation] \(state) axFrame=\(axFrame)")
        recordVisibleControlHostState(reason: "observation")
    }

    func recordVisibleControlHostState(reason: String) {
        guard let appState,
              let control = appState.menuBarManager.controlItem(withName: .visible)
        else { return }
        let controller = appState.menuBarManager.sectionController
        Self.diagLog.info(
            "VisibleControlLifecycle[\(reason)] revealed=\(String(describing: controller.revealedSection)) " +
                "manual=\(arrangementIsManual) host={\(control.diagnosticStateDescription())}"
        )
    }
}
