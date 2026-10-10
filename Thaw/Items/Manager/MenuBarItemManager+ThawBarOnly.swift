//
//  MenuBarItemManager+ThawBarOnly.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import PlatformRuntimeKit

/// Thaw Bar Only items belong to Hidden in the controller.
/// This app-only state avoids adding a fourth section to the kit's shared names.
extension MenuBarItemManager {
    static let thawBarOnlyDefaultsKey = "MenuBarItemManager.thawBarOnlyItems"

    static func loadThawBarOnlyIdentifiers() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: thawBarOnlyDefaultsKey) ?? [])
    }

    private static func thawBarOnlyIdentifier(for item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }

    /// Disabled without clearing saved entries; surfaces use ordinary Hidden behavior.
    /// Restore by returning the setting below and uncommenting UI marked "Thaw Bar Only is unplugged".
    var isThawBarOnlyEnabled: Bool {
        // appState?.settings.general.enableThawBarOnly ?? true
        false
    }

    func isThawBarOnly(_ item: MenuBarItem) -> Bool {
        isThawBarOnlyEnabled && thawBarOnlyIdentifiers.contains(Self.thawBarOnlyIdentifier(for: item))
    }

    /// Every item in the Thaw Bar Only state, in saved order.
    var thawBarOnlyItems: [MenuBarItem] {
        guard !thawBarOnlyIdentifiers.isEmpty else { return [] }
        return itemCache.managedItems.filter(isThawBarOnly)
    }

    /// Offer undrawn Visible items for Thaw Bar Only; never move them without asking.
    var thawBarOnlySuggestions: [MenuBarItem] {
        guard isThawBarOnlyEnabled else { return [] }
        return itemsNotShownOnBar.filter { !isThawBarOnly($0) }
    }

    func moveToThawBarOnly(_ item: MenuBarItem, appState: AppState) {
        var identifiers = thawBarOnlyIdentifiers
        guard identifiers.insert(Self.thawBarOnlyIdentifier(for: item)).inserted else { return }
        thawBarOnlyIdentifiers = identifiers
        persistThawBarOnlyIdentifiers()
        MenuBarItemManager.diagLog.info("Moved \(item.logString) to Thaw Bar Only")
        if appState.menuBarManager.sectionController.section(for: item) == .visible {
            MenuBarSearchItemActions.move(item, to: .hidden, appState: appState)
        }
    }

    func returnFromThawBarOnly(_ item: MenuBarItem, to section: MenuBarSection.Name, appState: AppState) {
        var identifiers = thawBarOnlyIdentifiers
        guard identifiers.remove(Self.thawBarOnlyIdentifier(for: item)) != nil else { return }
        thawBarOnlyIdentifiers = identifiers
        persistThawBarOnlyIdentifiers()
        MenuBarItemManager.diagLog.info("Returned \(item.logString) from Thaw Bar Only to \(section.logString)")
        // A suggestion comes back only after the streak rebuilds.
        notShownStreaks[item.tag] = nil
        MenuBarSearchItemActions.move(item, to: section, appState: appState)
    }

    /// Follow renamed identifiers for entries and stand-ins using the section record's migration rule.
    /// Rename only with one live item and one missing entry per app; untitled siblings are ambiguous.
    func followRenamedThawBarOnlyItems() {
        guard !thawBarOnlyIdentifiers.isEmpty else { return }
        let renames = RuntimeSectionController.migratedSectionOrder(
            [.hidden: thawBarOnlyIdentifiers.sorted()],
            liveItems: itemCache.managedItems
        ).renames
        guard !renames.isEmpty else { return }
        var identifiers = thawBarOnlyIdentifiers
        for rename in renames where identifiers.remove(rename.from) != nil {
            identifiers.insert(rename.to)
            MenuBarItemManager.diagLog.info("Thaw Bar Only entry \(rename.from) now follows \(rename.to)")
        }
        thawBarOnlyIdentifiers = identifiers
        persistThawBarOnlyIdentifiers()
        appState?.thawBarOnlyProxies.follow(renames)
        appState?.itemStandInSlots.follow(renames)
    }

    /// Keep these items in Hidden: native app hiding uses section membership, not the assertion's conceal set.
    /// Visible membership would show the item beside its stand-in.
    func keepThawBarOnlyItemsHidden() {
        guard let appState else { return }
        for item in thawBarOnlyItems
            where appState.menuBarManager.sectionController.section(for: item) == .visible
        {
            let identifier = Self.thawBarOnlyIdentifier(for: item)
            guard thawBarOnlyItemsReturnedToHidden.insert(identifier).inserted else { continue }
            MenuBarItemManager.diagLog.info("Thaw Bar Only \(item.logString) was in Visible; moving it to Hidden")
            Task { @MainActor in
                MenuBarSearchItemActions.move(item, to: .hidden, appState: appState)
            }
        }
    }

    private func persistThawBarOnlyIdentifiers() {
        UserDefaults.standard.set(thawBarOnlyIdentifiers.sorted(), forKey: Self.thawBarOnlyDefaultsKey)
    }
}
