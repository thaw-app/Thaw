//
//  MenuBarItemManager+Persistence.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

extension MenuBarItemManager {
    nonisolated struct NewItemsPlacement: Codable, Equatable {
        enum Relation: String, Codable {
            case leftOfAnchor
            case rightOfAnchor
            case sectionDefault
        }

        let sectionKey: String
        let anchorIdentifier: String?
        let relation: Relation

        static let defaultValue = NewItemsPlacement(
            sectionKey: Defaults.DefaultValue.newItemsSection,
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

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

        let storedSection = Defaults.string(forKey: .newItemsSection) ?? Defaults.DefaultValue.newItemsSection
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
        if let data = try? JSONEncoder().encode(placement) {
            Defaults.set(data, forKey: .newItemsPlacementData)
        } else {
            Defaults.removeObject(forKey: .newItemsPlacementData)
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
}
