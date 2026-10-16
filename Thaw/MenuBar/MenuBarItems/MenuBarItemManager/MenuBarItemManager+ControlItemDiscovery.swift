//
//  MenuBarItemManager+ControlItemDiscovery.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Cocoa

// MARK: - Control Item Discovery

extension MenuBarItemManager {
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
    func dropOrphanedOwnNamespaceWindows(from items: inout [MenuBarItem]) -> Set<CGWindowID> {
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
    func dropGhostControlItemWindows(from items: inout [MenuBarItem]) -> Set<CGWindowID> {
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
}
