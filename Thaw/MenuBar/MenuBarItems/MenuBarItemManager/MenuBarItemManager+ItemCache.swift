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

        /// Confirmed window/source incarnations from the previous cache cycle.
        /// These detect and correct transient source-PID resolution errors
        /// without trusting a recycled window ID or PID by itself.
        private(set) var cachedSourcePIDBaselines = [CGWindowID: SourcePIDSeed]()

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

        /// Source-PID seeds already written during this app session.
        private(set) var persistedSourcePIDSeeds: [SourcePIDSeed]?

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

        /// Updates the confirmed window/source incarnations.
        func updateCachedSourcePIDBaselines(_ baselines: [CGWindowID: SourcePIDSeed]) {
            cachedSourcePIDBaselines = baselines
        }

        /// Records a seed snapshot and reports whether it needs persistence.
        func updatePersistedSourcePIDSeeds(_ seeds: [SourcePIDSeed]) -> Bool {
            guard seeds != persistedSourcePIDSeeds else { return false }
            persistedSourcePIDSeeds = seeds
            return true
        }

        /// Returns the last persisted snapshot, loading it once per process.
        /// Priming this cache avoids one redundant defaults write on the first
        /// successful enumeration after launch.
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

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
            cachedSourcePIDBaselines.removeAll()
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
                self.alwaysHidden = Self.resolveAlwaysHidden(
                    in: &items,
                    authoritativeWindowID: alwaysHiddenControlItemWindowID
                )
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

            // Duplicate same-title divider windows cannot be disambiguated by
            // tag or source PID: on Tahoe, Control Center hosts both the stale
            // and current windows, and enumeration stamps both as this process.
            // AppKit may expose a synthetic windowNumber that does not fit in a
            // CGWindowID, so the authoritative-ID paths above are unavailable.
            // Only current-process AX frames can break the tie; otherwise keep
            // the last-known-good cache instead of adopting an arbitrary (often
            // older, lower-numbered) divider.
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

        /// Control-item titles that occur more than once in one enumeration.
        /// A title is the stable channel available when AppKit's window number
        /// is synthetic, but it cannot distinguish current and stale windows.
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

        /// Resolves the always-hidden control item once the hidden divider is
        /// claimed.
        ///
        /// With an authoritative window ID — Thaw's own `NSStatusItem` window
        /// — the item is taken from the enumerated list when present. When
        /// absent, it is recovered from the window server via
        /// `ownControlItem` (#991): the window still exists while it is
        /// parked offscreen (collapsed section) or filtered off the active
        /// space, which is exactly the state the divider sits in across a
        /// relaunch, when every profile apply needs it. Tag matching is
        /// deliberately skipped in that case: a known-but-absent
        /// authoritative ID must not adopt a lookalike window from a
        /// duplicate Thaw instance. Without an authoritative ID, the
        /// remaining list is tag-matched as before.
        ///
        /// `recovery` is the window-server lookup, a parameter so tests can
        /// substitute a fixture — the unit target owns no real windows.
        ///
        /// Returns `nil` when the window is absent and unknown to the window
        /// server (torn-down status item, disabled section) — the honest
        /// answer; a stale ID must not be dressed up as a live item.
        ///
        /// Zero counts as no ID (`kCGNullWindowID`): a status item whose
        /// window has not been created yet converts to it through
        /// `CGWindowID(exactly:)`, and recovering or window-matching against
        /// it would only ever fail.
        ///
        /// Without a usable ID, the remaining list is matched by our own
        /// process plus the canonical title first — the same identity
        /// channel the pair's sourcePID fallback uses for the hidden
        /// divider, and the one that still answers when the hosted title
        /// drifts from the autosave name — falling back to plain tag
        /// matching.
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
            // The ID is non-nil and absent from the list — the same decision
            // `shouldRecoverOwnControlItem` encodes for the hidden divider.
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
                let matches = candidates.filter { candidate in
                    !matchedIndices.contains(candidate.index)
                        && candidate.isOwnProcess
                        && !candidate.isVisibleControlItem
                        && AXIdentityCatalog.identity(for: candidate.bounds, in: identity) != nil
                }
                // More than one candidate for a current-process frame is not
                // corroboration. Refuse the whole correlation rather than let
                // array/window-number order decide which divider is current.
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

    /// Converts AppKit's status-item window number only when it is an exact
    /// WindowServer identifier. Tahoe can surface a larger synthetic number;
    /// treating it as sortable identity would let a stale divider win.
    static nonisolated func authoritativeControlItemWindowID(
        windowNumber: Int
    ) -> CGWindowID? {
        guard windowNumber > 0 else { return nil }
        return CGWindowID(exactly: windowNumber)
    }

    /// Returns windows that claim this instance's own namespace without
    /// being one of its status items.
    ///
    /// Control Center can outlive the Thaw process whose status item it
    /// hosted and keep serving that window. #1032's reporter carried one —
    /// `com.stonerl.Thaw:com.stonerl.Thaw`, window 639 — across relaunches
    /// until `killall ControlCenter` cleared it. Nothing about it is usable:
    /// it captures no image, and a move anchored on it can never verify.
    ///
    /// Two things took it for real, and the second is what made the session
    /// unusable. It was planned against as an unmanaged item, so live items
    /// were moved relative to a window with no owner. And it is self-titled
    /// under our own namespace, which is the first signal
    /// ``LayoutSolver/liveIdentitiesAreDegraded(_:)`` reads as a bar-wide
    /// `kCGWindowName` degradation — so 436 readings across the reporter's
    /// three logs were rejected as degraded and the cache never left the
    /// state it was in when the orphan appeared. Dropping the window here
    /// keeps it out of that check, which already expects ghost windows to
    /// be gone by the time it runs.
    ///
    /// Ownership is decided by window number, never by title, so one of our
    /// control items whose title really has degraded stays in the reading
    /// and still reaches the degradation check. Like
    /// ``ghostControlItemWindowIDs(in:ownWindowIDsByTitle:)``, the filter is
    /// self-validating: with none of our own windows present there is no
    /// baseline to call anything an orphan against, so nothing is dropped.
    ///
    /// ``LayoutSolver`` applies the same rule to the persisted side, where
    /// the misattribution is written rather than observed.
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
        // Window ownership, not the title, decides what is ours. A spacer
        // whose window is up before its title answers here and nowhere else.
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
        // Layout-editor refreshes are read-and-publish passes. They must not
        // advance the recovery episode or reach its status-item rebuild and
        // automatic-recache side effects.
        guard !suppressAutomaticMoves else { return false }
        guard let hostUptime else { return true }
        return hostUptime >= grace
    }

    /// Selects the exact newest host when launch handoff briefly exposes more
    /// than one Control Center process. `runningApplications` has no ordering
    /// contract, so using its first entry can select the process being retired.
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

    /// Re-arms divider recovery when Control Center changes process generation.
    /// The old process's spent rebuild latch cannot govern a new host whose
    /// status-item windows are being created from scratch.
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

        // `midTransitionSection` can suspend while a user move completes.
        // Never publish or persist the observation it was validating if that
        // move made the underlying geometry obsolete in the meantime.
        guard snapshotIsCurrent() else { return }

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

        if !suppressAutomaticMoves,
           recoverCollapsedHiddenSectionIfNeeded(
               hiddenSectionHasRoom: hiddenSectionHasRoom,
               controlItems: context.controlItems,
               // The dividers are excluded: a rebuild that only has the two
               // control items to place cannot strand anything on the wrong
               // side of the one it is rebuilding.
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

        if cacheChanged {
            itemCache = context.cache

            // Remember what the resolved items are called, so the next launch
            // can label them before its own source-PID scan lands (#956).
            MenuBarItemNameMemory.remember(itemCache.managedItems)
        } else {
            MenuBarItemManager.diagLog.debug(
                "Menu bar item cache is unchanged; evaluating saved-order persistence for a validated Layout-editor move"
            )
        }

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
        } else if suppressSavedOrderPersistence {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; this cache refresh follows a failed automatic move attempt"
            )
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
        if cacheChanged {
            MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")
        }
        completedCacheCycles += 1
    }

    /// Whether a completed cache read must continue through the saved-order
    /// persistence gates. A validated Layout-editor move may already have
    /// published its settled geometry during validation, so its final refresh
    /// must not stop merely because the cache value is identical.
    static nonisolated func shouldEvaluateSavedOrderPersistence(
        cacheChanged: Bool,
        forcePersistSavedOrder: Bool
    ) -> Bool {
        cacheChanged || forcePersistSavedOrder
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
    /// The recovery used to take the Phase 1 boundary mismatch alone, which
    /// made it unreachable in the state it exists to repair (#978): a
    /// stranded divider reads as a zero-width hidden section, the zero-width
    /// guards in `applySavedLayout` and `applyProfileLayout` return before
    /// Phase 1 runs, so the mismatch was never computed and the streak never
    /// advanced. A refusal is itself evidence an apply wanted the divider on
    /// the bar and could not have it, so it counts the same as a mismatch.
    nonisolated enum ParkedDividerTrigger {
        /// Phase 1 found items on the wrong side of H_ctrl.
        case boundaryMismatch(Int)
        /// An apply refused upstream because the hidden section read as
        /// having no room between the dividers. `source` names the guard.
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
    /// "Parked" here means stranded: no edge of the divider's frame falls on
    /// any display (``LayoutSolver/isFullyOffScreen(bounds:screenFrames:)``).
    /// The leading-edge test is not enough — a healthy collapsed bar expands
    /// H_ctrl into an offscreen-reaching spacer, and reading that as parked
    /// would rebuild dividers that are doing their job (#978). Only a
    /// divider pushed past every item has both edges offscreen.
    ///
    /// `managedItemCount` and the stored control item positions decide what
    /// the rebuild does with the autosaved position. See
    /// ``MenuBarItemManager/seedForRebuiltDivider(managedItemCount:storedPositions:)``.
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

    /// Clears the parked-divider streak, so the next strand starts counting
    /// from zero and is allowed its own rebuild.
    ///
    /// Kept separate from the guard that discovers a healthy divider because
    /// Phase 1 also has to clear it, and clearing it there on a zero mismatch
    /// alone was half of why the recovery could never fire (#978): a divider
    /// stranded while the visible/hidden boundary was consistent had its
    /// streak reset on every cycle.
    func resetParkedHiddenDividerRecovery() {
        parkedHiddenDividerMismatchStreak = 0
        didRecoverParkedHiddenDividerForCurrentMismatch = false
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

        // Serialization gate: drop concurrent calls while a previous cache
        // cycle is in flight. Without this, a call that starts during a
        // relocation move by another call may snapshot pre-move positions.
        guard await cacheGate.begin() else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, skipping")
            return
        }
        defer { Task { await cacheGate.end() } }

        // Capture this only after the gate is ours. A cycle that was already
        // in progress when this call arrived must not make an editor refresh
        // look successful after this call itself was dropped.
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

        var enumeration = await MenuBarItem.getMenuBarItemsSnapshot(
            option: .activeSpace,
            resolveSourcePID: resolveSourcePID
        )
        var items = enumeration.items

        if items.isEmpty {
            // Retry once after a small delay if we got zero items. This can happen
            // due to transient WindowServer glitches or during display reconfigurations.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
            try? await Task.sleep(for: .milliseconds(250))
            enumeration = await MenuBarItem.getMenuBarItemsSnapshot(
                option: .activeSpace,
                resolveSourcePID: resolveSourcePID
            )
            items = enumeration.items

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

        // Layout-editor reconciliation only needs fresh geometry. Reuse a
        // confirmed identity for the same live window so that its fast cache
        // pass can skip the occasionally slow AX source-PID scan without
        // turning every icon into a new Control Center placeholder.
        if reuseCachedIdentities {
            items = Self.reusingCachedIdentities(
                in: items,
                from: itemCache.managedItems
            )
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
        var ghostWindowIDs = dropGhostControlItemWindows(from: &items)

        // A window Control Center kept serving for a Thaw process that is
        // gone reads as one of ours and is nothing of the sort. Drop it
        // before the degradation check below, which would otherwise read a
        // single permanent orphan as the whole bar having lost its names,
        // and hold a stale cache for as long as the orphan lasts (#1032).
        ghostWindowIDs.formUnion(dropOrphanedOwnNamespaceWindows(from: &items))

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

        // Enumeration is the slow portion of this pass. If any move landed
        // while it was suspended, everything below was computed from the old
        // bar and must be read-discard: do not update continuity ledgers,
        // publish cache state, restore layout, or launch an automatic move.
        guard snapshotIsCurrent("after item enumeration") else { return }

        // Recorded only after clones and ghost windows are dropped, so their
        // throwaway windowIDs never enter the continuity history.
        let recentWindowIDs = recordRecentItemWindowIDs(items)

        // Reconcile resolved sourcePIDs against previously known values to
        // prevent transient resolution errors (e.g. stale AX data after item
        // moves) from corrupting item identities. SourcePIDCache does spatial
        // matching between CG windows and AX extras menu bar children, which
        // can produce wrong matches when AX positions lag behind CG updates.
        // A cached PID from a previous stable cycle is more trustworthy.
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

        // The reconciliation above can change an item's namespace while
        // preserving its instanceIndex. If another live item already holds
        // that (namespace, title, instanceIndex) identity, two items collide
        // and windowless tag matching can select the wrong one. Regroup the
        // instance indices over the reconciled namespaces.
        if didReconcileSourcePID {
            MenuBarItem.assignStableInstanceIndices(to: &items, using: enumeration.windowsByID)
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
            .filter { !cloneWindowIDs.contains($0) && !ghostWindowIDs.contains($0) }
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
        guard snapshotIsCurrent("after cache pruning") else { return }

        // Obtain window IDs from the actual ControlItem objects so the
        // fallback lookup in ControlItemPair can match by window ID when
        // the tag-based and title-based lookups fail (macOS 26+).
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
                // A pure position change does not change the window-ID set, so
                // cacheItemsIfNeeded cannot discover it. Hand the waiter to an
                // explicit post-settle cycle instead of leaving itemCache at
                // the geometry observed before the divider move.
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
        if !suppressAutomaticMoves,
           let activeLayout = activeProfileLayout,
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
                    // Carry the caller policy across the hand-off: this recache
                    // is where the launch restore actually runs after a completed
                    // relocation. A failed accepted attempt gets one read-and-
                    // publish pass with movers suppressed so it cannot retry-loop.
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

        // Skip all restore logic during the startup settling period.
        // The settling period prevents cascading icon moves when many apps
        // load at login or restart in quick succession (app update checks).
        // A final cacheItemsRegardless() after the period ends handles restore.
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
            // Absorb items that appear during settling into the profile
            // snapshot so they aren't treated as late arrivals afterwards.
            if !suppressAutomaticMoves, activeProfileLayout != nil {
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

        // Persist the resolved (possibly corrected) sourcePIDs for the next
        // cache cycle so transient resolution errors can be detected.
        // Only update when sourcePIDs were actually resolved; the settle-end
        // fast restore (resolveSourcePID=false) must not overwrite the baseline.
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

        // Detect late-arriving items that belong to the active profile.
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

        // Keep the visible row inside the beside-notch budget regardless of
        // whether a profile is active. Runs last so it sees the settled cache,
        // and self-gates on every in-flight mover.
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
                // The cache above describes the pre-ejection geometry. Position
                // moves keep their window IDs, so the change detector cannot
                // discover the stale reading; explicitly hand the waiter and
                // caller policy to a fresh post-settle cycle.
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

    /// Performs the authoritative cache pass required before the Layout
    /// editor may thaw its source and destination rows after a user move.
    ///
    /// Ordinary background refreshes deliberately drop when ``CacheGate`` is
    /// busy. An editor move cannot: thawing from the old cache duplicates or
    /// removes the transferred icon until a later timer happens to repair it.
    /// Retry discrete attempts so the gate is released between each one and
    /// nested relocation recaches cannot deadlock this caller.
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
