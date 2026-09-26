//
//  MenuBarItemManager+ItemCache.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
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

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    struct ControlItemPair {
        nonisolated enum Resolution: Equatable {
            case identity
            case axFrameCorrelation
        }

        nonisolated let hidden: MenuBarItem
        nonisolated let alwaysHidden: MenuBarItem?
        nonisolated let resolution: Resolution

        /// AX-frame correlation identifies likely controls geometrically, but
        /// that evidence is not strong enough to reposition section dividers.
        nonisolated var canRepositionControlItems: Bool {
            resolution != .axFrameCorrelation
        }

        /// For tests and callers with already-resolved items; live discovery uses
        /// the failable init. Nonisolated so tests can call it without a hop.
        nonisolated init(
            hidden: MenuBarItem,
            alwaysHidden: MenuBarItem?,
            resolution: Resolution = .identity
        ) {
            self.hidden = hidden
            self.alwaysHidden = alwaysHidden
            self.resolution = resolution
        }

        /// Creates a control item pair from a list of menu bar items.
        ///
        /// Our own NSStatusItem window IDs are authoritative; tag and title are
        /// startup fallbacks. On macOS 26 Control Center owns every item window
        /// and kCGWindowName can differ from the autosaveName.
        init?(
            items: inout [MenuBarItem],
            hiddenControlItemWindowID: CGWindowID? = nil,
            alwaysHiddenControlItemWindowID: CGWindowID? = nil
        ) {
            // Duplicate Thaw instances share titles, and tag matching favors the
            // lowest window ID, which may be another process's.
            if let hiddenWID = hiddenControlItemWindowID,
               let hiddenIndex = items.firstIndex(where: { $0.windowID == hiddenWID })
            {
                self.hidden = items.remove(at: hiddenIndex)
                self.alwaysHidden = Self.resolveAlwaysHidden(
                    in: &items,
                    authoritativeWindowID: alwaysHiddenControlItemWindowID
                )
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via window ID")
                return
            }

            // Ask WindowServer for our own windows when they're missing from
            // items (parked offscreen or off the active space). The fallbacks
            // below fail in exactly those conditions (#923).
            if let hiddenWID = hiddenControlItemWindowID,
               Self.shouldRecoverOwnControlItem(
                   authoritativeWindowID: hiddenWID,
                   itemWindowIDs: Set(items.map(\.windowID))
               ),
               let hidden = MenuBarItem.ownControlItem(windowID: hiddenWID)
            {
                self.hidden = hidden
                self.alwaysHidden = Self.resolveAlwaysHidden(
                    in: &items,
                    authoritativeWindowID: alwaysHiddenControlItemWindowID
                )
                self.resolution = .identity
                MenuBarItemManager.diagLog.info(
                    "ControlItemPair: recovered hidden control item \(hiddenWID) from its own window; it was absent from the \(items.count)-item list"
                )
                return
            }

            // On Tahoe, Control Center hosts stale and current same-title dividers,
            // both stamped as ours, and the windowNumber may not fit a CGWindowID.
            // Only our AX frames can break the tie; otherwise keep the last good cache.
            let ambiguousTitles = Self.ambiguousControlItemTitles(in: items)
            if !ambiguousTitles.isEmpty {
                if let pair = Self.matchViaAXFrame(items: &items),
                   !ambiguousTitles.contains(ControlItem.Identifier.alwaysHidden.rawValue) ||
                   pair.alwaysHidden != nil
                {
                    self.hidden = pair.hidden
                    self.alwaysHidden = pair.alwaysHidden
                    self.resolution = .axFrameCorrelation
                    MenuBarItemManager.diagLog.info(
                        "ControlItemPair: resolved duplicate control-item titles via unambiguous current-process AX frames"
                    )
                    return
                }
                MenuBarItemManager.diagLog.warning(
                    "ControlItemPair: refusing ambiguous same-title control windows without an authoritative CG window ID: \(ambiguousTitles.sorted())"
                )
                return nil
            }

            // Fallback 1: match by tag (namespace + title).
            if let hidden = items.removeFirst(matching: .hiddenControlItem) {
                self.hidden = hidden
                self.alwaysHidden = Self.resolveAlwaysHidden(
                    in: &items,
                    authoritativeWindowID: alwaysHiddenControlItemWindowID
                )
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via tag")
                return
            }

            // Fallback 2: match by sourcePID (our own process) + known title.
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let hiddenTitle = ControlItem.Identifier.hidden.rawValue

            if let idx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == hiddenTitle }) {
                self.hidden = items.remove(at: idx)
                self.alwaysHidden = Self.resolveAlwaysHidden(
                    in: &items,
                    authoritativeWindowID: alwaysHiddenControlItemWindowID
                )
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via sourcePID and title")
                return
            }

            // Fallback 3 (#754): correlate our own AX frames with window bounds.
            // Works when every CG-side identity channel has degraded.
            if let pair = Self.matchViaAXFrame(items: &items) {
                self.hidden = pair.hidden
                self.alwaysHidden = pair.alwaysHidden
                self.resolution = .axFrameCorrelation
                return
            }

            MenuBarItemManager.diagLog.warning(
                "ControlItemPair: unresolved; no strategy identified the hidden control item among \(items.count) item(s)"
            )
            return nil
        }

        /// Control-item titles that occur more than once in one enumeration.
        static nonisolated func ambiguousControlItemTitles(
            in items: [MenuBarItem]
        ) -> Set<String> {
            let relevantTitles = Set([
                ControlItem.Identifier.hidden.rawValue,
                ControlItem.Identifier.alwaysHidden.rawValue,
            ])
            var counts = [String: Int]()
            for item in items {
                guard let title = item.title, relevantTitles.contains(title) else { continue }
                counts[title, default: 0] += 1
            }
            return Set(counts.compactMap { title, count in count > 1 ? title : nil })
        }

        /// Whether to rebuild a control item from its window instead of the
        /// identity fallbacks: only when we have its ID but it's missing from the list.
        static nonisolated func shouldRecoverOwnControlItem(
            authoritativeWindowID: CGWindowID?,
            itemWindowIDs: Set<CGWindowID>
        ) -> Bool {
            guard let authoritativeWindowID else {
                return false
            }
            return !itemWindowIDs.contains(authoritativeWindowID)
        }

        /// Resolves the always-hidden control item once the hidden divider is
        /// claimed.
        ///
        /// With our window ID, take the item from the list, or recover it from
        /// WindowServer when parked offscreen (#991). Tag matching is skipped then,
        /// so a duplicate Thaw instance's lookalike isn't adopted. Returns nil
        /// when WindowServer doesn't know the window either.
        ///
        /// `recovery` is a parameter so tests can substitute a fixture.
        ///
        /// Zero (kCGNullWindowID) counts as no ID; unbuilt status items convert to it.
        /// Without an ID, match our PID plus canonical title, then plain tag.
        static func resolveAlwaysHidden(
            in items: inout [MenuBarItem],
            authoritativeWindowID: CGWindowID?,
            recovery: @MainActor (CGWindowID) -> MenuBarItem? = { MenuBarItem.ownControlItem(windowID: $0) }
        ) -> MenuBarItem? {
            guard let windowID = authoritativeWindowID, windowID != 0 else {
                let ourPID = ProcessInfo.processInfo.processIdentifier
                let alwaysHiddenTitle = ControlItem.Identifier.alwaysHidden.rawValue
                if let index = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == alwaysHiddenTitle }) {
                    return items.remove(at: index)
                }
                return items.removeFirst(matching: .alwaysHiddenControlItem)
            }
            if let index = items.firstIndex(where: { $0.windowID == windowID }) {
                return items.remove(at: index)
            }
            guard let recovered = recovery(windowID) else {
                MenuBarItemManager.diagLog.debug(
                    "ControlItemPair: always-hidden window \(windowID) absent from the \(items.count)-item list and unknown to the window server"
                )
                return nil
            }
            MenuBarItemManager.diagLog.info(
                "ControlItemPair: recovered always-hidden control item \(windowID) from its own window; it was absent from the \(items.count)-item list"
            )
            return recovered
        }

        /// Correlates our own AX frames with candidate window bounds. A confident
        /// match is >50% overlap of the smaller rect, with no ties.
        private static func matchViaAXFrame(
            items: inout [MenuBarItem]
        ) -> (hidden: MenuBarItem, alwaysHidden: MenuBarItem?)? {
            guard
                let app = AXHelpers.application(for: .current),
                let extrasMenuBar = AXHelpers.extrasMenuBar(for: app)
            else {
                MenuBarItemManager.diagLog.debug(
                    "ControlItemPair: strategy 4 (AX frame) unavailable — could not resolve Thaw's own extrasMenuBar"
                )
                return nil
            }
            try? app.setMessagingTimeout(0.25)
            try? extrasMenuBar.setMessagingTimeout(0.25)

            let children = AXHelpers.children(for: extrasMenuBar)
            let snapshot: [AXIdentityCatalog.AXItemIdentity] = children.compactMap { child in
                try? child.setMessagingTimeout(0.25)
                guard let frame = AXHelpers.frame(for: child) else { return nil }
                return AXIdentityCatalog.AXItemIdentity(
                    identifier: AXHelpers.identifier(for: child),
                    title: AXHelpers.title(for: child),
                    help: AXHelpers.help(for: child),
                    frame: frame
                )
            }

            guard !snapshot.isEmpty else {
                MenuBarItemManager.diagLog.debug(
                    "ControlItemPair: strategy 4 (AX frame) unavailable — Thaw's extrasMenuBar has no children with frames"
                )
                return nil
            }

            let ourPID = ProcessInfo.processInfo.processIdentifier
            let visibleTitle = ControlItem.Identifier.visible.rawValue
            let candidates = items.indexed().map { index, item in
                CandidateFrame(
                    index: index,
                    bounds: item.bounds,
                    isOwnProcess: item.sourcePID == ourPID,
                    // With the hidden divider absent, the chevron can be the only
                    // own-process candidate and get picked as the divider (#923).
                    // Title, not sourcePID, survives the degradation that got us here.
                    isVisibleControlItem: item.title == visibleTitle
                )
            }
            // The chevron's frame must never match as a divider.
            let axFrames = snapshot
                .filter { identity in
                    identity.identifier != ControlItem.Identifier.visible.rawValue
                        && identity.title != ControlItem.Identifier.visible.rawValue
                }
                .map(\.frame)

            guard let matchedIndices = Self.selectViaAXFrame(candidates: candidates, axFrames: axFrames),
                  let hiddenIdx = matchedIndices.first
            else {
                MenuBarItemManager.diagLog.debug(
                    "ControlItemPair: strategy 4 (AX frame) found no confident correlation among \(items.count) candidate item(s)"
                )
                return nil
            }

            // Remove higher index first so the lower index stays valid.
            let sortedIndices = matchedIndices.sorted(by: >)
            var removed = [Int: MenuBarItem]()
            for idx in sortedIndices {
                removed[idx] = items.remove(at: idx)
            }
            guard let hidden = removed[hiddenIdx] else {
                return nil
            }
            let alwaysHidden = matchedIndices.count > 1 ? removed[matchedIndices[1]] : nil

            MenuBarItemManager.diagLog.info(
                "ControlItemPair: strategy 4 (AX frame) matched hidden control item via AX-frame correlation (windowID=\(hidden.windowID))\(alwaysHidden.map { ", alwaysHidden windowID=\($0.windowID)" } ?? "")"
            )

            return (hidden, alwaysHidden)
        }

        /// What selectViaAXFrame needs, so tests can use synthetic fixtures.
        struct CandidateFrame {
            let index: Int
            let bounds: CGRect
            let isOwnProcess: Bool
            /// Never selected as a divider, however well its frame correlates.
            var isVisibleControlItem = false
        }

        /// Matches own-process candidates to axFrames in AX (left-to-right)
        /// order: the first match is the hidden divider, the second always-hidden.
        ///
        /// Returns 1 or 2 indices in that order, or nil when nothing correlates.
        static nonisolated func selectViaAXFrame(
            candidates: [CandidateFrame],
            axFrames: [CGRect]
        ) -> [Int]? {
            var matchedIndices = [Int]()
            for frame in axFrames {
                let identity = [AXIdentityCatalog.AXItemIdentity(identifier: nil, title: nil, help: nil, frame: frame)]
                let matches = candidates.filter { candidate in
                    !matchedIndices.contains(candidate.index)
                        && candidate.isOwnProcess
                        && !candidate.isVisibleControlItem
                        && AXIdentityCatalog.identity(for: candidate.bounds, in: identity) != nil
                }
                // Several candidates for one frame: refuse rather than let array order decide.
                guard matches.count <= 1 else { return nil }
                guard let candidate = matches.first else { continue }
                matchedIndices.append(candidate.index)
                if matchedIndices.count == 2 {
                    break
                }
            }
            return matchedIndices.isEmpty ? nil : matchedIndices
        }
    }

    /// Duplicate windows claiming our control-item title. Only when our own
    /// window is present, so a stale window number discards nothing.
    static nonisolated func ghostControlItemWindowIDs(
        in items: [MenuBarItem],
        ownWindowIDsByTitle: [String: CGWindowID]
    ) -> Set<CGWindowID> {
        var ghostIDs = Set<CGWindowID>()
        for (title, ownWindowID) in ownWindowIDsByTitle {
            guard items.contains(where: { $0.windowID == ownWindowID }) else { continue }
            for item in items where item.title == title && item.windowID != ownWindowID {
                ghostIDs.insert(item.windowID)
            }
        }
        return ghostIDs
    }

    /// Tahoe can report synthetic window numbers with zero low 32 bits;
    /// truncating them can crash or target the null window.
    static nonisolated func windowServerID(windowNumber: Int) -> CGWindowID? {
        guard windowNumber > 0,
              let windowID = CGWindowID(exactly: windowNumber),
              windowID != kCGNullWindowID
        else {
            return nil
        }
        return windowID
    }

    static nonisolated func authoritativeControlItemWindowID(
        windowNumber: Int
    ) -> CGWindowID? {
        windowServerID(windowNumber: windowNumber)
    }

    /// Returns windows that claim this instance's own namespace without
    /// being one of its status items.
    ///
    /// Control Center can keep serving a dead Thaw process's status item
    /// across relaunches (#1032). It captures nothing, can't anchor a move,
    /// and makes liveIdentitiesAreDegraded(_:) reject every reading.
    ///
    /// Decided by window number, never title, so a genuinely degraded control
    /// item still reaches that check. With none of our windows present, nothing is dropped.
    static nonisolated func orphanedOwnNamespaceWindowIDs(
        in items: [MenuBarItem],
        ownWindowIDs: Set<CGWindowID>
    ) -> Set<CGWindowID> {
        guard items.contains(where: { ownWindowIDs.contains($0.windowID) }) else { return [] }
        return Set(
            items.lazy
                .filter { item in
                    item.tag.namespace == .thaw
                        && !ownWindowIDs.contains(item.windowID)
                        // A spacer's window comes up before its title does,
                        // so a fresh one reads as a generic item under our
                        // namespace until the title lands.
                        && !MenuBarSpacerManager.isSpacerTag(item.tag)
                }
                .map(\.windowID)
        )
    }

    private func ownControlItemWindowIDsByTitle() -> [String: CGWindowID] {
        guard let menuBarManager = appState?.menuBarManager else { return [:] }
        return MenuBarSection.Name.allCases.reduce(into: [:]) { result, name in
            guard let controlItem = menuBarManager.controlItem(withName: name),
                  let window = controlItem.window,
                  let windowID = Self.authoritativeControlItemWindowID(
                      windowNumber: window.windowNumber
                  )
            else { return }
            result[controlItem.identifier.rawValue] = windowID
        }
    }

    @discardableResult
    private func dropOrphanedOwnNamespaceWindows(from items: inout [MenuBarItem]) -> Set<CGWindowID> {
        // Window ownership, not title: a new spacer's window appears before its title.
        let spacerManager = appState?.spacerManager
        let ownWindowIDs = Set(ownControlItemWindowIDsByTitle().values)
            .union(items.lazy.map(\.windowID).filter { spacerManager?.ownsWindowID($0) == true })
        let orphanIDs = Self.orphanedOwnNamespaceWindowIDs(in: items, ownWindowIDs: ownWindowIDs)
        guard !orphanIDs.isEmpty else { return [] }
        let descriptions = items.filter { orphanIDs.contains($0.windowID) }.map(\.tag.description)
        MenuBarItemManager.diagLog.warning(
            "cacheItemsRegardless: dropping \(orphanIDs.count) orphaned window(s) under our own namespace: \(descriptions)"
        )
        items.removeAll { orphanIDs.contains($0.windowID) }
        return orphanIDs
    }

    @discardableResult
    private func dropGhostControlItemWindows(from items: inout [MenuBarItem]) -> Set<CGWindowID> {
        let ghostIDs = Self.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: ownControlItemWindowIDsByTitle()
        )
        if !ghostIDs.isEmpty {
            MenuBarItemManager.diagLog.warning(
                "cacheItemsRegardless: dropping \(ghostIDs.count) duplicate control item window(s)"
            )
            items.removeAll { ghostIDs.contains($0.windowID) }
        }
        return ghostIDs
    }

    /// A brief period in which missing dividers mean Control Center is still
    /// re-hosting status items, not that Thaw should recreate them.
    static nonisolated let controlCenterRelaunchGrace: Duration = .seconds(20)

    static nonisolated func shouldCountControlItemLookupFailure(
        hostUptime: Duration?,
        suppressAutomaticMoves: Bool = false,
        grace: Duration = controlCenterRelaunchGrace
    ) -> Bool {
        // Layout-editor refreshes must not advance recovery or trigger its side effects.
        guard !suppressAutomaticMoves else { return false }
        guard let hostUptime else { return true }
        return hostUptime >= grace
    }

    /// Launch handoff can briefly show two Control Center processes, and
    /// runningApplications is unordered, so pick the newest explicitly.
    static nonisolated func newestControlCenterGeneration(
        in generations: [ProcessGeneration]
    ) -> ProcessGeneration? {
        SourcePIDSeedStore.newestGeneration(in: generations)
    }

    private static func controlCenterGeneration() -> ProcessGeneration? {
        SourcePIDSeedStore.currentControlCenterGeneration()
    }

    static nonisolated func controlCenterUptime(
        generation: ProcessGeneration?,
        now: Date = .now
    ) -> Duration? {
        generation.map { .seconds(max(0, now.timeIntervalSince($0.launchDate))) }
    }

    /// Re-arms divider recovery when Control Center restarts; the new host
    /// builds its windows from scratch.
    @discardableResult
    static nonisolated func resetControlItemLookupEpisodeIfHostChanged(
        previous: ProcessGeneration?,
        current: ProcessGeneration?,
        failureStreak: inout Int,
        alreadyRebuilt: inout Bool
    ) -> Bool {
        guard let current, current != previous else { return false }
        failureStreak = 0
        alreadyRebuilt = false
        return true
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

    /// Caches the items without checking the control item order.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?,
        suppressAutomaticMoves: Bool,
        suppressSavedOrderPersistence: Bool,
        forcePersistSavedOrder: Bool,
        snapshotIsCurrent: () -> Bool
    ) async {
        guard snapshotIsCurrent() else { return }
        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: processing \(items.count) items for caching")
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        var validCount = 0
        var invalidCount = 0
        var noSectionCount = 0

        // macOS can briefly report two windows for one item after a move.
        // Keep the first, which is the rightmost.
        var seenTags = Set<MenuBarItemTag>()

        for item in items where context.isValidForCaching(item) {
            guard seenTags.insert(item.tag).inserted else {
                MenuBarItemManager.diagLog.debug("uncheckedCacheItems: skipping duplicate tag \(item.logString)")
                continue
            }

            validCount += 1
            if item.sourcePID == nil {
                // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
                // Changing this string breaks log-replay regression tests.
                MenuBarItemManager.diagLog.warning("Missing sourcePID for \(item.logString)")
            }

            let matchingContext: TemporarilyShownItemContext? = {
                // Exact tag match, including windowID for non-system items.
                if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                    return temp
                }
                // Tag and PID match, only for an item physically in visible that belongs elsewhere.
                if let temp = temporarilyShownItemContexts.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        $0.sourcePID == (item.sourcePID ?? item.ownerPID)
                }),
                    context.findSection(for: item) == .visible,
                    temp.originalSection != .visible
                {
                    return temp
                }
                return nil
            }()

            if let matchingContext {
                // Cached at their return destinations once the rest are placed.
                context.temporarilyShownItems.append((item, matchingContext.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            noSectionCount += 1
            let currentBounds = item.liveBounds
            if currentBounds.origin.x == -1 {
                MenuBarItemManager.diagLog.warning(
                    "Skipping \(item.logString); blocked (x=-1), will retry on next cache tick"
                )
            } else {
                MenuBarItemManager.diagLog.warning(
                    "Couldn't find section for caching \(item.logString) bounds=\(NSStringFromRect(item.bounds)), assigning to hidden"
                )
                context.cache[.hidden].append(item)
            }
        }

        for item in items where !context.isValidForCaching(item) {
            invalidCount += 1
        }

        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: \(validCount) valid, \(invalidCount) invalid (filtered), \(noSectionCount) couldn't find section, \(context.temporarilyShownItems.count) temporarily shown")

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        let cacheChanged = itemCache != context.cache

        // Discard a pass whose divider geometry disagrees with the section's
        // logical state. Keeping the previous cache costs one cycle; accepting
        // the mixture reclassifies a whole section (#851).
        if Self.shouldEvaluateSavedOrderPersistence(
            cacheChanged: cacheChanged,
            forcePersistSavedOrder: forcePersistSavedOrder
        ),
            !itemCache.managedItems.isEmpty,
            let section = await midTransitionSection(in: context)
        {
            MenuBarItemManager.diagLog.debug(
                "Not updating menu bar item cache: \(section.logString) is mid expand/collapse, keeping last-known-good cache"
            )
            return
        }

        // midTransitionSection can suspend while a user move makes this reading obsolete.
        guard snapshotIsCurrent() else { return }

        // Without the always-hidden divider, findSection folds always-hidden into
        // hidden; persisting that made #849 permanent.
        let alwaysHiddenSectionResolved = LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: context.controlItems.alwaysHidden != nil,
            isAlwaysHiddenSectionEnabled: appState?.menuBarManager
                .section(withName: .alwaysHidden)?.isEnabled ?? false
        )

        // CGDisplayBounds, not NSScreen.frame: item bounds are in flipped CG space.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }

        // A zero-width hidden span classifies on-screen items as visible (#795).
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
            alwaysHiddenControlItemMaxX: context.alwaysHiddenControlItemBounds.first?.maxX,
            savedHiddenItemCount: savedSectionOrder[sectionKey(for: .hidden)]?.count ?? 0,
            liveHiddenItemCount: context.cache[.hidden].count,
            hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                itemBounds: MenuBarSection.Name.allCases.flatMap { section in
                    context.cache[section].map(\.bounds)
                },
                hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
                screenFrames: screenFrames
            )
        )

        if !suppressAutomaticMoves,
           recoverCollapsedHiddenSectionIfNeeded(
               hiddenSectionHasRoom: hiddenSectionHasRoom,
               controlItems: context.controlItems,
               // Dividers excluded: with only them to place, a rebuild strands nothing.
               managedItemCount: context.cache.managedItems.count(where: { !$0.isControlItem })
           )
        {
            return
        }

        guard Self.shouldEvaluateSavedOrderPersistence(
            cacheChanged: cacheChanged,
            forcePersistSavedOrder: forcePersistSavedOrder
        ) else {
            MenuBarItemManager.diagLog.debug("Not updating menu bar item cache, as items haven't changed")
            // Still counts: settling's early exit needs these stable no-op reads.
            completedCacheCycles += 1
            return
        }

        // Read before it's overwritten: the save gate checks for a display change (#958).
        let previousCacheDisplayID = itemCache.displayID

        if cacheChanged {
            itemCache = context.cache

            // Lets the next launch label items before its source-PID scan lands (#956).
            MenuBarItemNameMemory.remember(itemCache.managedItems)
        } else {
            MenuBarItemManager.diagLog.debug(
                "Menu bar item cache is unchanged; evaluating saved-order persistence for a validated Layout-editor move"
            )
        }

        // A stuck flag would block saves after manual moves.
        if isRestoringItemOrder, let timestamp = isRestoringItemOrderTimestamp, Date().timeIntervalSince(timestamp) > 10 {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        let hasPendingDivergence = pendingDivergenceObservedAt != nil

        // Mirrors applySavedLayout's cooldown, or a cycle can save a bar nobody
        // arranged (#958). User moves are exempt: the save must win so the
        // restore doesn't later revert the drag as drift.
        let isWithinMoveCooldown = lastMoveOperationOccurred(within: .seconds(5)) &&
            !Self.saveCooldownExemptForUserMove(
                lastMoveOperationTimestamp: lastMoveOperationTimestamp,
                lastUserMoveOperationTimestamp: lastUserMoveOperationTimestamp
            )

        // A relocation in progress. A nil on either side is just the first cycle.
        let menuBarDisplayChanged: Bool = if let previousCacheDisplayID,
                                             let currentDisplayID = context.cache.displayID
        {
            previousCacheDisplayID != currentDisplayID
        } else {
            false
        }

        // Saving a half-applied batch makes the bar drift further every retry (#900).
        if !suppressSavedOrderPersistence,
           context.controlItems.canRepositionControlItems,
           LayoutSolver.shouldPersistSavedOrder(
               LayoutSolver.SavedOrderGate(
                   isRestoringItemOrder: isRestoringItemOrder,
                   isResettingLayout: isResettingLayout,
                   isInStartupSettling: isInStartupSettling,
                   isApplyingProfileLayout: isApplyingProfileLayout,
                   temporarilyShownItemContextsIsEmpty: temporarilyShownItemContexts.isEmpty,
                   alwaysHiddenSectionResolved: alwaysHiddenSectionResolved,
                   hiddenSectionHasRoom: hiddenSectionHasRoom,
                   hasPendingDivergence: hasPendingDivergence,
                   hasUnfinishedMoveBatch: hasUnfinishedMoveBatch,
                   isWithinMoveCooldown: isWithinMoveCooldown,
                   menuBarDisplayChanged: menuBarDisplayChanged
               )
           )
        {
            // Items at x=-1 are in a transient blocked state.
            let hasBlockedItems = MenuBarSection.Name.allCases.contains { section in
                context.cache[section].contains { item in
                    let bounds = item.liveBounds
                    return bounds.origin.x == -1
                }
            }
            // Items straddling two displays mean a relocation mid-flight, and macOS
            // un-hides items as it moves them. Saving now bakes that in.
            //
            // Visible only: parked items sit at negative x, which a display left of
            // main owns, so they'd always read as a second screen.
            let itemCenters = context.cache[.visible].map {
                CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)
            }
            let spansDisplays = LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: itemCenters,
                screenFrames: screenFrames
            )
            if hasBlockedItems {
                MenuBarItemManager.diagLog.warning(
                    "Skipping saveSectionOrder; blocked items detected (x=-1), will retry on next cache tick"
                )
            } else if spansDisplays {
                MenuBarItemManager.diagLog.warning(
                    "Skipping saveSectionOrder; menu bar items span multiple displays (relocation in progress)"
                )
            } else {
                saveSectionOrder(from: context.cache)
            }
        } else if suppressSavedOrderPersistence {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; this cache refresh follows a failed automatic move attempt"
            )
        } else if !context.controlItems.canRepositionControlItems {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; control items resolved only by provisional AX-frame correlation"
            )
        } else if !alwaysHiddenSectionResolved {
            // Separate warning: this one silently rewrites the layout when wrong (#849).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; always-hidden divider unresolved while its section is enabled"
            )
        } else if !hiddenSectionHasRoom {
            // A geometry fault, kept greppable apart from the one above.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; hidden section has zero width between the dividers (hidden.minX=\(context.hiddenControlItemBounds.minX) windowID=\(context.controlItems.hidden.windowID), alwaysHidden.maxX=\(context.alwaysHiddenControlItemBounds.first?.maxX.description ?? "nil") windowID=\(context.controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
        } else if hasPendingDivergence {
            // applySavedLayout is waiting for a second divergence reading. This
            // cache may be transient (e.g. a space switch re-exposing hidden items) (#736).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; layout divergence pending confirmation (applySavedLayout has not yet restored the cached layout)"
            )
        } else if isWithinMoveCooldown {
            // A run of these means the bar never settles long enough to save (#958).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; within the 5s move cooldown that applySavedLayout also honours"
            )
        } else if menuBarDisplayChanged {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; menu bar moved display since the standing cache (\(previousCacheDisplayID.map { "\($0)" } ?? "nil") -> \(context.cache.displayID.map { "\($0)" } ?? "nil")), relocation in progress"
            )
        } else if hasUnfinishedMoveBatch {
            // A run of these means the apply keeps failing and the layout never takes (#900).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; the last bulk apply left planned moves unenacted, so the current arrangement is partial"
            )
        }
        if cacheChanged {
            MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")
        }
        completedCacheCycles += 1
    }

    /// A validated Layout-editor move may already have published its geometry,
    /// so an identical cache must not stop its final refresh here.
    static nonisolated func shouldEvaluateSavedOrderPersistence(
        cacheChanged: Bool,
        forcePersistSavedOrder: Bool
    ) -> Bool {
        cacheChanged || forcePersistSavedOrder
    }

    /// Rebuilds the hidden divider after repeated evidence that stale geometry
    /// closed the hidden span. The saved order is untouched, so the next pass restores it.
    ///
    /// managedItemCount decides whether the rebuild may also re-stamp the
    /// seeded position. See canSeedRebuiltDividerPosition(managedItemCount:).
    private func recoverCollapsedHiddenSectionIfNeeded(
        hiddenSectionHasRoom: Bool,
        controlItems: ControlItemPair,
        managedItemCount: Int
    ) -> Bool {
        // Only authoritative readings may touch the recovery episode.
        guard controlItems.canRepositionControlItems else {
            return false
        }

        guard !hiddenSectionHasRoom else {
            hiddenSectionCollapseStreak = 0
            didRecoverHiddenSectionForCurrentCollapse = false
            return false
        }

        hiddenSectionCollapseStreak += 1
        guard Self.shouldRecoverCollapsedHiddenSection(
            consecutiveCollapsedReadings: hiddenSectionCollapseStreak,
            alreadyRecovered: didRecoverHiddenSectionForCurrentCollapse
        ),
            let hiddenControlItem = appState?.menuBarManager.controlItem(withName: .hidden)
        else {
            return false
        }

        didRecoverHiddenSectionForCurrentCollapse = true
        let seed = Self.seedForRebuiltDivider(
            managedItemCount: managedItemCount,
            storedPositions: Self.currentStoredDividerPositions()
        )
        MenuBarItemManager.diagLog.warning(
            "Hidden section remained collapsed for \(hiddenSectionCollapseStreak) authoritative cache passes; rebuilding H_ctrl\(Self.seedDescription(seed))"
        )
        hiddenControlItem.recreateStatusItem(preferredPosition: seed.preferredPosition)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
        return true
    }

    /// Why a cycle is asking the parked-divider recovery to look at H_ctrl.
    ///
    /// A stranded divider makes the applies refuse before Phase 1, so a refusal
    /// counts like a mismatch; otherwise recovery could never trigger (#978).
    nonisolated enum ParkedDividerTrigger {
        /// Phase 1 found items on the wrong side of H_ctrl.
        case boundaryMismatch(Int)
        /// An apply refused upstream because the hidden section read as
        /// having no room between the dividers. source names the guard.
        case refusedApply(source: String)

        /// Whether this cycle actually needed the divider on the bar. A
        /// mismatch of zero is a healthy cycle; a refusal never is.
        var needsDividerOnBar: Bool {
            switch self {
            case let .boundaryMismatch(count): count > 0
            case .refusedApply: true
            }
        }

        var logDescription: String {
            switch self {
            case let .boundaryMismatch(count): "\(count)-item boundary mismatch"
            case let .refusedApply(source): "refused \(source) apply"
            }
        }
    }

    /// Rebuilds an authoritatively identified hidden divider after it remains
    /// parked through repeated layout cycles that need it on the bar.
    ///
    /// "Parked" means no edge of the frame is on any display. A healthy
    /// collapsed H_ctrl already reaches offscreen, so one edge isn't enough (#978).
    ///
    /// managedItemCount and the stored control item positions decide what
    /// the rebuild does with the autosaved position. See
    /// MenuBarItemManager/seedForRebuiltDivider(managedItemCount:storedPositions:).
    func recoverParkedHiddenDividerIfNeeded(
        trigger: ParkedDividerTrigger,
        hiddenControlItem: MenuBarItem,
        screenFrames: [CGRect],
        managedItemCount: Int
    ) -> Bool {
        guard trigger.needsDividerOnBar,
              LayoutSolver.isFullyOffScreen(bounds: hiddenControlItem.bounds, screenFrames: screenFrames)
        else {
            resetParkedHiddenDividerRecovery()
            return false
        }

        parkedHiddenDividerMismatchStreak += 1
        guard Self.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: parkedHiddenDividerMismatchStreak,
            alreadyRecovered: didRecoverParkedHiddenDividerForCurrentMismatch
        ),
            let hiddenControl = appState?.menuBarManager.controlItem(withName: .hidden)
        else {
            return false
        }

        didRecoverParkedHiddenDividerForCurrentMismatch = true
        let seed = MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: managedItemCount,
            storedPositions: MenuBarItemManager.currentStoredDividerPositions()
        )
        MenuBarItemManager.diagLog.warning(
            "H_ctrl remained parked through \(parkedHiddenDividerMismatchStreak) authoritative applies (\(trigger.logDescription)); rebuilding it\(MenuBarItemManager.seedDescription(seed))"
        )
        hiddenControl.recreateStatusItem(preferredPosition: seed.preferredPosition)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            // The failed batch may have stamped the move cooldown; bypass it so
            // applySavedLayout verifies the fresh divider.
            await self?.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                bypassSavedLayoutCooldown: true
            )
        }
        return true
    }

    /// Clears the parked-divider streak, so the next strand starts counting
    /// from zero and is allowed its own rebuild.
    ///
    /// Separate because Phase 1 also clears it; clearing on a zero mismatch
    /// alone reset a stranded divider's streak every cycle (#978).
    func resetParkedHiddenDividerRecovery() {
        parkedHiddenDividerMismatchStreak = 0
        didRecoverParkedHiddenDividerForCurrentMismatch = false
    }

    /// Whether bundleID owns a tracked item. The trailing ":" stops prefix
    /// matches (org.x.fdm6 vs org.x.fdm6x:Item-0).
    static nonisolated func tracksMenuBarItem(bundleID: String, in identifiers: Set<String>) -> Bool {
        identifiers.contains { $0.hasPrefix(bundleID + ":") }
    }

    /// Degraded means a generic Item-N title or a reverse-DNS, bundle-ID-shaped one.
    private static func isDegradedIdentity(_ item: MenuBarItem) -> Bool {
        if item.tag.isControlCenterGenericItem {
            return true
        }
        guard let title = item.title else { return false }
        return title.split(separator: ".").count >= 3
    }

    /// Fills degradedItemAXIdentities from an AX snapshot of Control Center and
    /// SystemUIServer, at most once per pass. Display-only.
    private func enrichDegradedItemIdentities(in items: [MenuBarItem]) {
        let degradedItems = items.filter(Self.isDegradedIdentity)
        guard !degradedItems.isEmpty else {
            degradedItemAXIdentities = [:]
            return
        }

        let hostBundleIDs = ["com.apple.controlcenter", "com.apple.systemuiserver"]
        let hosts = hostBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard !hosts.isEmpty else {
            MenuBarItemManager.diagLog.debug(
                "enrichDegradedItemIdentities: \(degradedItems.count) degraded item(s) present but no Control Center/SystemUIServer host is running"
            )
            degradedItemAXIdentities = [:]
            return
        }

        let snapshot = AXIdentityCatalog.snapshot(hosts: hosts)
        var enrichment = [CGWindowID: AXIdentityCatalog.AXItemIdentity]()
        for item in degradedItems {
            let bounds = item.liveBounds
            guard let identity = AXIdentityCatalog.identity(for: bounds, in: snapshot) else { continue }
            enrichment[item.windowID] = identity
        }

        MenuBarItemManager.diagLog.debug(
            "enrichDegradedItemIdentities: \(degradedItems.count) degraded item(s), \(enrichment.count) resolved via AX-frame correlation"
        )
        degradedItemAXIdentities = enrichment
    }

    /// Returns the hideable section whose divider geometry contradicts its
    /// logical state, or nil when both sections agree.
    ///
    /// See isMidSectionTransition(dividerWidth:isSectionCollapsed:) for why
    /// the two can disagree.
    private func midTransitionSection(in context: CacheContext) async -> MenuBarSection.Name? {
        var widths: [(MenuBarSection.Name, CGFloat)] = [
            (.hidden, context.hiddenControlItemBounds.width),
        ]
        if let alwaysHiddenBounds = context.alwaysHiddenControlItemBounds.first {
            widths.append((.alwaysHidden, alwaysHiddenBounds.width))
        }

        let mismatch = await MainActor.run { [weak self] () -> MenuBarSection.Name? in
            guard let menuBarManager = self?.appState?.menuBarManager else {
                return nil
            }
            return widths.first { name, width in
                guard
                    let section = menuBarManager.section(withName: name),
                    section.isEnabled
                else {
                    return false
                }
                return MenuBarItemManager.isMidSectionTransition(
                    dividerWidth: width,
                    isSectionCollapsed: section.isHidden
                )
            }?.0
        }

        guard let mismatch else {
            midTransitionSkipStreak = 0
            return nil
        }

        midTransitionSkipStreak += 1
        guard midTransitionSkipStreak <= MenuBarItemManager.maxMidTransitionSkips else {
            MenuBarItemManager.diagLog.warning(
                "midTransitionSection: \(mismatch.logString) still mid expand/collapse after \(midTransitionSkipStreak) passes, accepting this one"
            )
            midTransitionSkipStreak = 0
            return nil
        }

        return mismatch
    }

    /// Records this enumeration's windowIDs and returns the set that counts as
    /// recently seen.
    ///
    /// - Parameter items: The items enumerated this cycle, after clones and
    ///   ghost control windows have been dropped.
    ///
    /// - Returns: Every windowID enumerated within the last
    ///   recentWindowIDCycleWindow cycles, including this one.
    private func recordRecentItemWindowIDs(_ items: [MenuBarItem]) -> Set<CGWindowID> {
        recentItemWindowIDCycles.append(Set(items.lazy.map(\.windowID)))
        while recentItemWindowIDCycles.count > MenuBarItemManager.recentWindowIDCycleWindow {
            recentItemWindowIDCycles.removeFirst()
        }
        return recentItemWindowIDCycles.reduce(into: Set()) { $0.formUnion($1) }
    }

    /// Caches the current items unconditionally, fixing the control item order first.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        skipRecentMoveCheck: Bool = false,
        resolveSourcePID: Bool = true,
        reuseCachedIdentities: Bool = false,
        skipSavedLayoutApply: Bool = false,
        suppressAutomaticMoves: Bool = false,
        suppressSavedOrderPersistence: Bool = false,
        bypassSavedLayoutCooldown: Bool = false,
        forcePersistSavedOrder: Bool = false,
        waiterToken: Int? = nil,
        cacheAttempt: CacheAttempt? = nil
    ) async {
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil), resolveSourcePID=\(resolveSourcePID), reuseCachedIdentities=\(reuseCachedIdentities), skipSavedLayoutApply=\(skipSavedLayoutApply), suppressAutomaticMoves=\(suppressAutomaticMoves), suppressSavedOrderPersistence=\(suppressSavedOrderPersistence), bypassSavedLayoutCooldown=\(bypassSavedLayoutCooldown), forcePersistSavedOrder=\(forcePersistSavedOrder))"
        )

        guard skipRecentMoveCheck || !lastMoveOperationOccurred(within: .seconds(1)) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache due to recent item movement")
            return
        }

        guard !(appState?.isDraggingMenuBarItem ?? false) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: user is cmd-dragging")
            return
        }

        // Drop concurrent calls, or one may snapshot pre-move positions.
        guard await cacheGate.begin() else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, skipping")
            return
        }
        defer { Task { await cacheGate.end() } }

        // After the gate, so a dropped call can't claim an earlier cycle's success.
        let completedCyclesAtGateEntry = completedCacheCycles
        let moveTimestampAtGateEntry = lastMoveOperationTimestamp
        func snapshotIsCurrent(_ stage: String) -> Bool {
            guard lastMoveOperationTimestamp == moveTimestampAtGateEntry else {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: discarding stale snapshot at \(stage) because an item moved during this pass"
                )
                return false
            }
            return true
        }
        defer {
            cacheAttempt?.recordCompletion(
                cyclesAtEntry: completedCyclesAtGateEntry,
                cyclesAtExit: completedCacheCycles,
                snapshotRemainedCurrent: lastMoveOperationTimestamp == moveTimestampAtGateEntry
            )
        }

        // Relocation hand-offs pass the waiter to a nested recache. The defer
        // releases it on every other exit so it's never stranded.
        var ownsWaiter = true
        defer {
            if ownsWaiter, let waiterToken {
                resumeBackgroundCacheWaiter(waiterToken)
            }
        }

        let previousWindowIDs = cacheActor.cachedItemWindowIDs
        let previousCCGenericWindowIDs = cacheActor.cachedControlCenterGenericWindowIDs
        let displayID = Bridging.getActiveMenuBarDisplayID()
        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: displayID=\(displayID.map { "\($0)" } ?? "nil"), previousWindowIDs count=\(previousWindowIDs.count)")

        var enumeration = await MenuBarItem.getMenuBarItemsSnapshot(
            option: .activeSpace,
            resolveSourcePID: resolveSourcePID
        )
        var items = enumeration.items

        if items.isEmpty {
            // Transient WindowServer glitches and display changes can return nothing.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
            try? await Task.sleep(for: .milliseconds(250))
            enumeration = await MenuBarItem.getMenuBarItemsSnapshot(
                option: .activeSpace,
                resolveSourcePID: resolveSourcePID
            )
            items = enumeration.items

            // The bar doesn't empty itself; this is the .activeSpace filter using a
            // stale space ID. Keep the last good cache, or the layout editor blanks (#851).
            if items.isEmpty, !itemCache.managedItems.isEmpty {
                MenuBarItemManager.diagLog.warning(
                    "cacheItemsRegardless: getMenuBarItems returned ZERO items twice, keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
                )
                return
            }
        }

        // The editor only needs geometry; reusing confirmed identities skips the
        // slow AX source-PID scan without turning icons into placeholders.
        if reuseCachedIdentities {
            items = Self.reusingCachedIdentities(
                in: items,
                from: itemCache.managedItems
            )
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: getMenuBarItems returned \(items.count) items")

        // WindowServer spawns clone windows during capture and animations, with
        // fresh IDs and no source PID. Drop them early so they never trip a re-layout.
        let cloneWindowIDs = Set(items.filter(\.isSystemClone).map(\.windowID))
        if !cloneWindowIDs.isEmpty {
            let cloneDescriptions = items.filter(\.isSystemClone).map(\.tag.description)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: dropping \(cloneWindowIDs.count) system clone window(s): \(cloneDescriptions)")
            items.removeAll(where: \.isSystemClone)
        }

        // A duplicate or crashed Thaw can leave control-item titles on foreign windows.
        var ghostWindowIDs = dropGhostControlItemWindows(from: &items)

        // Drop orphans before the degradation check, which would read one as the
        // whole bar losing its names (#1032).
        ghostWindowIDs.formUnion(dropOrphanedOwnNamespaceWindows(from: &items))

        // Items titled after their owners identify nothing; caching them rewrites
        // the bar under IDs no later reading matches (#881). Keep the last good cache.
        if !itemCache.managedItems.isEmpty,
           LayoutSolver.liveIdentitiesAreDegraded(items.map { ($0.tag.namespace.description, $0.tag.title) })
        {
            MenuBarItemManager.diagLog.warning(
                "cacheItemsRegardless: reading titles items after their own owners (\(items.count) item(s)); keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
            )
            return
        }

        // Enumeration is slow; if a move landed meanwhile, discard this reading entirely.
        guard snapshotIsCurrent("after item enumeration") else { return }

        // After dropping clones and ghosts, so their throwaway IDs stay out.
        let recentWindowIDs = recordRecentItemWindowIDs(items)

        // SourcePIDCache matches CG windows to AX children spatially, which goes
        // wrong when AX lags after a move. A PID from a stable cycle is more trustworthy.
        var provisionalSourcePIDSeeds = enumeration.appliedSourcePIDSeeds
        var didReconcileSourcePID = false
        if resolveSourcePID {
            let previousBaselines = cacheActor.cachedSourcePIDBaselines
            var attemptedPIDs = Set<pid_t>()
            var identities = [pid_t: SourceProcessIdentity]()

            func cachedLiveIdentity(for pid: pid_t) -> SourceProcessIdentity? {
                if let cached = identities[pid] {
                    return cached
                }
                guard attemptedPIDs.insert(pid).inserted,
                      let resolved = SourcePIDSeedStore.liveIdentity(of: pid)
                else { return nil }
                identities[pid] = resolved
                return resolved
            }

            for i in items.indices {
                let item = items[i]
                guard
                    !item.isControlItem,
                    let previous = previousBaselines[item.windowID],
                    item.sourcePID != previous.pid,
                    let window = enumeration.windowsByID[item.windowID],
                    let controlCenterGeneration = enumeration.controlCenterGeneration,
                    SourcePIDSeedStore.reconciledSourcePID(
                        currentPID: item.sourcePID,
                        previous: previous,
                        for: window,
                        currentControlCenterGeneration: controlCenterGeneration,
                        liveIdentity: cachedLiveIdentity(for:)
                    ) == previous.pid
                else { continue }

                if let currentPID = item.sourcePID {
                    MenuBarItemManager.diagLog.warning(
                        "SourcePID changed for windowID \(item.windowID): \(previous.pid) -> \(currentPID), reverting to the generation-validated baseline"
                    )
                } else {
                    MenuBarItemManager.diagLog.info(
                        "SourcePID unresolved for windowID \(item.windowID); restoring the generation-validated in-session baseline \(previous.pid)"
                    )
                    provisionalSourcePIDSeeds[item.windowID] = previous
                }

                let correctedNamespace = MenuBarItemTag.Namespace.optional(
                    previous.bundleIdentifier ?? previous.processName
                )
                let correctedTag = MenuBarItemTag(
                    namespace: correctedNamespace,
                    title: item.tag.title,
                    windowID: item.windowID,
                    instanceIndex: item.tag.instanceIndex
                )
                items[i] = MenuBarItem(
                    tag: correctedTag,
                    windowID: item.windowID,
                    ownerPID: item.ownerPID,
                    sourcePID: previous.pid,
                    bounds: item.bounds,
                    title: item.title,
                    isOnScreen: item.isOnScreen
                )
                didReconcileSourcePID = true
            }
        }

        // Reconciling can change a namespace but keep the instanceIndex, so two
        // items can collide. Regroup the indices.
        if didReconcileSourcePID {
            MenuBarItem.assignStableInstanceIndices(to: &items, using: enumeration.windowsByID)
        }

        // A newly resolved identifier would look new to relocateNewLeftmostItems.
        // Skip unresolved sourcePIDs so the placeholder namespace is never persisted.
        if !previousWindowIDs.isEmpty {
            for item in items where previousWindowIDs.contains(item.windowID) && item.sourcePID != nil {
                let identifier = "\(item.tag.namespace):\(item.tag.title)"
                if !knownItemIdentifiers.contains(identifier) {
                    knownItemIdentifiers.insert(identifier)
                }
            }
            persistKnownItemIdentifiers()
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after getMenuBarItems")
            return
        }

        if items.isEmpty {
            MenuBarItemManager.diagLog.error("cacheItemsRegardless: getMenuBarItems returned ZERO items even after retry; this is the root cause of 'Loading menu bar items' being stuck")
        }

        // The raw window list may still hold clone or ghost IDs.
        let itemWindowIDs = (currentItemWindowIDs ?? items.reversed().map(\.windowID))
            .filter { !cloneWindowIDs.contains($0) && !ghostWindowIDs.contains($0) }
        // Don't commit the window IDs yet: if the ControlItemPair guard fails, the
        // change detector would stop firing right when recovery depends on it.

        await MainActor.run {
            MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
            self.pruneMoveOperationTimeouts(keeping: Set(items.map(\.tag)))
            self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
        }
        guard snapshotIsCurrent("after cache pruning") else { return }

        // Lets ControlItemPair match by window ID when tag and title fail (macOS 26+).
        let hiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .hidden)?.window?.windowNumber
        let alwaysHiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window?.windowNumber
        let hiddenControlItemWID = hiddenControlItemWindowNumber.flatMap {
            Self.authoritativeControlItemWindowID(windowNumber: $0)
        }
        let alwaysHiddenControlItemWID = alwaysHiddenControlItemWindowNumber.flatMap {
            Self.authoritativeControlItemWindowID(windowNumber: $0)
        }
        let observedControlCenterGeneration = Self.controlCenterGeneration()

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
        ) else {
            guard snapshotIsCurrent("before control-item recovery") else { return }
            // Keep the last good cache and leave the window IDs uncommitted so the
            // detector re-fires (#754). After controlItemRebuildThreshold failures in a
            // row the status items themselves are gone, so rebuild them.
            if !suppressAutomaticMoves,
               Self.resetControlItemLookupEpisodeIfHostChanged(
                   previous: lastObservedControlCenterGeneration,
                   current: observedControlCenterGeneration,
                   failureStreak: &controlItemLookupFailureStreak,
                   alreadyRebuilt: &didRebuildControlItemsForCurrentFailureEpisode
               )
            {
                lastControlItemLookupFailureAt = nil
                lastObservedControlCenterGeneration = observedControlCenterGeneration
            }
            let hostUptime = Self.controlCenterUptime(
                generation: observedControlCenterGeneration
            )
            guard Self.shouldCountControlItemLookupFailure(
                hostUptime: hostUptime,
                suppressAutomaticMoves: suppressAutomaticMoves
            ) else {
                MenuBarItemManager.diagLog.info(
                    suppressAutomaticMoves
                        ? "cacheItemsRegardless: Missing control item during Layout-editor refresh; not advancing recovery or scheduling an automatic recache. Items remaining: \(items.count)"
                        : "cacheItemsRegardless: Missing control item for hidden section \(hostUptime.map { "\(Int($0.milliseconds / 1000)) s" } ?? "?") after Control Center launched; not counting it toward a rebuild while the bar is being re-hosted. Items remaining: \(items.count)"
                )
                await MainActor.run {
                    self.areControlItemsMissing = true
                }
                return
            }
            controlItemLookupFailureStreak += 1
            lastControlItemLookupFailureAt = .now
            let failureStreak = controlItemLookupFailureStreak
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: Missing control item for hidden section (expected tag: \(MenuBarItemTag.hiddenControlItem)), keeping last-known-good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count). hiddenWindowNumber=\(hiddenControlItemWindowNumber.map(String.init) ?? "nil"), hiddenControlItemWID=\(hiddenControlItemWID.map(String.init) ?? "nil"), alwaysHiddenWindowNumber=\(alwaysHiddenControlItemWindowNumber.map(String.init) ?? "nil"), alwaysHiddenControlItemWID=\(alwaysHiddenControlItemWID.map(String.init) ?? "nil"). consecutiveFailures=\(failureStreak)")
            await MainActor.run {
                self.areControlItemsMissing = true
            }

            if MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: failureStreak,
                alreadyRebuilt: didRebuildControlItemsForCurrentFailureEpisode
            ) {
                MenuBarItemManager.diagLog.warning("cacheItemsRegardless: \(failureStreak) consecutive control item lookup failures, rebuilding hidden/always-hidden status items")
                await MainActor.run {
                    appState?.menuBarManager.controlItem(withName: .hidden)?.recreateStatusItem()
                    appState?.menuBarManager.controlItem(withName: .alwaysHidden)?.recreateStatusItem()
                }
                didRebuildControlItemsForCurrentFailureEpisode = true
                // Recache now. The short wait lets this cycle's cacheGate.end() run,
                // or the recache is dropped, and lets the new windows register.
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    await self?.cacheItemsRegardless()
                }
            }
            return
        }

        if controlItems.canRepositionControlItems {
            controlItemLookupFailureStreak = 0
            didRebuildControlItemsForCurrentFailureEpisode = false
            lastControlItemLookupFailureAt = nil
            if let observedControlCenterGeneration {
                lastObservedControlCenterGeneration = observedControlCenterGeneration
            }
            cacheActor.updateCachedItemWindowIDs(itemWindowIDs)
            cacheActor.updateCachedCloneWindowIDs(cloneWindowIDs.union(ghostWindowIDs))
            cacheActor.updateCachedControlCenterGenericWindowIDs(
                Set(items.filter(\.tag.isControlCenterGenericItem).map(\.windowID))
            )
        }

        await MainActor.run {
            self.areControlItemsMissing = false
        }
        guard snapshotIsCurrent("after control-item discovery") else { return }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

        // A display change can strand the always-hidden divider on another screen
        // while the pair still succeeds, so the rebuild above never fires (#863).
        // Only authoritative cycles count; a disabled section's divider is absent on purpose.
        if !suppressAutomaticMoves, controlItems.canRepositionControlItems {
            if appState?.settings.advanced.enableAlwaysHiddenSection == true {
                if controlItems.alwaysHidden == nil {
                    missingAlwaysHiddenDividerStreak += 1
                    if Self.shouldRecoverMissingAlwaysHiddenDivider(
                        consecutiveMissingReadings: missingAlwaysHiddenDividerStreak,
                        alreadyRecovered: didRecoverMissingAlwaysHiddenDivider
                    ) {
                        didRecoverMissingAlwaysHiddenDivider = true
                        MenuBarItemManager.diagLog.warning(
                            "cacheItemsRegardless: always-hidden section enabled but its divider has not resolved for \(missingAlwaysHiddenDividerStreak) consecutive cycles, recreating it"
                        )
                        await MainActor.run {
                            appState?.menuBarManager.controlItem(withName: .alwaysHidden)?.recreateStatusItem()
                        }
                        Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(100))
                            await self?.cacheItemsRegardless()
                        }
                    }
                } else {
                    missingAlwaysHiddenDividerStreak = 0
                    didRecoverMissingAlwaysHiddenDivider = false
                }
            } else {
                missingAlwaysHiddenDividerStreak = 0
                didRecoverMissingAlwaysHiddenDivider = false
            }
        }

        if Self.isDegradedIdentityEnrichmentEnabled {
            enrichDegradedItemIdentities(in: items)
        } else if !degradedItemAXIdentities.isEmpty {
            degradedItemAXIdentities = [:]
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after control item discovery")
            return
        }

        guard snapshotIsCurrent("before control-item order enforcement") else { return }
        if !suppressAutomaticMoves {
            let controlItemOrderOutcome = await enforceControlItemOrder(
                controlItems: controlItems,
                shouldBeginMove: {
                    snapshotIsCurrent("control-item order move preflight")
                }
            )
            if controlItemOrderOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "Control-item reorder attempt reached moveGate; scheduling authoritative recache"
                )
                // Position-only changes keep window IDs, so the detector can't see them.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(
                        skipRecentMoveCheck: true,
                        resolveSourcePID: resolveSourcePID,
                        reuseCachedIdentities: reuseCachedIdentities,
                        skipSavedLayoutApply: skipSavedLayoutApply
                            || controlItemOrderOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressAutomaticMoves: suppressAutomaticMoves
                            || controlItemOrderOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressSavedOrderPersistence: suppressSavedOrderPersistence
                            || controlItemOrderOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                        bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                        forcePersistSavedOrder: forcePersistSavedOrder,
                        waiterToken: waiterToken
                    )
                }
                return
            }
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled before relocateNewLeftmostItems")
            return
        }
        guard snapshotIsCurrent("after control-item order enforcement") else { return }

        // A relaunched app keeps its identifier but gets a new windowID and lands
        // wherever macOS puts it. Drop it from the sorted snapshot so the
        // late-arrival path picks it up. Must run before the early returns below,
        // whose recache records the new windowID and loses the signal.
        //
        // Idle wake and AX rebinding also recreate status items in place, so only
        // drop items in the wrong section. Undeterminable sections still drop.
        if !suppressAutomaticMoves,
           let activeLayout = activeProfileLayout,
           !activeProfileItemIdentifiers.isEmpty,
           !previousWindowIDs.isEmpty
        {
            let previousWindowIDSet = Set(previousWindowIDs)
            let hiddenMinX = controlItems.hidden.bounds.minX
            let hiddenMaxX = controlItems.hidden.bounds.maxX
            let ahBounds = controlItems.alwaysHidden?.bounds

            var expectedSectionByID = [String: String]()
            for (sectionKey, ids) in activeLayout.itemOrder {
                for id in ids {
                    expectedSectionByID[id] = sectionKey
                }
            }

            /// Mirrors currentLayoutDivergesFromSaved. Items straddling a divider
            /// return nil to avoid false positives during show/hide animations.
            func sectionKey(for item: MenuBarItem) -> String? {
                if item.bounds.minX >= hiddenMaxX {
                    return "visible"
                } else if let ahBounds, item.bounds.maxX <= ahBounds.minX {
                    return "alwaysHidden"
                } else if let ahBounds, item.bounds.minX >= ahBounds.maxX, item.bounds.maxX <= hiddenMinX {
                    return "hidden"
                } else if ahBounds == nil, item.bounds.maxX <= hiddenMinX {
                    return "hidden"
                }
                return nil
            }

            let relaunchedIdentifiers = Set(
                items
                    .filter { item in
                        guard !item.isControlItem,
                              !previousWindowIDSet.contains(item.windowID),
                              activeProfileItemIdentifiers.contains(item.uniqueIdentifier)
                        else { return false }
                        if let expected = expectedSectionByID[item.uniqueIdentifier],
                           let current = sectionKey(for: item),
                           expected == current
                        {
                            return false
                        }
                        return true
                    }
                    .map(\.uniqueIdentifier)
            )
            let staleSorted = relaunchedIdentifiers.intersection(profileSortedItemIdentifiers)
            if !staleSorted.isEmpty {
                MenuBarItemManager.diagLog.info("Profile re-sort: detected \(staleSorted.count) relaunched profile item(s) with fresh windowID at wrong section: \(staleSorted.sorted())")
                profileSortedItemIdentifiers.subtract(staleSorted)
            }
        }

        if !suppressAutomaticMoves {
            let newLeftmostOutcome = await relocateNewLeftmostItems(
                items,
                controlItems: controlItems,
                previousWindowIDs: previousWindowIDs,
                recentWindowIDs: recentWindowIDs,
                shouldBeginMove: {
                    snapshotIsCurrent("new-item relocation move preflight")
                }
            )
            if newLeftmostOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "New-leftmost relocation attempt reached moveGate; scheduling authoritative recache"
                )
                // Ownership transfers to the nested recache: the waiter must not
                // be told the cache is settled until the second cycle finishes.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    // The launch restore runs in this recache. After a failed accepted
                    // attempt, movers are suppressed so it can't retry-loop.
                    await self?.cacheItemsRegardless(
                        skipRecentMoveCheck: true,
                        resolveSourcePID: resolveSourcePID,
                        reuseCachedIdentities: reuseCachedIdentities,
                        skipSavedLayoutApply: skipSavedLayoutApply
                            || newLeftmostOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressAutomaticMoves: suppressAutomaticMoves
                            || newLeftmostOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressSavedOrderPersistence: suppressSavedOrderPersistence
                            || newLeftmostOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                        bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                        forcePersistSavedOrder: forcePersistSavedOrder,
                        waiterToken: waiterToken
                    )
                }
                return
            }
        }
        guard snapshotIsCurrent("after new-item relocation check") else { return }

        if !suppressAutomaticMoves {
            let pendingRelocationOutcome = await relocatePendingItems(
                items,
                controlItems: controlItems,
                shouldBeginMove: {
                    snapshotIsCurrent("pending-item relocation move preflight")
                }
            )
            if pendingRelocationOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "Pending-item relocation attempt reached moveGate; scheduling authoritative recache"
                )
                // Ownership transfers to the nested recache: the waiter must not
                // be told the cache is settled until the second cycle finishes.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(
                        skipRecentMoveCheck: true,
                        resolveSourcePID: resolveSourcePID,
                        reuseCachedIdentities: reuseCachedIdentities,
                        skipSavedLayoutApply: skipSavedLayoutApply
                            || pendingRelocationOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressAutomaticMoves: suppressAutomaticMoves
                            || pendingRelocationOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressSavedOrderPersistence: suppressSavedOrderPersistence
                            || pendingRelocationOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                        bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                        forcePersistSavedOrder: forcePersistSavedOrder,
                        waiterToken: waiterToken
                    )
                }
                return
            }
        }
        guard snapshotIsCurrent("after pending-item relocation check") else { return }

        // Settling prevents cascading moves while many apps load at login;
        // a final pass afterwards restores.
        guard !isInStartupSettling else {
            await uncheckedCacheItems(
                items: items,
                controlItems: controlItems,
                displayID: displayID,
                suppressAutomaticMoves: suppressAutomaticMoves,
                suppressSavedOrderPersistence: suppressSavedOrderPersistence,
                forcePersistSavedOrder: forcePersistSavedOrder,
                snapshotIsCurrent: { snapshotIsCurrent("startup cache publish") }
            )
            guard snapshotIsCurrent("after startup cache publish") else { return }
            // So items appearing during settling aren't late arrivals afterwards.
            if !suppressAutomaticMoves, activeProfileLayout != nil {
                for item in items where !item.isControlItem {
                    profileSortedItemIdentifiers.insert(item.uniqueIdentifier)
                }
            }

            // One early apply for already-identified items, instead of showing
            // macOS's arrangement for all of settling (~8 s, #881).
            // Bypasses the cooldown: relocateThawIcon stamps it within ~100 ms of
            // launch, and this runs only once per settling period.
            if !skipSavedLayoutApply,
               !suppressAutomaticMoves,
               lastMoveOperationTimestamp == moveTimestampAtGateEntry,
               !didAttemptEarlySavedLayoutApply
            {
                let didApply = await applySavedLayout(
                    items: items,
                    previousCycle: PreviousCacheCycle(
                        windowIDs: previousWindowIDs,
                        displayID: itemCache.displayID,
                        ccGenericWindowIDs: previousCCGenericWindowIDs
                    ),
                    controlItems: controlItems,
                    currentDisplayID: displayID,
                    bypassMoveCooldown: true,
                    resolvedIdentitiesOnly: true,
                    shouldBegin: {
                        snapshotIsCurrent("early saved-layout apply preflight")
                    }
                )
                // Only a real dispatch spends the one attempt.
                if didApply {
                    didAttemptEarlySavedLayoutApply = true
                    MenuBarItemManager.diagLog.debug(
                        "cacheItemsRegardless: early saved-layout apply dispatched during settling"
                    )
                    return
                }
            } else if !skipSavedLayoutApply,
                      lastMoveOperationTimestamp != moveTimestampAtGateEntry
            {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: skipping early saved-layout apply because an item moved during this cache pass"
                )
            }

            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: startup settling active, skipping restore")
            return
        }

        // Restore the saved layout when window IDs change (app relaunch).
        //
        // skipSavedLayoutApply keeps the post-apply refresh from re-entering here.
        // Control Center widgets churn windowIDs, so otherwise it loops forever.
        if !skipSavedLayoutApply,
           !suppressAutomaticMoves,
           lastMoveOperationTimestamp == moveTimestampAtGateEntry
        {
            let didApplySavedLayout = await applySavedLayout(
                items: items,
                previousCycle: PreviousCacheCycle(
                    windowIDs: previousWindowIDs,
                    displayID: itemCache.displayID,
                    ccGenericWindowIDs: previousCCGenericWindowIDs
                ),
                controlItems: controlItems,
                currentDisplayID: displayID,
                bypassMoveCooldown: bypassSavedLayoutCooldown,
                shouldBegin: {
                    snapshotIsCurrent("saved-layout apply preflight")
                }
            )
            if didApplySavedLayout {
                return
            }
        } else if !skipSavedLayoutApply,
                  lastMoveOperationTimestamp != moveTimestampAtGateEntry
        {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsRegardless: skipping saved-layout apply because an item moved during this cache pass"
            )
        }

        guard snapshotIsCurrent("before cache publish") else { return }
        await uncheckedCacheItems(
            items: items,
            controlItems: controlItems,
            displayID: displayID,
            suppressAutomaticMoves: suppressAutomaticMoves,
            suppressSavedOrderPersistence: suppressSavedOrderPersistence,
            forcePersistSavedOrder: forcePersistSavedOrder,
            snapshotIsCurrent: { snapshotIsCurrent("cache publish") }
        )
        guard snapshotIsCurrent("after cache publish") else { return }

        // The settle-end fast restore resolves nothing and must not overwrite the baseline.
        if resolveSourcePID {
            let currentWindowIDs = Set(items.map(\.windowID))
            let currentControlCenterGeneration = SourcePIDSeedStore.currentControlCenterGeneration()
            let validatedProvisionalSeeds: [CGWindowID: SourcePIDSeed]
            let freshSeeds: [SourcePIDSeed]

            if let currentControlCenterGeneration {
                var attemptedPIDs = Set<pid_t>()
                var identities = [pid_t: SourceProcessIdentity]()

                func cachedLiveIdentity(for pid: pid_t) -> SourceProcessIdentity? {
                    if let cached = identities[pid] {
                        return cached
                    }
                    guard attemptedPIDs.insert(pid).inserted,
                          let resolved = SourcePIDSeedStore.liveIdentity(of: pid)
                    else { return nil }
                    identities[pid] = resolved
                    return resolved
                }

                validatedProvisionalSeeds = provisionalSourcePIDSeeds.filter { windowID, seed in
                    guard
                        currentWindowIDs.contains(windowID),
                        let window = enumeration.windowsByID[windowID]
                    else { return false }
                    return SourcePIDSeedStore.isTrustworthy(
                        seed,
                        for: window,
                        currentControlCenterGeneration: currentControlCenterGeneration,
                        liveIdentity: cachedLiveIdentity(for:)
                    )
                }
                freshSeeds = SourcePIDSeedStore.seeds(
                    from: items,
                    excluding: Set(validatedProvisionalSeeds.keys),
                    windowsByID: enumeration.windowsByID,
                    currentControlCenterGeneration: currentControlCenterGeneration,
                    identity: SourcePIDSeedStore.liveIdentity(of:)
                )
            } else {
                validatedProvisionalSeeds = [:]
                freshSeeds = []
            }

            let baselines = SourcePIDSeedStore.mergedConfirmedBaselines(
                previous: cacheActor.cachedSourcePIDBaselines,
                fresh: freshSeeds,
                provisional: validatedProvisionalSeeds
            )
            cacheActor.updateCachedSourcePIDBaselines(baselines)

            let previousPersistedSeeds = cacheActor.persistedSourcePIDSeeds(
                from: Defaults.store
            )
            let persistedSeeds = SourcePIDSeedStore.coalescingCaptureTimes(
                proposed: SourcePIDSeedStore.mergedPersistedSeeds(
                    fresh: freshSeeds,
                    provisional: validatedProvisionalSeeds
                ),
                previous: Dictionary(
                    previousPersistedSeeds.map { ($0.windowID, $0) },
                    uniquingKeysWith: { _, last in last }
                )
            )
            if cacheActor.updatePersistedSourcePIDSeeds(persistedSeeds) {
                SourcePIDSeedStore.save(persistedSeeds, to: Defaults.store)
            }

            if !validatedProvisionalSeeds.isEmpty {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: retained \(validatedProvisionalSeeds.count) restored source PID(s) provisionally while persisting \(freshSeeds.count) fresh confirmation(s)"
                )
            }
        }

        if !suppressAutomaticMoves,
           activeProfileLayout != nil,
           !activeProfileItemIdentifiers.isEmpty
        {
            await MainActor.run {
                guard profileResortTask == nil,
                      !isApplyingProfileLayout
                else { return }
                let newProfileItems = Self.lateArrivingProfileIdentifiers(
                    items: items,
                    profileIdentifiers: activeProfileItemIdentifiers,
                    alreadySortedIdentifiers: profileSortedItemIdentifiers
                )
                if !newProfileItems.isEmpty {
                    let unidentifiable = items.count { !$0.isControlItem && $0.sourcePID == nil }
                    if unidentifiable > 0 {
                        MenuBarItemManager.diagLog.debug(
                            "Profile re-sort: ignoring \(unidentifiable) item(s) with an unresolved sourcePID when detecting arrivals"
                        )
                    }
                    MenuBarItemManager.diagLog.info("Profile re-sort: detected \(newProfileItems.count) late-arriving profile item(s): \(newProfileItems.sorted())")
                    scheduleProfileResort()
                }
            }
        }

        await MainActor.run {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: finished, cache now has \(self.itemCache.managedItems.count) managed items")
        }

        // Runs last so it sees the settled cache.
        guard snapshotIsCurrent("before notch-overflow rebalance") else { return }
        if !suppressAutomaticMoves {
            let notchRebalanceOutcome = await rebalanceNotchOverflowIfNeeded(
                items: items,
                controlItems: controlItems,
                shouldBeginMove: {
                    snapshotIsCurrent("notch-overflow move preflight")
                }
            )
            if notchRebalanceOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "Notch-overflow rebalance attempted item moves; scheduling authoritative recache"
                )
                // Position moves keep window IDs, so hand the waiter to a fresh cycle.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(
                        skipRecentMoveCheck: true,
                        resolveSourcePID: resolveSourcePID,
                        reuseCachedIdentities: reuseCachedIdentities,
                        skipSavedLayoutApply: skipSavedLayoutApply
                            || notchRebalanceOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressAutomaticMoves: suppressAutomaticMoves
                            || notchRebalanceOutcome.shouldSuppressAutomaticMovesDuringRecache,
                        suppressSavedOrderPersistence: suppressSavedOrderPersistence
                            || notchRebalanceOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                        bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                        forcePersistSavedOrder: forcePersistSavedOrder,
                        waiterToken: waiterToken
                    )
                }
                return
            }
        }
    }

    /// Returns a fresh-geometry reading with previously confirmed identities
    /// restored for windows that are demonstrably the same live status item.
    static nonisolated func reusingCachedIdentities(
        in freshItems: [MenuBarItem],
        from cachedItems: [MenuBarItem]
    ) -> [MenuBarItem] {
        let cachedByWindowID = Dictionary(
            cachedItems.lazy.map { ($0.windowID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return freshItems.map { freshItem in
            guard freshItem.sourcePID == nil,
                  let cachedItem = cachedByWindowID[freshItem.windowID],
                  let cachedSourcePID = cachedItem.sourcePID,
                  cachedItem.ownerPID == freshItem.ownerPID,
                  cachedItem.title == freshItem.title
            else {
                return freshItem
            }

            return MenuBarItem(
                tag: cachedItem.tag,
                windowID: freshItem.windowID,
                ownerPID: freshItem.ownerPID,
                sourcePID: cachedSourcePID,
                bounds: freshItem.bounds,
                title: freshItem.title,
                isOnScreen: freshItem.isOnScreen
            )
        }
    }

    /// The cache pass the Layout editor needs before thawing its rows after a move.
    ///
    /// Unlike background refreshes it can't be dropped at a busy CacheGate, or the
    /// moved icon duplicates or vanishes. Discrete retries avoid deadlocking on nested recaches.
    func refreshCacheAfterLayoutEditorMove(
        timeout: Duration = .seconds(30),
        forcePersistSavedOrder: Bool = false
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout

        while !Task.isCancelled {
            let attempt = CacheAttempt()
            await cacheItemsRegardless(
                skipRecentMoveCheck: true,
                resolveSourcePID: false,
                reuseCachedIdentities: true,
                skipSavedLayoutApply: true,
                suppressAutomaticMoves: true,
                forcePersistSavedOrder: forcePersistSavedOrder,
                cacheAttempt: attempt
            )
            if attempt.didCompleteCycle {
                return true
            }

            guard ContinuousClock.now < deadline else {
                MenuBarItemManager.diagLog.error(
                    "Layout editor cache refresh timed out before an authoritative cycle completed"
                )
                return false
            }

            do {
                try await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            } catch {
                return false
            }
        }

        return false
    }

    /// Caches the current items if they changed, fixing the control item order first.
    func cacheItemsIfNeeded() async {
        let rawWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        // Known clones don't count as changes. A new clone costs one recache.
        let cloneIDs = cacheActor.cachedCloneWindowIDs
        let itemWindowIDs = cloneIDs.isEmpty
            ? rawWindowIDs
            : rawWindowIDs.filter { !cloneIDs.contains($0) }
        let cachedIDs = cacheActor.cachedItemWindowIDs

        // During a Space switch the .activeSpace filter can match the outgoing
        // space and return nothing. Treating that as real blinks the editor (#851).
        if itemWindowIDs.isEmpty, !cachedIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsIfNeeded: ignoring empty window ID reading against \(cachedIDs.count) cached, likely a Space switch"
            )
            return
        }

        if cachedIDs != itemWindowIDs {
            // Failing lookups leave the snapshot uncommitted, so this fires every
            // poll (#933). Back off; each real attempt logs the streak.
            if let backoff = Self.controlItemLookupRetryBackoff(
                consecutiveFailures: controlItemLookupFailureStreak
            ),
                let lastFailure = lastControlItemLookupFailureAt,
                lastFailure.duration(to: .now) < backoff
            {
                return
            }
            MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: window IDs changed (\(cachedIDs.count) cached vs \(itemWindowIDs.count) current), triggering recache")
            await cacheItemsRegardless(itemWindowIDs)
            return
        }

        await recacheIfSourceProcessesResolved(itemWindowIDs)
    }

    /// Recaches when an item that had no source process last cycle has one now.
    ///
    /// Window IDs don't change when a source process resolves. The AX scan often
    /// misses right after login, and without this the item stays "Menu Bar Item"
    /// under Control Center until relaunch.
    ///
    /// Costs one XPC round trip per tick while anything is unresolved;
    /// SourcePIDNegativeCachePolicy bounds how often that becomes a real scan.
    private func recacheIfSourceProcessesResolved(_ itemWindowIDs: [CGWindowID]) async {
        let probeWindowIDs = Self.windowIDsNeedingSourceResolution(
            cachedItems: itemCache.managedItems,
            currentWindowIDs: itemWindowIDs
        )
        guard !probeWindowIDs.isEmpty else {
            return
        }

        // A duplicate Thaw can leave control-item windows under foreign IDs.
        let windows = WindowInfo.createWindows(from: probeWindowIDs)
            .filter { !($0.title?.hasPrefix("Thaw.ControlItem.") ?? false) }
        guard !windows.isEmpty else {
            return
        }

        let resolved = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows).count { $0 != nil }
        guard resolved > 0 else {
            return
        }

        MenuBarItemManager.diagLog.info(
            """
            cacheItemsIfNeeded: \(resolved) of \(windows.count) item(s) cached without a \
            source process can now be resolved; recaching to give them their real identity
            """
        )
        await cacheItemsRegardless(itemWindowIDs)
    }

    /// The item windows worth asking the service about: the ones the cache is
    /// holding without a source process.
    ///
    /// Read from the cache, so the set only shrinks as items resolve.
    ///
    /// Control items are excluded: their AX children are disabled dividers, so a
    /// request is a guaranteed miss that can scan every running app.
    ///
    /// Limited to currentWindowIDs so a vanished window can't keep the probe alive.
    static nonisolated func windowIDsNeedingSourceResolution(
        cachedItems: [MenuBarItem],
        currentWindowIDs: [CGWindowID]
    ) -> [CGWindowID] {
        let current = Set(currentWindowIDs)
        return Array(
            cachedItems.lazy
                .filter { $0.sourcePID == nil && !$0.isControlItem && current.contains($0.windowID) }
                .map(\.windowID)
                .uniqued()
        )
    }
}
