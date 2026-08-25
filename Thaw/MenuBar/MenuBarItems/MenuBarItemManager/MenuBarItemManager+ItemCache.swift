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
    /// A `final class`, not an actor, despite the historical name: every
    /// access is confined to the manager's `@MainActor` isolation, which is
    /// the only thing making the unsynchronized stored properties safe.
    final class CacheActor {
        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// A mapping from window identifiers to their resolved source process
        /// identifiers from the previous cache cycle. Used to detect and correct
        /// transient sourcePID resolution errors (e.g. stale AX data after moves).
        private(set) var cachedItemPIDs = [CGWindowID: pid_t]()

        /// Window identifiers of the system clone windows seen in the most
        /// recent cache cycle. cacheItemsIfNeeded filters these out of its
        /// change comparison so a transient clone appearing or vanishing
        /// doesn't read as a layout change and trigger a recache.
        private(set) var cachedCloneWindowIDs = Set<CGWindowID>()

        /// Window identifiers of Control-Center-generic (`Item-N`) items seen
        /// in the most recent cache cycle. These windows churn — Live
        /// Activities and other transient Control Center widgets appear,
        /// vanish, and get new windowIDs while the visible item count stays
        /// stable — so applySavedLayout's windowID-change gate ignores their
        /// disappearance instead of dispatching a full bulk apply (#736).
        private(set) var cachedControlCenterGenericWindowIDs = Set<CGWindowID>()

        /// Updates the list of cached menu bar item window identifiers.
        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        /// Updates the set of cached system clone window identifiers.
        func updateCachedCloneWindowIDs(_ ids: Set<CGWindowID>) {
            cachedCloneWindowIDs = ids
        }

        /// Updates the set of cached Control-Center-generic window identifiers.
        func updateCachedControlCenterGenericWindowIDs(_ ids: Set<CGWindowID>) {
            cachedControlCenterGenericWindowIDs = ids
        }

        /// Updates the mapping from window identifiers to source process identifiers.
        func updateCachedItemPIDs(_ pids: [CGWindowID: pid_t]) {
            cachedItemPIDs = pids
        }

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
            cachedItemPIDs.removeAll()
            // Clear clone IDs alongside the main set so the two don't drift.
            // Leaving stale clone IDs here would let cacheItemsIfNeeded filter
            // a recycled windowID out of its comparison before the recache
            // that follows this reset repopulates the set.
            cachedCloneWindowIDs.removeAll()
            cachedControlCenterGenericWindowIDs.removeAll()
        }
    }

    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// Storage for cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        /// Creates a cache with the given display identifier.
        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        /// Returns the managed menu bar items for the given section.
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section]
        }

        /// Returns the address for the menu bar item with the given tag,
        /// if it exists in the cache.
        func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(matching: tag) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        /// Inserts the given menu bar item into the cache at the specified
        /// destination.
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

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    struct ControlItemPair {
        nonisolated enum Resolution: Equatable, Sendable {
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

        /// Creates a control item pair from already-known control items.
        ///
        /// Used by test fixtures and by callers that have already resolved the
        /// hidden and always-hidden items themselves. Production discovery from
        /// a live menu bar uses the failable initializer below.
        ///
        /// Marked `nonisolated` so test fixtures (compiled without the app
        /// target's MainActor default) and other non-MainActor callers can
        /// construct a pair from already-resolved items without a hop; the
        /// failable `init?` below stays implicitly `@MainActor` since it
        /// performs AX-frame correlation.
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
        /// Window IDs from this process's `NSStatusItem` windows are the
        /// authoritative lookup when available. Tag and title lookup remain
        /// fallbacks for startup, when those window IDs may not exist yet.
        ///
        /// On macOS 26 (Tahoe), all menu bar item windows are owned by Control
        /// Center and the item title reported by `kCGWindowName` may differ from
        /// the `NSStatusItem` autosaveName used to build the expected tag, so the
        /// primary lookup can fail.
        init?(
            items: inout [MenuBarItem],
            hiddenControlItemWindowID: CGWindowID? = nil,
            alwaysHiddenControlItemWindowID: CGWindowID? = nil
        ) {
            // Primary lookup: match the windows this process created. Duplicate
            // Thaw instances can produce identical titles; tag assignment then
            // favors the lowest window ID, which may belong to another process.
            if let hiddenWID = hiddenControlItemWindowID,
               let hiddenIndex = items.firstIndex(where: { $0.windowID == hiddenWID })
            {
                self.hidden = items.remove(at: hiddenIndex)
                if let alwaysHiddenWID = alwaysHiddenControlItemWindowID {
                    // Do not adopt a duplicate control window when the
                    // authoritative always-hidden ID is known but absent.
                    if let alwaysHiddenIndex = items.firstIndex(where: { $0.windowID == alwaysHiddenWID }) {
                        self.alwaysHidden = items.remove(at: alwaysHiddenIndex)
                    } else {
                        self.alwaysHidden = nil
                    }
                } else {
                    self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
                }
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via window ID")
                return
            }

            // Authoritative recovery: ask the window server about the windows
            // this process created, instead of searching the enumerated list
            // for them.
            //
            // The primary lookup above can only match a control item that is
            // *in* `items`, and it drops out whenever the window is parked
            // far offscreen or filtered off the active space. The two
            // fallbacks below then need identity channels — namespace, or a
            // resolved sourcePID — that fail together exactly when the item
            // service's PID resolution degrades, which is the same failure
            // that stranded the window in the first place. That left frame
            // correlation guessing at Thaw's own dividers (#923, #924, #927).
            //
            // Thaw holds these windows, so it does not have to guess. Only
            // attempted when the caller supplied an authoritative ID, and
            // only for a window the window server still knows.
            if let hiddenWID = hiddenControlItemWindowID,
               Self.shouldRecoverOwnControlItem(
                   authoritativeWindowID: hiddenWID,
                   itemWindowIDs: Set(items.map(\.windowID))
               ),
               let hidden = MenuBarItem.ownControlItem(windowID: hiddenWID)
            {
                self.hidden = hidden
                if let alwaysHiddenWID = alwaysHiddenControlItemWindowID {
                    if let alwaysHiddenIndex = items.firstIndex(where: { $0.windowID == alwaysHiddenWID }) {
                        self.alwaysHidden = items.remove(at: alwaysHiddenIndex)
                    } else {
                        // Same reasoning for the partner; a nil always-hidden
                        // is a legitimate state (the section can be disabled),
                        // so failure here is not fatal to the pair.
                        self.alwaysHidden = MenuBarItem.ownControlItem(windowID: alwaysHiddenWID)
                    }
                } else {
                    self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
                }
                self.resolution = .identity
                MenuBarItemManager.diagLog.info(
                    "ControlItemPair: recovered hidden control item \(hiddenWID) from its own window; it was absent from the \(items.count)-item list"
                )
                return
            }

            // Fallback 1: match by tag (namespace + title).
            if let hidden = items.removeFirst(matching: .hiddenControlItem) {
                self.hidden = hidden
                self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via tag")
                return
            }

            // Fallback 2: match by sourcePID (our own process) + known title.
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let hiddenTitle = ControlItem.Identifier.hidden.rawValue
            let alwaysHiddenTitle = ControlItem.Identifier.alwaysHidden.rawValue

            if let idx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == hiddenTitle }) {
                self.hidden = items.remove(at: idx)
                if let ahIdx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == alwaysHiddenTitle }) {
                    self.alwaysHidden = items.remove(at: ahIdx)
                } else {
                    self.alwaysHidden = nil
                }
                self.resolution = .identity
                MenuBarItemManager.diagLog.debug("ControlItemPair: resolved via sourcePID and title")
                return
            }

            // Fallback 3 (strategy 4, #754): AX-frame correlation against
            // Thaw's own AX elements. Thaw's control items are its own
            // NSStatusItems, so their AX elements (reached via Thaw's own
            // process, not any third party) carry frames that can be
            // correlated against the candidate items' CG window bounds even
            // when tag, title, and window ID all fail to match — this is
            // the only strategy that lets Thaw identify its OWN control
            // items when every CG-side identity channel has degraded.
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

        /// Whether to rebuild one of Thaw's own control items directly from
        /// its window rather than continuing down the identity fallbacks.
        ///
        /// Only when the caller supplied an authoritative window ID *and*
        /// that window is missing from the enumerated list. Present means the
        /// primary lookup already claimed it; absent with an ID in hand is
        /// precisely the case the fallbacks handle badly, because the
        /// channels they depend on — namespace, resolved sourcePID — fail in
        /// the same conditions that strand the window.
        ///
        /// Pure over its inputs.
        static nonisolated func shouldRecoverOwnControlItem(
            authoritativeWindowID: CGWindowID?,
            itemWindowIDs: Set<CGWindowID>
        ) -> Bool {
            guard let authoritativeWindowID else {
                return false
            }
            return !itemWindowIDs.contains(authoritativeWindowID)
        }

        /// Strategy 4: correlates Thaw's own AX element frames (from its own
        /// `extrasMenuBar`, via `NSRunningApplication.current`) against the
        /// candidate items' CG window bounds, using
        /// `AXIdentityCatalog.identity(for:in:)`'s pure correlation. Confident
        /// matches (>50% overlap of the smaller rect's area, no ties) select
        /// the hidden and always-hidden control items exactly as strategies
        /// 1–3 would.
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
                    // The visible control item is own-process, so it is an
                    // eligible candidate on frame alone. When the hidden
                    // divider is absent from `items` — parked far offscreen,
                    // or dropped by the active-space filter — it can be the
                    // only own-process candidate left, and the hidden AX
                    // frame correlates onto it. It is then returned AS the
                    // hidden divider, and every section boundary downstream
                    // is measured from the wrong window (#923, #924, #927).
                    //
                    // The filter on `axFrames` below excludes the visible
                    // item from the frames being matched *against*; this
                    // excludes it from the windows that can be *selected*.
                    // Matched by title rather than window ID because title
                    // survives the identity degradation that got us here:
                    // it comes off the CG window, not from sourcePID.
                    isVisibleControlItem: item.title == visibleTitle
                )
            }
            // Exclude the visible control item's AX child before correlation
            // so its frame can never confidently match a candidate and be
            // returned as the hidden or always-hidden control item.
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

        /// A candidate item's bounds and own-process ownership, stripped
        /// down to what ``selectViaAXFrame(candidates:axFrames:)`` needs so
        /// it can be exercised with synthetic fixtures.
        struct CandidateFrame {
            let index: Int
            let bounds: CGRect
            let isOwnProcess: Bool
            /// Whether this candidate is Thaw's *visible* control item, which
            /// must never be selected as the hidden or always-hidden divider
            /// however well its frame correlates.
            var isVisibleControlItem = false
        }

        /// Pure selection helper: correlates each of our own control items
        /// (`candidates` where `isOwnProcess` is true) against `axFrames` in
        /// AX order (left-to-right in the extras menu bar, matching the
        /// order Thaw's own status items are enumerated in), so the first
        /// confidently-correlated own-item becomes the hidden control item
        /// and the second becomes the always-hidden one — the same relative
        /// ordering the tag/title strategies assume, but derived from AX
        /// position instead of a title that may no longer be trustworthy.
        ///
        /// Returns the matched candidate indices (1 or 2 of them, in
        /// hidden/always-hidden order), or `nil` when no own-process
        /// candidate correlates confidently with any AX frame.
        static nonisolated func selectViaAXFrame(
            candidates: [CandidateFrame],
            axFrames: [CGRect]
        ) -> [Int]? {
            var matchedIndices = [Int]()
            for frame in axFrames {
                let identity = [AXIdentityCatalog.AXItemIdentity(identifier: nil, title: nil, help: nil, frame: frame)]
                guard
                    let candidate = candidates.first(where: { candidate in
                        !matchedIndices.contains(candidate.index)
                            && candidate.isOwnProcess
                            && !candidate.isVisibleControlItem
                            && AXIdentityCatalog.identity(for: candidate.bounds, in: identity) != nil
                    })
                else { continue }
                matchedIndices.append(candidate.index)
                if matchedIndices.count == 2 {
                    break
                }
            }
            return matchedIndices.isEmpty ? nil : matchedIndices
        }
    }

    /// Returns duplicate windows that claim this instance's control-item
    /// title while its authoritative window is present in the same list.
    /// Requiring the authoritative window makes the filter self-validating:
    /// if a window number is stale or absent, nothing is discarded.
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

    private func ownControlItemWindowIDsByTitle() -> [String: CGWindowID] {
        guard let menuBarManager = appState?.menuBarManager else { return [:] }
        return MenuBarSection.Name.allCases.reduce(into: [:]) { result, name in
            guard let controlItem = menuBarManager.controlItem(withName: name),
                  let window = controlItem.window,
                  window.windowNumber > 0,
                  let windowID = CGWindowID(exactly: window.windowNumber)
            else { return }
            result[controlItem.identifier.rawValue] = windowID
        }
    }

    @discardableResult
    private func dropGhostControlItemWindows(from items: inout [MenuBarItem]) -> Set<CGWindowID> {
        let ghostIDs = Self.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: ownControlItemWindowIDsByTitle()
        )
        guard !ghostIDs.isEmpty else { return [] }
        MenuBarItemManager.diagLog.warning(
            "cacheItemsRegardless: dropping \(ghostIDs.count) duplicate control item window(s)"
        )
        items.removeAll { ghostIDs.contains($0.windowID) }
        return ghostIDs
    }

    /// Context maintained during a menu bar item cache operation.
    struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
        var relocatedItems = [MenuBarItem]()
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

            // Strict-inequality fast path for items that lie entirely on
            // one side of every boundary. Identical to the original
            // semantics so well-behaved items keep their existing
            // classification.
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

            // Fall-through: the item straddles at least one boundary.
            // Control items are zero-width markers; any item whose
            // physical bounds cross the marker's single X coordinate
            // fails the strict inequalities above. This happens when a
            // profile collapses a section by moving its control item
            // into the items' physical range, or transiently while
            // sections expand/collapse during section.show()/hide().
            // Returning nil drops the item from the cache and from
            // Phase 1's section sets, which causes the layout to skip
            // the divider move it would otherwise prefer. Resolve every
            // straddle case via midpoint: assign the item to whichever
            // section its physical centre predominantly occupies.
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

    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?
    ) async {
        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: processing \(items.count) items for caching")
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        var validCount = 0
        var invalidCount = 0
        var noSectionCount = 0

        // Track which tags have already been cached to avoid duplicates.
        // macOS can briefly report two windows for the same item during
        // or shortly after a move operation (e.g. layout reset). We keep
        // the first occurrence, which is the rightmost (items are reversed
        // from the Window Server order).
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
                // 1. Try exact tag match (includes windowID for non-system items).
                if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                    return temp
                }
                // 2. Fallback: tag and PID match, but ONLY if the item is physically in the visible section
                //    (identifying it as the 'shown' instance) and it originally belonged elsewhere.
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
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
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

        // Count invalid items
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
        if cacheChanged,
           !itemCache.managedItems.isEmpty,
           let section = await midTransitionSection(in: context)
        {
            MenuBarItemManager.diagLog.debug(
                "Not updating menu bar item cache: \(section.logString) is mid expand/collapse, keeping last-known-good cache"
            )
            return
        }

        // The always-hidden divider is what tells always-hidden items apart
        // from hidden ones. If this cycle resolved the hidden divider but
        // not the always-hidden one, findSection has already collapsed the
        // always-hidden section into hidden; persisting that reading is what
        // made #849 permanent.
        let alwaysHiddenSectionResolved = LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: context.controlItems.alwaysHidden != nil,
            isAlwaysHiddenSectionEnabled: appState?.menuBarManager
                .section(withName: .alwaysHidden)?.isEnabled ?? false
        )

        // Item bounds come from the window server in CoreGraphics space, so
        // the frames they are tested against have to be CGDisplayBounds and
        // not NSScreen.frame — the two disagree by a vertical flip.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }

        // The hidden section is the span between the two dividers. When it
        // closes to zero, findSection can no longer classify anything as
        // .hidden by the strict test and the midpoint tie-break resolves
        // on-screen items as .visible instead (#795, docked topology).
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
            alwaysHiddenControlItemMaxX: context.alwaysHiddenControlItemBounds.first?.maxX,
            savedHiddenItemCount: savedSectionOrder[sectionKey(for: .hidden)]?.count ?? 0,
            // The cache's own reading, because the cache's own reading is what
            // this path is deciding whether to persist.
            liveHiddenItemCount: context.cache[.hidden].count,
            hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                itemBounds: MenuBarSection.Name.allCases.flatMap { section in
                    context.cache[section].map(\.bounds)
                },
                hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
                screenFrames: screenFrames
            )
        )

        if recoverCollapsedHiddenSectionIfNeeded(
            hiddenSectionHasRoom: hiddenSectionHasRoom,
            controlItems: context.controlItems,
            // The dividers are excluded: a rebuild that only has the two
            // control items to place cannot strand anything on the wrong
            // side of the one it is rebuilding.
            managedItemCount: context.cache.managedItems.count(where: { !$0.isControlItem })
        ) {
            return
        }

        guard cacheChanged else {
            MenuBarItemManager.diagLog.debug("Not updating menu bar item cache, as items haven't changed")
            // Still an observed cycle: the settling stability check needs
            // exactly these stable, no-op reads to count toward its early
            // exit, or a bar that has settled reads as "no evidence" and
            // settling runs to its full deadline.
            completedCacheCycles += 1
            return
        }

        // Read before the assignment below overwrites it: the save gate needs
        // to know whether the menu bar changed display between the cycle that
        // produced the standing cache and this one (#958).
        let previousCacheDisplayID = itemCache.displayID

        itemCache = context.cache

        // Remember what the resolved items are called, so the next launch can
        // label them before its own source-PID scan lands (#956).
        MenuBarItemNameMemory.remember(itemCache.managedItems)

        // Reset isRestoringItemOrder if it's been stuck for too long (10 seconds).
        // This prevents stale flags from blocking saves after user manual moves.
        if isRestoringItemOrder, let timestamp = isRestoringItemOrderTimestamp, Date().timeIntervalSince(timestamp) > 10 {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        let hasPendingDivergence = pendingDivergenceObservedAt != nil

        // Mirrors applySavedLayout's own cooldown. Whatever stops the restore
        // has to stop the save, or the cycle that skips one and takes the
        // other writes down a bar nobody arranged (#958).
        //
        // A move the user made themselves is exempt, and the exemption is
        // load-bearing rather than a nicety: after a Layout-editor drag the
        // live bar diverges from the saved order, and it is the save winning
        // inside the cooldown that makes the drag the new saved order. Hold
        // it back and the restore, once the cooldown lapses, reads the drag
        // as drift and reverts it.
        let isWithinMoveCooldown = lastMoveOperationOccurred(within: .seconds(5)) &&
            !Self.saveCooldownExemptForUserMove(
                lastMoveOperationTimestamp: lastMoveOperationTimestamp,
                lastUserMoveOperationTimestamp: lastUserMoveOperationTimestamp
            )

        // A relocation in progress. Both displays have to be known for the
        // comparison to mean anything: a nil on either side is the ordinary
        // first cycle, not a change.
        let menuBarDisplayChanged: Bool = if let previousCacheDisplayID,
                                            let currentDisplayID = context.cache.displayID
        {
            previousCacheDisplayID != currentDisplayID
        } else {
            false
        }

        // The bar after a batch that gave up partway is the batch's own
        // wreckage, not a layout anyone chose. Recording it hands the next
        // pass a target it just moved, which is how a failed apply turns
        // into a bar that drifts a little further on every retry (#900).
        if context.controlItems.canRepositionControlItems,
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
            // Don't persist if any items are in a transient blocked state (x=-1).
            // Wait for the next cache cycle when bounds are reliable.
            let hasBlockedItems = MenuBarSection.Name.allCases.contains { section in
                context.cache[section].contains { item in
                    let bounds = item.liveBounds
                    return bounds.origin.x == -1
                }
            }
            // Don't persist while the items straddle two displays. A cross-display
            // cache is a menu bar relocation caught mid-flight, not a settled
            // layout: macOS un-hides items as it moves them to the new screen, so
            // capturing the section order now would bake those un-hidden items
            // into the saved layout as if the user wanted them visible. Wait for
            // the items to collapse back onto a single display.
            //
            // Only the visible section feeds the gate. Hidden and always-hidden
            // items are parked left of the menu bar at arbitrary negative x, and
            // a display positioned to the left of the main one owns that
            // coordinate range, so parked items read as a second screen on a
            // settled layout and this branch never stops firing. The visible
            // section is never parked, and a genuine relocation splits it across
            // screens just the same, so narrowing the input keeps the protection.
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
        } else if !context.controlItems.canRepositionControlItems {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; control items resolved only by provisional AX-frame correlation"
            )
        } else if !alwaysHiddenSectionResolved {
            // Logged at warning level, and separately from the gate's other
            // inputs, because this is the one that silently rewrites the
            // user's layout when it goes wrong (#849). A run of these means
            // the always-hidden divider keeps failing to resolve.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; always-hidden divider unresolved while its section is enabled"
            )
        } else if !hiddenSectionHasRoom {
            // Same reasoning as above: this one is a geometry fault rather
            // than a resolution fault, and it is worth being able to grep
            // the two apart. A run of these means the dividers have
            // collapsed and the menu bar is visibly wrong to the user, not
            // merely at risk of a bad save.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; hidden section has zero width between the dividers (hidden.minX=\(context.hiddenControlItemBounds.minX) windowID=\(context.controlItems.hidden.windowID), alwaysHidden.maxX=\(context.alwaysHiddenControlItemBounds.first?.maxX.description ?? "nil") windowID=\(context.controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
        } else if hasPendingDivergence {
            // applySavedLayout observed a layout divergence on this cycle
            // but is waiting for a second consecutive observation before
            // correcting it. The current cache reflects a transient state
            // (e.g. macOS rebuilding the bar after a space switch and
            // re-exposing hidden items as visible); persisting it now
            // would bake that transient state into the saved layout (#736).
            // The arm clears once applySavedLayout confirms and runs its
            // correction, after which the next cycle sees a settled layout.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; layout divergence pending confirmation (applySavedLayout has not yet restored the cached layout)"
            )
        } else if isWithinMoveCooldown {
            // Warning level like the rest: a run of these means the bar is
            // being moved often enough that the save never gets a settled
            // cycle, which is its own problem — but it is no longer the
            // problem of a save landing on an unsettled bar (#958).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; within the 5s move cooldown that applySavedLayout also honours"
            )
        } else if menuBarDisplayChanged {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; menu bar moved display since the standing cache (\(previousCacheDisplayID.map { "\($0)" } ?? "nil") -> \(context.cache.displayID.map { "\($0)" } ?? "nil")), relocation in progress"
            )
        } else if hasUnfinishedMoveBatch {
            // Warning level, like the two above, because a run of these is
            // the signature of a bar that cannot be restored at all: the
            // apply keeps failing, so the saved order keeps being withheld,
            // and the user sees their layout never take (#900).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; the last bulk apply left planned moves unenacted, so the current arrangement is partial"
            )
        }
        MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")
        completedCacheCycles += 1
    }

    /// Rebuilds the hidden divider after repeated, authoritative evidence
    /// that stale geometry closed the hidden span.
    /// The saved order remains untouched, so the next cache pass can restore
    /// section membership through the normal saved-layout apply.
    ///
    /// `managedItemCount` decides whether the rebuild may also re-stamp the
    /// seeded position. See ``canSeedRebuiltDividerPosition(managedItemCount:)``.
    private func recoverCollapsedHiddenSectionIfNeeded(
        hiddenSectionHasRoom: Bool,
        controlItems: ControlItemPair,
        managedItemCount: Int
    ) -> Bool {
        // A provisional reading must not advance, reset, or re-arm the
        // recovery episode. Only authoritative observations may mutate it.
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
        let seedPosition = Self.seedPositionForRebuiltDivider(managedItemCount: managedItemCount)
        MenuBarItemManager.diagLog.warning(
            "Hidden section remained collapsed for \(hiddenSectionCollapseStreak) authoritative cache passes; rebuilding H_ctrl\(Self.seedDescription(seedPosition))"
        )
        hiddenControlItem.recreateStatusItem(preferredPosition: seedPosition)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
        return true
    }

    /// Rebuilds an authoritatively identified hidden divider after it remains
    /// parked through repeated layout applies that need it on the bar.
    ///
    /// `managedItemCount` decides whether the rebuild may also re-stamp the
    /// seeded position. See ``canSeedRebuiltDividerPosition(managedItemCount:)``.
    func recoverParkedHiddenDividerIfNeeded(
        hiddenBoundaryMismatch: Int,
        hiddenControlItem: MenuBarItem,
        screenFrames: [CGRect],
        managedItemCount: Int
    ) -> Bool {
        guard hiddenBoundaryMismatch > 0,
              !LayoutSolver.isOnScreen(bounds: hiddenControlItem.bounds, screenFrames: screenFrames)
        else {
            parkedHiddenDividerMismatchStreak = 0
            didRecoverParkedHiddenDividerForCurrentMismatch = false
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
        let seedPosition = Self.seedPositionForRebuiltDivider(managedItemCount: managedItemCount)
        MenuBarItemManager.diagLog.warning(
            "H_ctrl remained parked through \(parkedHiddenDividerMismatchStreak) authoritative mismatch applies; rebuilding it\(Self.seedDescription(seedPosition))"
        )
        hiddenControl.recreateStatusItem(preferredPosition: seedPosition)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            // The unfinished batch that exposed the parked divider may have
            // stamped the move cooldown. This recovery owns its retry, so let
            // the fresh divider reach applySavedLayout instead of committing
            // its new window ID without verifying the saved boundary.
            await self?.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                bypassSavedLayoutCooldown: true
            )
        }
        return true
    }

    /// Whether bundleID owns a menu bar item Thaw already tracks: an entry
    /// in identifiers (each formatted "namespace:title") whose namespace is
    /// exactly bundleID. The trailing ":" anchors the match so one bundle ID
    /// can't be a loose prefix of another (org.x.fdm6 must not match
    /// org.x.fdm6x:Item-0). Used to arm relaunch settling only for apps whose
    /// status item actually churns the bar when they relaunch.
    static nonisolated func tracksMenuBarItem(bundleID: String, in identifiers: Set<String>) -> Bool {
        identifiers.contains { $0.hasPrefix(bundleID + ":") }
    }

    /// A Boolean value indicating whether `item`'s CG-side identity is
    /// degraded: either a Control-Center generic `Item-N` placeholder title,
    /// or a bundle-id-shaped title (reverse-DNS, three-plus dot-separated
    /// components — the same shape `86f2514e`'s title-identity fallback
    /// matches on the service side).
    private static func isDegradedIdentity(_ item: MenuBarItem) -> Bool {
        if item.tag.isControlCenterGenericItem {
            return true
        }
        guard let title = item.title else { return false }
        return title.split(separator: ".").count >= 3
    }

    /// Populates `degradedItemAXIdentities` for `items` whose CG-side
    /// identity is degraded, at most once per `cacheItemsRegardless` pass
    /// and only when at least one degraded item is present. Takes an
    /// on-demand AX snapshot of Control Center and SystemUIServer (the hosts
    /// responsible for the degraded cases this targets) and records the
    /// confident correlation for each degraded item's window bounds.
    ///
    /// This map is additive and display-only — see its declaration.
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
    /// logical state, or `nil` when both sections agree.
    ///
    /// See ``isMidSectionTransition(dividerWidth:isSectionCollapsed:)`` for why
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
    /// See ``recentItemWindowIDCycles`` for why continuity is judged over
    /// several cycles rather than only the preceding one.
    ///
    /// - Parameter items: The items enumerated this cycle, after clones and
    ///   ghost control windows have been dropped.
    ///
    /// - Returns: Every windowID enumerated within the last
    ///   ``recentWindowIDCycleWindow`` cycles, including this one.
    private func recordRecentItemWindowIDs(_ items: [MenuBarItem]) -> Set<CGWindowID> {
        recentItemWindowIDCycles.append(Set(items.lazy.map(\.windowID)))
        while recentItemWindowIDCycles.count > MenuBarItemManager.recentWindowIDCycleWindow {
            recentItemWindowIDCycles.removeFirst()
        }
        return recentItemWindowIDCycles.reduce(into: Set()) { $0.formUnion($1) }
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        skipRecentMoveCheck: Bool = false,
        resolveSourcePID: Bool = true,
        skipSavedLayoutApply: Bool = false,
        bypassSavedLayoutCooldown: Bool = false,
        waiterToken: Int? = nil
    ) async {
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil), resolveSourcePID=\(resolveSourcePID), skipSavedLayoutApply=\(skipSavedLayoutApply), bypassSavedLayoutCooldown=\(bypassSavedLayoutCooldown))"
        )

        guard skipRecentMoveCheck || !lastMoveOperationOccurred(within: .seconds(1)) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache due to recent item movement")
            return
        }

        guard !(appState?.isDraggingMenuBarItem ?? false) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: user is cmd-dragging")
            return
        }

        // Serialization gate: drop concurrent calls while a previous cache
        // cycle is in flight. Without this, a call that starts during a
        // relocation move by another call may snapshot pre-move positions.
        guard await cacheGate.begin() else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, skipping")
            return
        }
        defer { Task { await cacheGate.end() } }

        // Ownership of the waiter (if any) defaults to this call. Some
        // paths below (relocation hand-offs) hand ownership to a nested
        // recache below. Resuming from `defer` means every exit path from
        // here on — including early returns that cached nothing — releases
        // the waiter rather than stranding it. A caller that bailed before
        // the gate above never took ownership, so it cannot resume a waiter
        // that isn't its to resume.
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

        var items = await MenuBarItem.getMenuBarItems(
            option: .activeSpace,
            resolveSourcePID: resolveSourcePID
        )

        if items.isEmpty {
            // Retry once after a small delay if we got zero items. This can happen
            // due to transient WindowServer glitches or during display reconfigurations.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
            try? await Task.sleep(for: .milliseconds(250))
            items = await MenuBarItem.getMenuBarItems(
                option: .activeSpace,
                resolveSourcePID: resolveSourcePID
            )

            // Still nothing, but the cache holds items. The menu bar does not
            // empty itself, so this is the `.activeSpace` filter resolving a
            // space ID that no longer matches the windows (a Space switch, a
            // display reconfiguration). Replacing a populated cache with the
            // empty reading is what blanks the layout editor mid-session
            // (#851); hold the last known good cache and let the next cycle
            // read the menu bar again.
            if items.isEmpty, !itemCache.managedItems.isEmpty {
                MenuBarItemManager.diagLog.warning(
                    "cacheItemsRegardless: getMenuBarItems returned ZERO items twice, keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
                )
                return
            }
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: getMenuBarItems returned \(items.count) items")

        // Drop System Status Item Clone windows before any downstream
        // processing. These are transient duplicates the WindowServer
        // spawns during screen capture and menu bar animations. Each one
        // carries a fresh windowID and a nil source PID, and resolves to
        // an unstable namespace, so they must never be cached, assigned to
        // a section, placed via planUnmanagedPlacement, or moved. Removing
        // them here also keeps their windowIDs out of the stored set
        // below, so a clone appearing or vanishing can't trip the
        // windowID-change trigger that dispatches a bulk re-layout.
        let cloneWindowIDs = Set(items.filter(\.isSystemClone).map(\.windowID))
        if !cloneWindowIDs.isEmpty {
            let cloneDescriptions = items.filter(\.isSystemClone).map(\.tag.description)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: dropping \(cloneWindowIDs.count) system clone window(s): \(cloneDescriptions)")
            items.removeAll(where: \.isSystemClone)
        }

        // A duplicate Thaw process (or windows left by one that crashed) can
        // expose control-item titles under foreign window IDs. Exclude those
        // windows from every cache decision so they cannot be treated as new
        // unmanaged items or make the normal window-ID comparison churn.
        let ghostControlWindowIDs = dropGhostControlItemWindows(from: &items)

        // A reading whose items are titled after their own owners identifies
        // nothing, and caching it rewrites the whole bar under a second set of
        // identifiers that no later reading will match (#881, #927). Same
        // treatment as the empty reading above: this is a failed observation,
        // not the bar changing, so hold the last known good cache and read
        // again next cycle. Only once there is a cache to hold — on a first
        // launch there is nothing better to fall back to.
        if !itemCache.managedItems.isEmpty,
           LayoutSolver.liveIdentitiesAreDegraded(items.map { ($0.tag.namespace.description, $0.tag.title) })
        {
            MenuBarItemManager.diagLog.warning(
                "cacheItemsRegardless: reading titles items after their own owners (\(items.count) item(s)); keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
            )
            return
        }

        // Recorded only after clones and ghost windows are dropped, so their
        // throwaway windowIDs never enter the continuity history.
        let recentWindowIDs = recordRecentItemWindowIDs(items)

        // Reconcile resolved sourcePIDs against previously known values to
        // prevent transient resolution errors (e.g. stale AX data after item
        // moves) from corrupting item identities. SourcePIDCache does spatial
        // matching between CG windows and AX extras menu bar children, which
        // can produce wrong matches when AX positions lag behind CG updates.
        // A cached PID from a previous stable cycle is more trustworthy.
        if resolveSourcePID {
            let previousPIDs = cacheActor.cachedItemPIDs
            for i in items.indices {
                let item = items[i]
                guard !item.isControlItem else { continue }
                if let prevPID = previousPIDs[item.windowID],
                   let currentPID = item.sourcePID,
                   currentPID != prevPID
                {
                    // Only a live previous PID is more trustworthy than a
                    // fresh resolution. When the app behind it has exited —
                    // an item's owner relaunching, or Control Center itself
                    // respawning and recreating every status item, both seen
                    // in the #854 logs — reverting pins the item to a dead
                    // process, and every event addressed to it goes nowhere.
                    // Take the new PID in that case; there is nothing left to
                    // protect.
                    guard Self.previousPIDIsLive(prevPID) else {
                        MenuBarItemManager.diagLog.info(
                            "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID); previous PID is dead, accepting the new one"
                        )
                        continue
                    }
                    MenuBarItemManager.diagLog.warning(
                        "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID), reverting to previous PID"
                    )
                    // Rebuild the namespace from the previous PID. If the bundle
                    // ID is not available (app no longer running), keep the
                    // original tag namespace as a safe fallback.
                    let prevBundleID = NSRunningApplication(processIdentifier: prevPID)?.bundleIdentifier
                    let correctedNamespace: MenuBarItemTag.Namespace = if let prevBundleID {
                        .string(prevBundleID)
                    } else {
                        item.tag.namespace
                    }
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
                        sourcePID: prevPID,
                        bounds: item.bounds,
                        title: item.title,
                        isOnScreen: item.isOnScreen
                    )
                }
            }
        }

        // When sourcePID resolution changes an item's identifier (e.g. from
        // com.apple.controlcenter:Item-0:4 to pl.maketheweb.cleanshotx:Item-0),
        // the new identifier won't be in knownItemIdentifiers. Seed it now so
        // the item isn't treated as a "new" item by relocateNewLeftmostItems.
        // Skip items with unresolved sourcePID so the placeholder
        // "com.apple.controlcenter" namespace never enters the persisted set.
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

        // currentItemWindowIDs comes straight from the bridging window list
        // and may still contain clone or ghost IDs. Keep the stored set in
        // sync with the managed item set and ignore those transient IDs in
        // the next raw-list comparison.
        let itemWindowIDs = (currentItemWindowIDs ?? items.reversed().map(\.windowID))
            .filter { !cloneWindowIDs.contains($0) && !ghostControlWindowIDs.contains($0) }
        // NOTE: cacheActor.updateCachedItemWindowIDs/updateCachedCloneWindowIDs
        // are deliberately NOT called here. Committing them this early, before
        // the ControlItemPair guard below is known to succeed, would make
        // cacheItemsIfNeeded's change detector see cachedIDs == itemWindowIDs
        // on the very next poll even though this cycle failed to find the
        // control items. That desensitizes the detector right when recovery
        // depends on it, since a failed cacheItemsRegardless call otherwise
        // looks identical to a successful one from the detector's point of
        // view. The commit happens only after the guard succeeds, below.

        await MainActor.run {
            MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
            self.pruneMoveOperationTimeouts(keeping: Set(items.map(\.tag)))
            self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
        }

        // Obtain window IDs from the actual ControlItem objects so the
        // fallback lookup in ControlItemPair can match by window ID when
        // the tag-based and title-based lookups fail (macOS 26+).
        let hiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .hidden)?.window?.windowNumber
        let alwaysHiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window?.windowNumber
        let hiddenControlItemWID = hiddenControlItemWindowNumber.flatMap { CGWindowID(exactly: $0) }
        let alwaysHiddenControlItemWID = alwaysHiddenControlItemWindowNumber.flatMap { CGWindowID(exactly: $0) }

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
        ) else {
            // Recovery path (#754): a failed lookup here used to wipe
            // itemCache and commit the just-fetched window-ID snapshot to
            // the change detector, which together made the failure
            // permanent — the cache stayed empty, and cacheItemsIfNeeded
            // saw no further change to re-drive a recache. Instead: keep
            // the last-known-good itemCache (consumers key visible UI off
            // areControlItemsMissing, not off an empty cache; see
            // MenuBarLayoutSettingsPane), leave the window-ID snapshot
            // uncommitted so the detector re-fires on the next poll, and
            // count consecutive failures. After controlItemRebuildThreshold
            // in a row, the backing NSStatusItems are rebuilt outright,
            // since a lookup that keeps failing across independently
            // triggered cache cycles means the status items themselves are
            // gone (e.g. their windowNumber no longer matches any
            // enumerated CG window ID), not that this one cycle raced a
            // transient WindowServer update.
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
                // Schedule one immediate recache so the freshly rebuilt
                // status items are picked up right away rather than waiting
                // for the next externally triggered cache cycle. Briefly wait
                // first so the deferred cacheGate.end() from this cycle can
                // complete (otherwise the recache is dropped at the gate) and
                // the newly created NSStatusItems can register their windows.
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
            cacheActor.updateCachedItemWindowIDs(itemWindowIDs)
            cacheActor.updateCachedCloneWindowIDs(cloneWindowIDs.union(ghostControlWindowIDs))
            cacheActor.updateCachedControlCenterGenericWindowIDs(
                Set(items.filter(\.tag.isControlCenterGenericItem).map(\.windowID))
            )
        }

        await MainActor.run {
            self.areControlItemsMissing = false
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

        // A display change can strand the always-hidden divider on another
        // screen's menu bar while the hidden divider resolves fine.
        // ControlItemPair models the missing divider as an optional, so the
        // pair succeeds and the lookup-failure rebuild above never fires:
        // #863's HDMI re-plug left alwaysHidden=nil for 12+ hours and the
        // whole always-hidden section drained into visible. Only
        // authoritative cycles may advance, reset, or re-arm the episode —
        // a provisional correlation says nothing either way, the same rule
        // the parked-divider streak applies — and a disabled section's
        // absent divider is intentional, not a loss to recover from.
        if controlItems.canRepositionControlItems {
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

        await enforceControlItemOrder(controlItems: controlItems)

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled before relocateNewLeftmostItems")
            return
        }

        // App-relaunch detection: uniqueIdentifier is namespace:title
        // (windowID-independent and stable across restarts), so a
        // relaunched app keeps the same identifier and would be filtered
        // out of newProfileItems by profileSortedItemIdentifiers in the
        // late-arrival check below. A windowID not in previousWindowIDs
        // for a profile-tracked item means the app re-registered its
        // NSStatusItem at whatever position macOS chose, which is
        // usually not the saved profile position. Drop such identifiers
        // from the sorted snapshot so the late-arrival path picks them
        // up. Run this BEFORE the relocate/restore early returns: those
        // paths schedule a recache after which previousWindowIDs already
        // contains the freshly registered windowID, and the signal would
        // be lost.
        //
        // Position-check refinement: a fresh windowID does not always
        // mean the item is at the wrong position. Idle wake, AX
        // rebinding, and some app lifecycle events recreate the
        // underlying NSStatusItem while macOS retains the original
        // visual position. The earlier unconditional drop fired a
        // full re-sort (which can replan many moves across the bar)
        // on every such event, even when the item was already at its
        // profile-expected section. Gate the drop on a section
        // mismatch: keep items whose current section matches the
        // profile spec, drop only items that genuinely landed in the
        // wrong section. Items whose current section can't be
        // determined (transient bounds during in-flight moves) fall
        // through to the drop path, preserving the original
        // conservative behaviour for ambiguous cases.
        if let activeLayout = activeProfileLayout,
           !activeProfileItemIdentifiers.isEmpty,
           !previousWindowIDs.isEmpty
        {
            let previousWindowIDSet = Set(previousWindowIDs)
            let hiddenMinX = controlItems.hidden.bounds.minX
            let hiddenMaxX = controlItems.hidden.bounds.maxX
            let ahBounds = controlItems.alwaysHidden?.bounds

            // Build per-identifier expected-section lookup from the
            // active profile spec. itemOrder is keyed by section
            // string ("visible" / "hidden" / "alwaysHidden") with
            // identifier arrays for each section.
            var expectedSectionByID = [String: String]()
            for (sectionKey, ids) in activeLayout.itemOrder {
                for id in ids {
                    expectedSectionByID[id] = sectionKey
                }
            }

            /// Spatial classification mirrors currentLayoutDivergesFromSaved:
            /// visible is right of hiddenCtrl; alwaysHidden is left of
            /// ahCtrl when present; hidden is between the two control
            /// items (or anything left of hiddenCtrl when ahCtrl is
            /// disabled). Items straddling a divider return nil to
            /// avoid false positives during transient section
            /// show/hide animations.
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
                        // If the item is already at its profile-
                        // expected section, the windowID change was
                        // benign; no re-sort needed. Items whose
                        // current section can't be determined fall
                        // through to the drop path.
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

        if await relocateNewLeftmostItems(
            items,
            controlItems: controlItems,
            previousWindowIDs: previousWindowIDs,
            recentWindowIDs: recentWindowIDs
        ) {
            MenuBarItemManager.diagLog.debug("Relocated new leftmost items; scheduling recache")
            // Ownership transfers to the nested recache: the waiter must not
            // be told the cache is settled until the second cycle finishes.
            ownsWaiter = false
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                // Carry the bypass across the hand-off: this recache is where the
                // launch restore actually runs, and the move it is retrying behind
                // was stamped by the relocation just above.
                await self?.cacheItemsRegardless(
                    skipRecentMoveCheck: true,
                    bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                    waiterToken: waiterToken
                )
            }
            return
        }

        if await relocatePendingItems(items, controlItems: controlItems) {
            MenuBarItemManager.diagLog.debug("Relocated pending temporarily-shown items; scheduling recache")
            // Ownership transfers to the nested recache: the waiter must not
            // be told the cache is settled until the second cycle finishes.
            ownsWaiter = false
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                await self?.cacheItemsRegardless(
                    skipRecentMoveCheck: true,
                    bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                    waiterToken: waiterToken
                )
            }
            return
        }

        // Skip all restore logic during the startup settling period.
        // The settling period prevents cascading icon moves when many apps
        // load at login or restart in quick succession (app update checks).
        // A final cacheItemsRegardless() after the period ends handles restore.
        guard !isInStartupSettling else {
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)
            // Absorb items that appear during settling into the profile
            // snapshot so they aren't treated as late arrivals afterwards.
            if activeProfileLayout != nil {
                for item in items where !item.isControlItem {
                    profileSortedItemIdentifiers.insert(item.uniqueIdentifier)
                }
            }

            // One early apply restricted to items we can already identify,
            // rather than leaving the bar in macOS's arrangement for the
            // whole settling period. Waiting for every sourcePID means the
            // user watches an unsaved layout for as long as resolution takes
            // — ~8 s on a dense bar (#881). Restricted so the items still
            // being resolved are not move targets; the settling-end pass
            // runs unrestricted and LCS leaves whatever this placed alone.
            // The cooldown is bypassed rather than inherited from the caller.
            // relocateThawIcon moves our own control item within the first
            // ~100 ms of launch, so every settling poll that reaches here is
            // inside the 5 s window that same launch just stamped, and no
            // settling-period call site sets bypassSavedLayoutCooldown. In the
            // #881 log the early apply was rejected at 19.457 for a cooldown
            // stamped at 16.375 by relocateThawIcon, which left the reporter
            // watching macOS's arrangement for the whole settling period and
            // then the entire reorder as a visible sequence. Cascading
            // re-applies, which is what the cooldown guards against, cannot
            // happen here: this runs once per settling period.
            if !skipSavedLayoutApply, !didAttemptEarlySavedLayoutApply {
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
                    resolvedIdentitiesOnly: true
                )
                // Spend the one attempt only on a dispatch that happened. The
                // flag used to be set before the call, so an apply rejected by
                // a guard consumed it and no later poll retried.
                if didApply {
                    didAttemptEarlySavedLayoutApply = true
                    MenuBarItemManager.diagLog.debug(
                        "cacheItemsRegardless: early saved-layout apply dispatched during settling"
                    )
                    return
                }
            }

            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: startup settling active, skipping restore")
            return
        }

        // Unified saved-layout restore: dispatch the bulk apply path
        // when window IDs have changed (app relaunch). applySavedLayout
        // owns its own cooldown and guard checks; applyProfileLayout's
        // body arms isRestoringItemOrder around the moves and drives
        // its own follow-up recache. On rejection the flag is left
        // false so saveSectionOrder can persist the current cache.
        //
        // The skipSavedLayoutApply gate exists so the post-apply
        // refresh scheduled by scheduleDeferredCacheRefresh does NOT
        // re-enter applySavedLayout. Without the gate the deferred
        // refresh runs cacheItemsRegardless → applySavedLayout →
        // dispatch → schedule another refresh, and because consecutive
        // getMenuBarItems calls can return slightly different windowID
        // sets (transient Apple Control Center widgets churn windowIDs
        // even when the visible item count is stable),
        // windowIDsChanged fires on every iteration and the bar enters
        // an infinite no-op apply loop.
        if !skipSavedLayoutApply {
            let didApplySavedLayout = await applySavedLayout(
                items: items,
                previousCycle: PreviousCacheCycle(
                    windowIDs: previousWindowIDs,
                    displayID: itemCache.displayID,
                    ccGenericWindowIDs: previousCCGenericWindowIDs
                ),
                controlItems: controlItems,
                currentDisplayID: displayID,
                bypassMoveCooldown: bypassSavedLayoutCooldown
            )
            if didApplySavedLayout {
                return
            }
        }

        await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)

        // Persist the resolved (possibly corrected) sourcePIDs for the next
        // cache cycle so transient resolution errors can be detected.
        // Only update when sourcePIDs were actually resolved; the settle-end
        // fast restore (resolveSourcePID=false) must not overwrite the baseline.
        if resolveSourcePID {
            // Keyed by first occurrence: macOS can briefly report the same
            // window twice around a move, and trapping on the duplicate
            // would take the whole cache cycle down with it.
            let newPIDs = Dictionary(
                items.compactMap { item in
                    item.sourcePID.map { (item.windowID, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            cacheActor.updateCachedItemPIDs(newPIDs)
        }

        // Detect late-arriving items that belong to the active profile.
        if activeProfileLayout != nil,
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

        // Keep the visible row inside the beside-notch budget regardless of
        // whether a profile is active. Runs last so it sees the settled cache,
        // and self-gates on every in-flight mover.
        await rebalanceNotchOverflowIfNeeded(items: items, controlItems: controlItems)
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        let rawWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        // Exclude windowIDs already known to be system clones so their
        // churn doesn't read as a layout change. A brand-new clone whose
        // windowID hasn't been learned yet still triggers one recache,
        // which resolves it, records it, and drops it; from then on its
        // presence and removal are ignored.
        let cloneIDs = cacheActor.cachedCloneWindowIDs
        let itemWindowIDs = cloneIDs.isEmpty
            ? rawWindowIDs
            : rawWindowIDs.filter { !cloneIDs.contains($0) }
        let cachedIDs = cacheActor.cachedItemWindowIDs

        // An empty reading against a populated cache is a failed observation,
        // not the menu bar emptying out. The `.activeSpace` filter resolves
        // the space ID separately from the window list, so during a Space
        // switch it matches the outgoing space and nothing passes the filter
        // — the next reading, milliseconds later, returns the full set again.
        // Treating the zero as real is what makes the layout editor blink its
        // items away and back while it sits open (#851).
        if itemWindowIDs.isEmpty, !cachedIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsIfNeeded: ignoring empty window ID reading against \(cachedIDs.count) cached, likely a Space switch"
            )
            return
        }

        if cachedIDs != itemWindowIDs {
            // While control-item lookups keep failing, the uncommitted
            // snapshot makes this branch fire on every poll; #933 measured
            // 27 hours of full recaches every 3 seconds against a failure
            // that was not going away. Skip silently inside the backoff
            // window — each attempt that does run logs its failure with the
            // streak count, so the lengthening gaps stay visible in the log.
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
    /// The window ID comparison above asks whether the *set* of items changed.
    /// It cannot see a change in what is known *about* an item, and an item's
    /// source process is not read off its window — it is resolved by an AX scan
    /// in the XPC service that routinely misses on the first cold pass, because
    /// other apps' accessibility trees are still warming up seconds after login.
    ///
    /// A miss is not cosmetic. ``MenuBarItem/hasProvisionalIdentity`` spells out
    /// what an item is without its source: the namespace falls back to the owner
    /// of the window, which on macOS 26 is Control Center for every hosted status
    /// item, and the display name falls back to "Menu Bar Item". Both are wrong,
    /// and both were permanent — the item's window never goes anywhere, so no
    /// window ID ever changed, so nothing recached it, and a relaunch was the only
    /// way to get the real name back.
    ///
    /// ``SourcePIDNegativeCachePolicy`` was built for exactly this: it shortens
    /// the first retry deadlines so a warmer scan can land, and its own reasoning
    /// names the failure it cannot fix from that side — "the app stops requesting
    /// once settled". This is the app not stopping. The probe costs one XPC round
    /// trip per tick while anything is still unresolved and nothing at all once
    /// everything has resolved; the ladder is what bounds how often a request
    /// behind it becomes a real scan.
    private func recacheIfSourceProcessesResolved(_ itemWindowIDs: [CGWindowID]) async {
        let probeWindowIDs = Self.windowIDsNeedingSourceResolution(
            cachedItems: itemCache.managedItems,
            currentWindowIDs: itemWindowIDs
        )
        guard !probeWindowIDs.isEmpty else {
            return
        }

        // Second guard on the same rule as the filter above, against a title
        // this side can see and a cached item cannot: a duplicate Thaw process
        // can leave control-item windows behind under foreign window IDs.
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
    /// Read from the cache rather than by differencing window IDs against the
    /// resolved-PID map, because these are the items actually on display under a
    /// provisional identity, and because the set can only shrink as they resolve
    /// — a probe can never talk the cache into recaching what it just cached.
    ///
    /// Control items are excluded for the reason
    /// ``MenuBarItem/getMenuBarItems(on:option:resolveSourcePID:)`` excludes them
    /// from resolution in the first place: their AX children are disabled
    /// dividers, so a request for one is a guaranteed miss that can start a full
    /// scan of every running app, and their PID is known locally anyway.
    ///
    /// Restricted to `currentWindowIDs` so an item the cache is still holding
    /// after its window is gone cannot keep the probe alive on its own.
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
