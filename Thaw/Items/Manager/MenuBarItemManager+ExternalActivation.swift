//
//  MenuBarItemManager+ExternalActivation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// What became of a request to open a menu bar item, for callers that have to
/// tell "request received" from "menu opened".
nonisolated enum MenuBarItemActivationOutcome: Equatable, Sendable {
    /// The press or click was delivered. reactionObserved is false for an item
    /// that acts without opening anything the verifier can see.
    case completed(reactionObserved: Bool)
    /// No live, actionable item has that identifier, such as a quit app's.
    case itemUnavailable
    /// Accessibility is not granted, so Thaw can neither see nor press items.
    case permissionMissing
    /// The item is there but no activation method got through to its owner.
    case activationFailed
}

extension MenuBarItemManager {
    /// The outcome already decided before anything is pressed, or nil to go ahead.
    /// Permission comes first: without it the cache is empty and every identifier reads as gone.
    nonisolated static func activationPreflight(
        hasAccessibilityPermission: Bool,
        itemIsLive: Bool
    ) -> MenuBarItemActivationOutcome? {
        guard hasAccessibilityPermission else { return .permissionMissing }
        guard itemIsLive else { return .itemUnavailable }
        return nil
    }

    /// The live item an external caller may activate by identifier: the same
    /// set the Shortcuts item picker offers.
    func externallyActionableItem(withIdentifier identifier: String) -> MenuBarItem? {
        managedItems.first { $0.uniqueIdentifier == identifier && $0.isUserActionable }
    }

    /// Opens the item through the shared activation path and waits for the result,
    /// unlike MenuBarManager.openItem(withIdentifier:). A nil displayID means the active menu bar's display.
    func activateItem(
        withIdentifier identifier: String,
        on displayID: CGDirectDisplayID? = nil
    ) async -> MenuBarItemActivationOutcome {
        guard let appState else { return .activationFailed }
        return await activateItem(
            withIdentifier: identifier,
            hasAccessibilityPermission: appState.permissions.accessibility.hasPermission
        ) { item in
            await self.activate(item: item, on: displayID ?? NSScreen.screenWithActiveMenuBar?.displayID)
        }
    }

    /// The decision around the press, with the permission and the press supplied by the caller.
    func activateItem(
        withIdentifier identifier: String,
        hasAccessibilityPermission: Bool,
        press: (MenuBarItem) async -> MenuBarItemActivationOutcome
    ) async -> MenuBarItemActivationOutcome {
        let item = externallyActionableItem(withIdentifier: identifier)
        if let decided = Self.activationPreflight(
            hasAccessibilityPermission: hasAccessibilityPermission,
            itemIsLive: item != nil
        ) {
            MenuBarItemManager.diagLog.info("Cannot activate item \(identifier): \(decided)")
            return decided
        }
        guard let item else { return .itemUnavailable }

        return await press(item)
    }
}
