//
//  MenuBarItemManager+Persistence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import MenuBarModel
import ThawLayout

extension MenuBarItemManager {
    /// Lives in the ThawLayout package; the alias keeps MenuBarItemManager.NewItemsPlacement working.
    typealias NewItemsPlacement = ThawLayout.NewItemsPlacement

    func loadKnownItemIdentifiers() {
        let key = "MenuBarItemManager.knownItemIdentifiers"
        let defaults = UserDefaults.standard
        if let stored = defaults.array(forKey: key) as? [String] {
            knownItemIdentifiers = Set(stored.map(MenuBarItemTag.canonicalPersistentIdentifier))
        }
    }

    func persistKnownItemIdentifiers() {
        let key = "MenuBarItemManager.knownItemIdentifiers"
        let defaults = UserDefaults.standard
        defaults.set(
            Array(Set(knownItemIdentifiers.map(MenuBarItemTag.canonicalPersistentIdentifier))),
            forKey: key
        )
    }

    /// Compares one settled inventory with the apps that hosted items last
    /// session, and publishes the ones still missing.
    func noteUnseenMenuBarHosts(in cache: ItemCache) {
        guard !isInStartupSettling, !areControlItemsMissing else { return }
        let key = UnseenMenuBarHosts.defaultsKey
        let defaults = UserDefaults.standard
        var tracker = unseenHosts
            ?? UnseenMenuBarHosts(expected: defaults.dictionary(forKey: key) as? [String: Int] ?? [:])

        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        func isTracked(_ bundle: String) -> Bool {
            !bundle.hasPrefix("com.apple.") && !bundle.hasPrefix(ourBundleID)
        }
        let runningApps = NSWorkspace.shared.runningApplications
        let bundlesByPID = Dictionary(
            runningApps.compactMap { app in app.bundleIdentifier.map { (app.processIdentifier, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let seen = Set(cache.managedItems.compactMap { item in
            bundlesByPID[item.sourcePID ?? item.ownerPID]
        }.filter(isTracked))
        // Natively hidden apps publish nothing on purpose.
        let nativelyHidden = appState?.menuBarManager.nativeHiddenBundleIDs ?? []
        let running = Set(bundlesByPID.values.filter(isTracked)).subtracting(nativelyHidden)

        // An app switched off in System Settings, or one that answers with no items, is not being missed.
        let candidates = tracker.candidates(seen: seen, running: running)
        let answeredEmpty = MenuBarItemAXProvider.processesAnsweringWithNoItems()
        let quiet = MenuBarAllowState.switchedOff(among: candidates)
            .union(answeredEmpty.compactMap { bundlesByPID[$0] })

        if tracker.update(seen: seen, running: running, quiet: quiet, now: .now) {
            let flagged = tracker.flagged
            if !flagged.isEmpty {
                MenuBarItemManager.diagLog.warning(
                    "menu bar items expected from running apps are not visible to the walk: \(flagged.sorted())"
                )
            }
            unseenHostBundleIDs = flagged
        }
        unseenHosts = tracker

        let persisted = tracker.persisted()
        if persisted != lastPersistedExpectedHosts {
            defaults.set(persisted, forKey: key)
            lastPersistedExpectedHosts = persisted
        }
    }

    func loadPinnedBundleIDs() {
        let defaults = UserDefaults.standard
        if let hidden = defaults.array(forKey: "MenuBarItemManager.pinnedHiddenBundleIDs") as? [String] {
            pinnedHiddenBundleIDs = Set(hidden)
        }
        if let alwaysHidden = defaults.array(forKey: "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs") as? [String] {
            pinnedAlwaysHiddenBundleIDs = Set(alwaysHidden)
        }
    }

    func persistPinnedBundleIDs() {
        let defaults = UserDefaults.standard
        defaults.set(Array(pinnedHiddenBundleIDs), forKey: "MenuBarItemManager.pinnedHiddenBundleIDs")
        defaults.set(Array(pinnedAlwaysHiddenBundleIDs), forKey: "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs")
    }

    func loadSavedSectionOrder() {
        let key = "MenuBarItemManager.savedSectionOrder"
        if let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] {
            savedSectionOrder = Self.canonicalizedSectionOrder(stored)
        }
    }

    func loadNewItemsPlacementPreference() {
        if let data = Defaults.data(forKey: .newItemsPlacementData),
           let stored = try? JSONDecoder().decode(NewItemsPlacement.self, from: data)
        {
            newItemsPlacement = NewItemsPlacement(
                sectionKey: stored.sectionKey,
                anchorIdentifier: stored.anchorIdentifier.map(MenuBarItemTag.canonicalPersistentIdentifier),
                relation: stored.relation
            )
            return
        }

        let storedSection = Defaults.string(forKey: .newItemsSection) ?? ""
        let resolvedSection = sectionName(for: storedSection) ?? .hidden
        newItemsPlacement = NewItemsPlacement(
            sectionKey: sectionKey(for: resolvedSection),
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

    func persistNewItemsPlacementPreference() {
        Defaults.set(newItemsPlacement.sectionKey, forKey: .newItemsSection)
        let placement = NewItemsPlacement(
            sectionKey: newItemsPlacement.sectionKey,
            anchorIdentifier: newItemsPlacement.anchorIdentifier.map(MenuBarItemTag.canonicalPersistentIdentifier),
            relation: newItemsPlacement.relation
        )
        do {
            let data = try JSONEncoder().encode(placement)
            Defaults.set(data, forKey: .newItemsPlacementData)
        } catch {
            // Keep the last placement that encoded rather than clearing a
            // working preference.
            MenuBarItemManager.diagLog.error("Could not encode the New Items placement; keeping the stored one: \(error)")
        }
    }

    func persistSavedSectionOrder() {
        let key = "MenuBarItemManager.savedSectionOrder"
        savedSectionOrder = Self.canonicalizedSectionOrder(savedSectionOrder)
        UserDefaults.standard.set(savedSectionOrder, forKey: key)
    }

    private static func canonicalizedSectionOrder(
        _ order: [String: [String]]
    ) -> [String: [String]] {
        order.mapValues(MenuBarItemTag.canonicalPersistentIdentifiers)
    }

    /// Drops only _NS:<number> titles, which AppKit regenerates on every
    /// relaunch, so they never match again.
    ///
    /// Unresolvable owners are kept: helpers may be inner bundles
    /// LaunchServices never indexes, and absence from one walk proves nothing.
    /// Quit apps and non-bundle owners are kept too.
    func pruneSavedSectionOrderGhosts() {
        var removed: [String] = []
        savedSectionOrder = savedSectionOrder.mapValues { identifiers in
            identifiers.filter { identifier in
                guard let separator = identifier.firstIndex(of: ":") else {
                    return true
                }
                let title = identifier[identifier.index(after: separator)...]
                if title.contains(/^_NS:\d+$/) {
                    removed.append(identifier)
                    return false
                }
                return true
            }
        }
        guard !removed.isEmpty else { return }
        MenuBarItemManager.diagLog.info(
            "pruneSavedSectionOrderGhosts: removed \(removed.count) unreachable entries: \(removed.joined(separator: ", "))"
        )
        persistSavedSectionOrder()
    }
}
