//
//  MenuBarItemManager+ItemCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - Item Cache

extension MenuBarItemManager {
    /// Owns the menu bar item cache's cycle-to-cycle state.
    ///
    /// Not an actor despite the name: @MainActor confinement is what makes the
    /// unsynchronized properties safe.
    final class CacheActor {
        /// Window identifiers at the time of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// Confirmed window/source incarnations from the previous cache cycle.
        /// These detect and correct transient source-PID resolution errors
        /// without trusting a recycled window ID or PID by itself.
        private(set) var cachedSourcePIDBaselines = [CGWindowID: SourcePIDSeed]()

        /// System clone windows from the last cycle. Filtered out of change
        /// detection so a transient clone doesn't trigger a recache.
        private(set) var cachedCloneWindowIDs = Set<CGWindowID>()

        /// Control Center generic (Item-N) windows from the last cycle. Live
        /// Activities churn their windowIDs, so their disappearance doesn't
        /// trigger a bulk apply (#736).
        private(set) var cachedControlCenterGenericWindowIDs = Set<CGWindowID>()

        /// Source-PID seeds already written during this app session.
        private(set) var persistedSourcePIDSeeds: [SourcePIDSeed]?

        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        func updateCachedCloneWindowIDs(_ ids: Set<CGWindowID>) {
            cachedCloneWindowIDs = ids
        }

        func updateCachedControlCenterGenericWindowIDs(_ ids: Set<CGWindowID>) {
            cachedControlCenterGenericWindowIDs = ids
        }

        func updateCachedSourcePIDBaselines(_ baselines: [CGWindowID: SourcePIDSeed]) {
            cachedSourcePIDBaselines = baselines
        }

        /// Records a seed snapshot and reports whether it needs persistence.
        func updatePersistedSourcePIDSeeds(_ seeds: [SourcePIDSeed]) -> Bool {
            guard seeds != persistedSourcePIDSeeds else { return false }
            persistedSourcePIDSeeds = seeds
            return true
        }

        /// Loads the persisted snapshot once per process, which avoids a
        /// redundant defaults write on the first enumeration.
        func persistedSourcePIDSeeds(from defaults: UserDefaults) -> [SourcePIDSeed] {
            if let persistedSourcePIDSeeds {
                return persistedSourcePIDSeeds
            }
            let loaded = SourcePIDSeedStore.load(from: defaults).values.sorted {
                $0.windowID < $1.windowID
            }
            persistedSourcePIDSeeds = loaded
            return loaded
        }

        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
            cachedSourcePIDBaselines.removeAll()
            // Stale clone IDs could filter a recycled windowID out of change detection.
            cachedCloneWindowIDs.removeAll()
            cachedControlCenterGenericWindowIDs.removeAll()
        }
    }

    struct ItemCache: Hashable {
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section]
        }

        func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(matching: tag) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination) {
            let targetTag = destination.targetItem.tag

            if targetTag == .hiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.hidden].append(item)
                case .rightOfItem:
                    self[.visible].insert(item, at: 0)
                }
                return
            }

            if targetTag == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.alwaysHidden].append(item)
                case .rightOfItem:
                    self[.hidden].insert(item, at: 0)
                }
                return
            }

            guard case (let section, var index)? = address(for: targetTag) else {
                return
            }

            if case .rightOfItem = destination {
                let range = self[section].startIndex ... self[section].endIndex
                index = (index + 1).clamped(to: range)
            }

            self[section].insert(item, at: index)
        }

        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
        let hiddenControlItemBounds: CGRect
        let alwaysHiddenControlItemBounds: [CGRect]

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
            self.hiddenControlItemBounds = Self.bestBounds(for: controlItems.hidden)
            self.alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map { [Self.bestBounds(for: $0)] } ?? []
        }

        private static func bestBounds(for item: MenuBarItem) -> CGRect {
            item.liveBounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if item.tag == .visibleControlItem {
                return true
            }
            if !item.canBeHidden {
                return false
            }
            if item.isSystemClone {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }

        mutating func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            let itemBounds = Self.bestBounds(for: item)

            // Fast path: the item is entirely on one side of every boundary.
            if itemBounds.minX >= hiddenControlItemBounds.maxX {
                return .visible
            }
            if itemBounds.maxX <= hiddenControlItemBounds.minX {
                if let alwaysHiddenBounds = alwaysHiddenControlItemBounds.first {
                    if itemBounds.minX >= alwaysHiddenBounds.maxX {
                        return .hidden
                    }
                    if itemBounds.maxX <= alwaysHiddenBounds.minX {
                        return .alwaysHidden
                    }
                } else {
                    return .hidden
                }
            }

            // The item straddles a divider (a collapsed section, or mid show/hide).
            // Returning nil would drop it from Phase 1, so classify by midpoint.
            let itemMid = (itemBounds.minX + itemBounds.maxX) / 2
            let hiddenMid = (hiddenControlItemBounds.minX + hiddenControlItemBounds.maxX) / 2
            if itemMid >= hiddenMid {
                return .visible
            }
            if let alwaysHiddenBounds = alwaysHiddenControlItemBounds.first {
                let ahMid = (alwaysHiddenBounds.minX + alwaysHiddenBounds.maxX) / 2
                return itemMid >= ahMid ? .hidden : .alwaysHidden
            }
            return .hidden
        }
    }
}
