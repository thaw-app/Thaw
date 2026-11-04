//
//  MenuBarItemManager+AbsentAppSiblings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

@MainActor
extension MenuBarItemManager {
    /// Runs a section change's commit, then under Native hiding moves the same apps'
    /// undrawn items to that section, so none left behind keeps an app on the bar.
    func commitKeepingAppsTogether(_ items: [MenuBarItem], to section: MenuBarSection.Name, _ commit: () -> Void) {
        commit()
        guard let menuBarManager = appState?.menuBarManager, menuBarManager.nativeAppHidingExperiment.isActive else { return }
        let controller = menuBarManager.sectionController
        let siblings = AbsentAppSiblings.identifiers(
            following: items,
            to: section,
            assignment: controller.sectionAssignment,
            liveIdentifiers: Set(managedItems.map(\.uniqueIdentifier))
        )
        guard !siblings.isEmpty else { return }
        for identifier in siblings {
            controller.setSection(section, identifier: identifier)
        }
        MenuBarItemManager.diagLog.info("Moved \(siblings) with their app to \(section.logString); they aren't on the bar")
    }
}
