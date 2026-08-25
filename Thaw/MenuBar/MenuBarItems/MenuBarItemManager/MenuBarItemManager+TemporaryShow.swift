//
//  MenuBarItemManager+TemporaryShow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    final class TemporarilyShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The PID used to match this item back on the bar at rehide time.
        let sourcePID: pid_t

        /// Every process that could plausibly own this item's interface.
        ///
        /// The process that owns an item's *window* and the one that owns the
        /// *menu* that window opens are not always the same. On macOS 26
        /// Control Center hosts the status item while the app draws the menu,
        /// so a lookup keyed on either PID alone misses. It matters most for
        /// an item whose `sourcePID` never resolved, where collapsing to a
        /// single PID via `?? ownerPID` yields Control Center's — and the
        /// app's open menu can then never be found, so the rehide tears it
        /// down (#924).
        ///
        /// ``ClickReactionVerifier/Snapshot/pids`` accepts both for the same
        /// reason; this keeps the two in agreement.
        let interfacePIDs: Set<pid_t>

        /// The display identifier where the item was shown.
        let displayID: CGDirectDisplayID

        /// The destination to return the item to (captured at show-time).
        /// This is the preferred destination, but may become stale if the
        /// target item has moved or disappeared by the time we rehide.
        let returnDestination: MoveDestination

        /// The neighbor on the opposite side of the ``returnDestination``,
        /// used as a secondary fallback to preserve relative ordering when
        /// the primary target is gone.
        let fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?

        /// The original section the item belonged to before being temporarily
        /// shown. Used as a last-resort fallback when both neighbor-based
        /// destinations are stale.
        let originalSection: MenuBarSection.Name

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// The number of times the item was not found on the active space.
        /// Tracked separately from ``rehideAttempts`` to allow more retries
        /// for the "item not found" case (the app may be on another space
        /// or temporarily invisible).
        var notFoundAttempts = 0

        /// The number of rehide checks that have found the interface
        /// ``InterfaceState/unknown``.
        ///
        /// Bounded by ``maxUndetectedInterfaceChecks`` so an item whose
        /// interface can never be identified still goes home rather than
        /// sitting in the visible section forever.
        var undetectedInterfaceChecks = 0

        /// How many `unknown` readings to sit through before rehiding anyway.
        ///
        /// The checks are three seconds apart, so this trades roughly the
        /// length of the ordinary rehide timer against tearing down a menu
        /// that is open but unidentifiable. An item that lingers too long is
        /// a far cheaper failure than a menu that closes underneath the user.
        static let maxUndetectedInterfaceChecks = 4

        /// Timestamp for when the item was first shown so we can honor
        /// a short grace period for menus that use nonstandard windows.
        private let firstShownDate = Date.now

        /// Minimum time to treat the item as "showing" even if we can't
        /// detect a popup window (helps apps with unusual window levels).
        private let graceInterval: TimeInterval = 2

        /// What is known about the item's interface.
        enum InterfaceState {
            /// A window belonging to the item was observed on screen.
            case showing

            /// The interface was identified and is no longer on screen, so it
            /// has been closed or dismissed. Positive evidence.
            case absent

            /// The interface was never identified: nothing was captured when
            /// the item was clicked and nothing can be found now.
            ///
            /// Distinct from ``absent`` because it is an admission of
            /// ignorance rather than an observation. Rehiding on it is a
            /// guess, and when the guess is wrong the user loses the menu
            /// they just opened (#924).
            case unknown
        }

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
            interfaceState == .showing
        }

        /// What is currently known about the item's interface.
        var interfaceState: InterfaceState {
            // First check the tracked popup window; this is the most
            // reliable signal when available.
            if let window = shownInterfaceWindow,
               let current = WindowInfo(windowID: window.windowID)
            {
                if current.layer == CGWindowLevelForKey(.popUpMenuWindow)
                    || current.layer == CGWindowLevelForKey(.popUpMenuWindow) - 1
                    || current.layer == CGWindowLevelForKey(.statusWindow)
                    || current.layer == CGWindowLevelForKey(.mainMenuWindow)
                {
                    return current.isOnScreen ? .showing : .absent
                }
                if let app = current.owningApplication {
                    // The captured window is the popup we just opened, so trust its
                    // on-screen state rather than requiring the app to be active in
                    // two cases the isActive check gets wrong:
                    //   - Menu-bar agent apps (.accessory) can never report active,
                    //     so their popover (e.g. BetterDisplay) would look hidden
                    //     the instant it opens.
                    //   - Some apps (e.g. Claude/Electron) place their menu at a
                    //     non-standard window level, and it is our programmatic
                    //     trigger, not the user, that opened it, so the app is
                    //     not frontmost. A menu-sized window distinguishes this
                    //     from an incidental small window.
                    if app.activationPolicy == .accessory
                        || current.bounds.height > MenuBarItemManager.maxMenuBarItemHeight
                    {
                        return current.isOnScreen ? .showing : .absent
                    }
                    return app.isActive && current.isOnScreen ? .showing : .absent
                }
                return current.isOnScreen ? .showing : .absent
            }

            // The tracked window is gone or was never captured. During the
            // grace period, assume the interface is still showing to give
            // apps with nonstandard windows time to create them.
            if Date.now.timeIntervalSince(firstShownDate) < graceInterval {
                return .showing
            }

            // Grace period expired and no tracked window. Check whether the
            // app has any visible popup or overlay window that we missed.
            //
            // A miss here is not evidence the menu closed — we never found it
            // in the first place — so it reports `unknown` and the caller
            // decides how long to keep looking.
            return appHasVisiblePopup() ? .showing : .unknown
        }

        /// Checks whether any process that could own this item's interface has
        /// a visible menu window on screen.
        ///
        /// See ``MenuBarItemManager/windowIsOpenInterface(ownerPID:layer:height:interfacePIDs:)``
        /// for what counts.
        private func appHasVisiblePopup() -> Bool {
            WindowInfo.createWindows(option: .onScreen).contains { window in
                MenuBarItemManager.windowIsOpenInterface(
                    ownerPID: window.ownerPID,
                    layer: window.layer,
                    height: window.bounds.height,
                    interfacePIDs: interfacePIDs
                )
            }
        }

        init(
            tag: MenuBarItemTag,
            sourcePID: pid_t,
            interfacePIDs: Set<pid_t>,
            displayID: CGDirectDisplayID,
            returnDestination: MoveDestination,
            fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?,
            originalSection: MenuBarSection.Name
        ) {
            self.tag = tag
            self.sourcePID = sourcePID
            self.interfacePIDs = interfacePIDs
            self.displayID = displayID
            self.returnDestination = returnDestination
            self.fallbackNeighbor = fallbackNeighbor
            self.originalSection = originalSection
        }
    }

    /// Whether an on-screen window counts as the interface a temporarily shown
    /// item opened.
    ///
    /// Matches the pop-up menu level (the level macOS uses for menus opened
    /// from menu bar items). Some apps (e.g. DisplayLink) instead draw their
    /// menu as a status- or main-menu-level window owned by the app rather
    /// than at pop-up level, so those levels are also matched, but only when
    /// the window is taller than a menu bar item, so the status item itself
    /// (which sits in the menu bar) is not mistaken for an open menu. A
    /// liberal "above normal" match was previously used as a catch-all, but
    /// it matched floating panels, modal levels, and other unrelated app
    /// windows, keeping the interface reading positive indefinitely and
    /// preventing rehide.
    ///
    /// `interfacePIDs` is a set rather than one PID because the process that
    /// owns the item's window and the one that owns the menu it opens are not
    /// always the same — see
    /// ``TemporarilyShownItemContext/interfacePIDs``.
    static nonisolated func windowIsOpenInterface(
        ownerPID: pid_t,
        layer: Int,
        height: CGFloat,
        interfacePIDs: Set<pid_t>
    ) -> Bool {
        guard interfacePIDs.contains(ownerPID) else {
            return false
        }
        let level = CGWindowLevel(Int32(layer))
        if level == CGWindowLevelForKey(.popUpMenuWindow)
            || level == CGWindowLevelForKey(.popUpMenuWindow) - 1
        {
            return true
        }
        // Menu bar items are at most ~menu-bar height; a real menu drawn
        // at status/main-menu level is taller, which distinguishes it.
        if level == CGWindowLevelForKey(.statusWindow) || level == CGWindowLevelForKey(.mainMenuWindow) {
            return height > maxMenuBarItemHeight
        }
        return false
    }

    /// The tallest a window can be and still be a menu bar item rather than
    /// something the item opened.
    static nonisolated let maxMenuBarItemHeight: CGFloat = 40

    /// Picks the window to track as the interface a temporarily shown item
    /// just opened, out of the windows that appeared around its click.
    ///
    /// Picking wrong is worse than picking nothing. A tracked window
    /// short-circuits ``TemporarilyShownItemContext/interfaceState``: the grace
    /// period and the `unknown` budget are both skipped, and the instant the
    /// tracked window goes away the reading is a confident `absent`. So
    /// latching onto an incidental window that lives for a moment — and
    /// Control Center, which is in `interfacePIDs` for every item it hosts,
    /// opens them around a click — hands the rehide the same false negative
    /// those two mechanisms exist to prevent, only sooner and with more
    /// conviction. The menu goes down inside a second (#924).
    ///
    /// A candidate therefore has to look like an interface: a menu-level
    /// window first, then any window too tall to be a status item, which is how
    /// ``TemporarilyShownItemContext/interfaceState`` recognizes the popovers
    /// and non-standard-level menus that never reach pop-up level. Nothing
    /// qualifying means nothing is tracked, which leaves the reading `unknown`
    /// and the menu alone.
    static nonisolated func interfaceWindowToTrack(
        among candidates: [WindowInfo],
        interfacePIDs: Set<pid_t>
    ) -> WindowInfo? {
        let owned = candidates.filter { interfacePIDs.contains($0.ownerPID) }
        let menu = owned.first { window in
            windowIsOpenInterface(
                ownerPID: window.ownerPID,
                layer: window.layer,
                height: window.bounds.height,
                interfacePIDs: interfacePIDs
            )
        }
        return menu ?? owned.first { $0.bounds.height > maxMenuBarItemHeight }
    }

    /// Returns the item `temporarilyShow` should operate on, re-mapping the
    /// caller's item onto its freshly fetched counterpart when their tags
    /// have diverged.
    ///
    /// The caller's item can carry a fallback tag from a cache snapshot taken
    /// before sourcePID resolution succeeded — on a cold start, hidden items
    /// resolve only once the MenuBarItemService has warmed, and until then a
    /// third-party item is tagged `com.apple.controlcenter:Item-0:N`. A fresh
    /// fetch resolves real tags, so a tag lookup on the stale item finds
    /// nothing and the click dies in `getReturnDestination` (#943). The
    /// window itself is stable across resolution: match by windowID so the
    /// tag lookup, the rehide metadata, and the context all carry the
    /// resolved identity. An item whose tag is present in `items`, or whose
    /// window is gone entirely, is returned unchanged.
    static nonisolated func remappedItem(for item: MenuBarItem, in items: [MenuBarItem]) -> MenuBarItem {
        guard items.first(matching: item.tag) == nil else {
            return item
        }
        return items.first { $0.windowID == item.windowID } ?? item
    }

    /// Re-fetches an item from the given display's live window list so a
    /// click targets current windowID and bounds rather than a stale
    /// pre-move struct.
    ///
    /// Prefers an exact windowID match, then tag plus PID, then returns the
    /// caller's struct unchanged.
    private func refreshedClickTarget(for item: MenuBarItem, on displayID: CGDirectDisplayID) async -> MenuBarItem {
        let refreshedItems = await MenuBarItem.getMenuBarItems(on: displayID, option: .onScreen)
        return refreshedItems.first(where: { $0.windowID == item.windowID })
            ?? refreshedItems.first(matchingTag: item.tag, pid: item.sourcePID ?? item.ownerPID)
            ?? item
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown, along with the tag and PID of the neighbor on the
    /// opposite side (if any) for fallback ordering.
    ///
    /// Only neighbors that share `section` are considered. An item from
    /// another section is not a usable anchor: moving next to it returns the
    /// item into *that* section, and once macOS persists the position the
    /// item stays there across relaunches. Items that can never be hidden are
    /// the common case — Control Center modules such as `AudioVideoModule`
    /// come and go as the mic or camera is used, and even with the items
    /// sorted into left-to-right order, the physically adjacent item can
    /// belong to another section.
    private func getReturnDestination(
        for item: MenuBarItem,
        in items: [MenuBarItem],
        section: MenuBarSection.Name
    ) -> (destination: MoveDestination, fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?)? {
        // The anchor math below treats index adjacency as physical
        // adjacency, but the item list arrives in Window Server order.
        // Sort by each item's leading edge so successor/predecessor mean
        // the item's actual on-screen neighbors.
        let orderedItems = items.sorted { $0.bounds.minX < $1.bounds.minX }

        guard let index = orderedItems.firstIndex(matching: item.tag) else {
            return nil
        }

        let eligibleIndices = Set(orderedItems.indices.filter { candidateIndex in
            let candidate = orderedItems[candidateIndex]
            guard candidate.canBeHidden else {
                return false
            }
            return itemCache.address(for: candidate.tag)?.section == section
        })

        let anchors = LayoutSolver.returnAnchors(
            forIndex: index,
            itemCount: orderedItems.count,
            eligibleIndices: eligibleIndices
        )

        // Prefer anchoring to the neighbor on the right. The fallback is the
        // nearest eligible neighbor on the opposite side.
        if let successor = anchors.successor {
            let fallback: (MenuBarItemTag, pid_t)? = anchors.predecessor.map { predecessor in
                let neighbor = orderedItems[predecessor]
                return (neighbor.tag, neighbor.sourcePID ?? neighbor.ownerPID)
            }
            return (.leftOfItem(orderedItems[successor]), fallback)
        }
        if let predecessor = anchors.predecessor {
            return (.rightOfItem(orderedItems[predecessor]), nil)
        }

        // The section holds no other item to anchor against, so aim at the
        // section itself. Ordering within the section is not preserved, but
        // the item lands in the correct section.
        return sectionDestination(for: section, in: items).map { ($0, nil) }
    }

    /// Gets the destination that returns an item to the given section's
    /// boundary, used when no neighbor is available to preserve ordering.
    private func sectionDestination(
        for section: MenuBarSection.Name,
        in items: [MenuBarItem]
    ) -> MoveDestination? {
        switch section {
        case .hidden:
            items.first(matching: .hiddenControlItem).map { .leftOfItem($0) }
        case .alwaysHidden:
            // If the always-hidden section was disabled, fall back to hidden.
            (items.first(matching: .alwaysHiddenControlItem) ?? items.first(matching: .hiddenControlItem))
                .map { .leftOfItem($0) }
        case .visible:
            // Should not happen (we don't temporarily show items that are
            // already visible), but handle it gracefully.
            nil
        }
    }

    /// Waits for a menu bar item's position to stabilize after a move.
    ///
    /// After a Cmd+drag move, the Window Server updates the item's window
    /// position, but the owning app may take additional time to process the
    /// change internally. If we click the item before it has settled, the
    /// app may position its popup at the old location.
    ///
    /// This method polls the item's bounds until two consecutive reads
    /// return the same value, up to a maximum wait time.
    private nonisolated func waitForItemPositionToSettle(item: MenuBarItem) async {
        let maxWait: Duration = .milliseconds(250)
        let pollInterval: Duration = .milliseconds(20)
        let startTime = ContinuousClock.now

        var previousBounds = Bridging.getWindowBounds(for: item.windowID)

        while ContinuousClock.now - startTime < maxWait {
            await eventSleep(for: pollInterval)
            let currentBounds = Bridging.getWindowBounds(for: item.windowID)
            if currentBounds == previousBounds, currentBounds != nil {
                return
            }
            previousBounds = currentBounds
        }
    }

    /// Waits until the item's Window Server origin differs from `previousOrigin`,
    /// or until `timeout` elapses.
    ///
    /// Used on the fast path of `temporarilyShow` as a lightweight alternative
    /// to `waitForItemPositionToSettle`: we only need to confirm the Window
    /// Server has applied the new position; we don't need two consecutive
    /// identical readings.
    private nonisolated func waitForItemToLeaveOrigin(
        item: MenuBarItem,
        previousOrigin: CGPoint,
        timeout: Duration
    ) async {
        let pollInterval = Duration.milliseconds(15)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            await eventSleep(for: pollInterval)
            if let currentOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin,
               currentOrigin != previousOrigin
            {
                return
            }
        }
    }

    /// How long to wait before looking again while a temporarily shown item's
    /// menu is still open, or while the user is still mid-interaction.
    ///
    /// The item sits in the visible section until a check passes, so this is
    /// also how long it lingers there after the user dismisses the menu. The
    /// check itself is cheap in the common case — a single window lookup — and
    /// the expensive full enumeration only runs for an item whose interface was
    /// never identified, which is spaced further apart by the `unknown` branch
    /// of ``rehideTemporarilyShownItems(force:isCalledFromTemporarilyShow:)``.
    private static let rehidePollInterval: TimeInterval = 1

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        let interval = interval ?? 15
        MenuBarItemManager.diagLog.debug("Running rehide timer for interval: \(interval)")
        rehideTimer?.invalidate()
        rehideCancellable?.cancel()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MenuBarItemManager.diagLog.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
        // Also rehide when frontmost app changes (smart-ish).
        //
        // `dropFirst` because the KVO publisher's default options include
        // `.initial`, so subscribing replays the app that is already frontmost.
        // Every call to this method re-subscribes — including the retry calls
        // from `rehideTemporarilyShownItems` — so that replay turned each
        // "look again in `interval` seconds" into "look again in 200 ms". The
        // intervals below were reasoned about as seconds and were really a
        // fifth of one: the four `unknown` checks that read as twelve seconds
        // of grace for a menu we cannot identify were spending eight hundred
        // milliseconds (#924). Only a real app switch belongs here.
        //
        // Debounce so rapid app switches (Cmd-Tab spam) collapse to one
        // rehide attempt instead of queuing a separate Task per change ;
        // each rehide call can do an expensive on-screen window enumeration.
        rehideCancellable = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.rehideTemporarilyShownItems()
                }
            }
    }

    /// The result of a ``temporarilyShow(item:clickingWith:on:fastPath:)`` call.
    enum TemporaryShowResult {
        /// The item was never moved; a precondition failed (missing state,
        /// no return destination, no anchor, or the move itself failed).
        /// The item is still hidden; do **not** attempt a fallback click.
        case showFailed
        /// The item was moved into the visible area **and** the synthetic
        /// click completed successfully.
        case movedAndClicked
        /// The item was moved into the visible area but the synthetic click
        /// failed. The icon is now visible; callers may attempt a fallback
        /// click using live bounds.
        case movedButClickFailed
    }

    /// Temporarily moves `item` into the visible area next to the Ice icon,
    /// clicks it, then schedules a rehide.
    ///
    /// The item is returned to its original location after approximately
    /// 15 seconds, though it may be sooner (e.g. when switching apps) or
    /// later due to the smart rehide logic.
    ///
    /// - Returns: A ``TemporaryShowResult`` describing whether the move and
    ///   click succeeded. Only act on ``TemporaryShowResult/movedButClickFailed``
    ///   for fallback clicks; the item is hidden for every other non-success case.
    @discardableResult
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton, on displayID: CGDirectDisplayID? = nil, fastPath: Bool = false) async -> TemporaryShowResult {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not showing \(item.logString)")
            return .showFailed
        }

        MenuBarItemManager.diagLog.debug("temporarilyShow: started for \(item.logString)")

        // Determine the displayID for this item.
        let resolvedDisplayID: CGDirectDisplayID
        if let displayID {
            resolvedDisplayID = displayID
        } else {
            let itemBounds = item.liveBounds
            let screen = NSScreen.screens.first { $0.frame.intersects(itemBounds) }
            resolvedDisplayID = screen?.displayID ?? Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        // Determine the item's original section early so we can persist it
        // and use it as a fallback if the neighbor-based return destination
        // becomes stale by the time we rehide. Resolved against the same
        // cache snapshot the caller's tag came from, so it must happen
        // before the item is re-mapped to a freshly resolved tag below.
        let originalSection = itemCache.address(for: item.tag)?.section ?? .hidden

        // Rehide any previously temporarily shown items before showing a new one.
        // This prevents stale contexts from accumulating when the user opens multiple
        // temporary items in quick succession.
        if !temporarilyShownItemContexts.isEmpty {
            rehideTimer?.invalidate()
            rehideCancellable?.cancel()
            await rehideTemporarilyShownItems(force: true, isCalledFromTemporarilyShow: true)

            // Only treat contexts with rehideAttempts > 0 as genuinely stuck
            // (move was attempted and failed). Contexts with rehideAttempts == 0
            // but notFoundAttempts > 0 are merely not visible on the active
            // space right now; they are transient and will retry fine.
            // Bailing on notFound items would leave them permanently stranded.
            let stuckItems = temporarilyShownItemContexts.filter {
                !$0.tag.matchesIgnoringWindowID(item.tag) && $0.rehideAttempts > 0
            }
            if !stuckItems.isEmpty {
                MenuBarItemManager.diagLog.error(
                    """
                    temporarilyShow: aborting; \(stuckItems.count) item(s) still stuck \
                    after force-rehide: \(stuckItems.map(\.tag)). \
                    Avoiding further semaphore saturation.
                    """
                )
                // Re-arm the rehide timer so stuck contexts are retried rather
                // than left stranded with no scheduled retry.
                runRehideTimer()
                return .showFailed
            }

            if temporarilyShownItemContexts.contains(where: { $0.tag.matchesIgnoringWindowID(item.tag) }) {
                // The item we want to show is already in the temporary list.
                // This can happen if the user clicks the same item twice very fast.
                // Remove the old context so we can create a fresh one with new bounds.
                removeTemporarilyShownItemFromCache(with: item.tag)
            }
        }

        // Fetch items specifically for the display where the item lives.
        let items = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .activeSpace)

        var item = item
        let remappedItem = MenuBarItemManager.remappedItem(for: item, in: items)
        if remappedItem.tag != item.tag {
            MenuBarItemManager.diagLog.info(
                "temporarilyShow: re-mapped stale \(item.logString) to \(remappedItem.logString) via windowID"
            )
            item = remappedItem
        }
        let tagIdentifier = item.tag.tagIdentifier

        guard let returnInfo = getReturnDestination(for: item, in: items, section: originalSection) else {
            MenuBarItemManager.diagLog.error("No return destination for \(item.logString) on display \(resolvedDisplayID)")
            return .showFailed
        }

        // Prefer inserting to the left of the Thaw/visible control item so the icon appears
        // where users expect. If it's missing, fall back to the first non-control item.
        let visibleControl = items.first(matching: .visibleControlItem)
        let targetItem = visibleControl ?? items.first(where: { !$0.isControlItem && $0.canBeHidden }) ?? items.first

        // If we couldn't find any anchor, bail gracefully.
        guard let anchor = targetItem else {
            MenuBarItemManager.diagLog.warning("Not enough room or no anchor to show \(item.logString)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Not enough room to show \"\(item.displayName)\"")
            alert.runModal()
            return .showFailed
        }

        let moveDestination: MoveDestination = .leftOfItem(anchor)

        // Record the item's original section early so we can relocate it if its app
        // quits before we get a chance to rehide it (macOS persists the
        // physical position set by the Cmd+drag, so on relaunch the icon
        // would otherwise stay in the visible section).
        pendingRelocations[tagIdentifier] = sectionKey(for: originalSection)

        // Also store the return destination to preserve ordering
        let neighborTag = returnInfo.destination.targetItem.tag
        let position = switch returnInfo.destination {
        case .leftOfItem: "left"
        case .rightOfItem: "right"
        }
        let returnDestinationRecord = [
            "neighbor": neighborTag.tagIdentifier,
            "position": position,
        ]
        pendingReturnDestinations[tagIdentifier] = returnDestinationRecord
        persistPendingRelocations()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        MenuBarItemManager.diagLog.debug("Temporarily showing \(item.logString) on display \(resolvedDisplayID)")

        // Capture the item's origin before the move so the fast-path settle
        // can detect when the Window Server has applied the new position.
        let preMoveOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin

        do {
            if fastPath {
                // Two-attempt move on the fast path. The first attempt almost always
                // repositions the item correctly; the second is a cheap safety net for
                // the rare case where the event cycle is dropped under CPU load.
                // Keeping retries at 2 (vs. the default 8) avoids the visible jitter
                // from a long retry loop while still tolerating one bad cycle.
                try await move(item: item, to: moveDestination, on: resolvedDisplayID, skipInputPause: true, maxMoveAttempts: 2)
            } else {
                try await move(item: item, to: moveDestination, on: resolvedDisplayID, skipInputPause: true)
            }
        } catch {
            MenuBarItemManager.diagLog.error("Error showing item: \(error)")

            // Determine whether the item physically left its original position
            // despite move() throwing. itemCache is a pre-move snapshot and is
            // not updated during a move() call, so itemCache.address(for:) would
            // always return originalSection here; giving a false negative.
            // Instead, compare live Window Server bounds against the origin
            // captured before the move started. Any nil (window gone or
            // pre-move capture missed) is treated as moved/unknown; preserving
            // rehide metadata is the safe-side choice.
            let currentOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin
            // Treat any nil as "moved/unknown"; preserving rehide metadata is
            // the safe-side choice when the move outcome cannot be determined.
            // Note: in Swift nil != nil evaluates to false, so without the nil
            // guards both-nil would wrongly indicate "item never moved."
            let itemHasMoved = currentOrigin == nil || preMoveOrigin == nil || currentOrigin != preMoveOrigin

            if itemHasMoved {
                // The item is no longer where it started; keep the rehide
                // metadata so the persistent-relocation path can restore it
                // when the app relaunches or the rehide timer fires.
                MenuBarItemManager.diagLog.warning("move() threw but item \(item.logString) is no longer in \(originalSection); preserving pending rehide metadata")
                // pendingRelocations already set above; re-assert return destination
                // in case it was not yet written (guard-exit paths above this block).
                pendingReturnDestinations[tagIdentifier] = returnDestinationRecord
                persistPendingRelocations()
            } else {
                // Item never moved; safe to discard the speculative metadata.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                persistPendingRelocations()
            }

            return .showFailed
        }

        let context = TemporarilyShownItemContext(
            tag: item.tag,
            sourcePID: item.sourcePID ?? item.ownerPID,
            interfacePIDs: Set([item.ownerPID, item.sourcePID].compactMap(\.self)),
            displayID: resolvedDisplayID,
            returnDestination: returnInfo.destination,
            fallbackNeighbor: returnInfo.fallbackNeighbor,
            originalSection: originalSection
        )
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            // A poll, not the fifteen-second ceiling. Nothing else re-arms a
            // check until the frontmost app changes, and dismissing a menu with
            // Escape changes nothing, so scheduling the ceiling here would park
            // the item in the visible section for fifteen seconds every time
            // the user closed its menu without picking anything. Each check
            // reschedules itself, so the ceiling still arrives on time for an
            // item that opened nothing at all.
            runRehideTimer(for: Self.rehidePollInterval)
        }

        if fastPath {
            // Fast path: lightweight settle (max 150 ms, 15 ms poll) so the
            // click target coordinates are live rather than the pre-move bounds.
            // This is shorter than the full waitForItemPositionToSettle (250 ms)
            // to keep the IceBar click feel snappy.
            if let preMoveOrigin {
                await waitForItemToLeaveOrigin(item: item, previousOrigin: preMoveOrigin, timeout: .milliseconds(150))
            }
        } else {
            // Wait for the item's position to stabilize after the move. Some
            // apps need time to process the window relocation before they can
            // correctly position their popup in response to a click.
            await waitForItemPositionToSettle(item: item)
        }

        // Re-fetch the item so getCurrentBounds inside postClickEvents uses
        // a fresh window reference rather than the stale pre-move struct.
        let clickItem = await refreshedClickTarget(for: item, on: resolvedDisplayID)

        if !fastPath {
            // Give the owning app a little extra time to finish processing the
            // move internally. Some apps (e.g. OneDrive) need more than just a
            // stable window position before they can respond to clicks.
            await eventSleep(for: .milliseconds(25))
        }

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        // Electron/Chromium tray items ignore the synthetic click, so open their
        // menu via an Accessibility press once revealed, mirroring the on-screen
        // path. Other apps (and right-clicks) use the synthetic click below. The
        // popup window capture that follows is unaffected by which path opened it.
        // The window the click opened, when the click path we took already
        // watched for it. Saves repeating the scan below.
        var observedInterfaceWindowID: CGWindowID?

        if mouseButton == .left, isElectronItem(clickItem), pressItemViaAccessibility(clickItem) {
            MenuBarItemManager.diagLog.info("Activated \(clickItem.logString) via AX press")
        } else {
            do {
                // Single attempt: the item is already at a known-good position with
                // fresh bounds. If it fails, fall through to the fallback path below
                // rather than spending 3× the semaphore timeout here.
                let reaction = try await click(item: clickItem, with: mouseButton, skipInputPause: true, maxAttempts: 1)
                observedInterfaceWindowID = reaction.openedWindowID
            } catch {
                MenuBarItemManager.diagLog.error("Error clicking item (first attempt): \(error); attempting fallback click")

                // Fallback: re-fetch the item from the live window list so the
                // click targets a fresh MenuBarItem with current windowID and
                // bounds, rather than the potentially stale pre-click struct.
                let fallbackItem = await refreshedClickTarget(for: clickItem, on: resolvedDisplayID)

                // We stay inside temporarilyShow so that idsBeforeClick and context
                // remain in scope; shownInterfaceWindow can still be captured if
                // the fallback succeeds, keeping isShowingInterface accurate for
                // the rehide logic.
                do {
                    let reaction = try await click(item: fallbackItem, with: mouseButton, skipInputPause: true)
                    observedInterfaceWindowID = reaction.openedWindowID
                } catch {
                    MenuBarItemManager.diagLog.error("Fallback click also failed for \(item.logString): \(error)")
                    // Icon is visible but both click attempts failed.
                    return .movedButClickFailed
                }
            }
        }

        // Capture the popup window opened by whichever click path succeeded.
        // The synthetic-click paths already waited for it and told us which
        // one it was; only the AX press path, which posts nothing and so has
        // nothing to verify, still has to look for itself.
        let interfaceCandidates: [WindowInfo]
        if let observedInterfaceWindowID, let observed = WindowInfo(windowID: observedInterfaceWindowID) {
            interfaceCandidates = [observed]
        } else {
            await eventSleep(for: .milliseconds(100))
            interfaceCandidates = WindowInfo.createWindows(option: .onScreen)
                .filter { !idsBeforeClick.contains($0.windowID) }
        }

        // Either PID counts, for the reason ``interfacePIDs`` documents: the
        // item's window and the menu it opens can belong to different
        // processes, and the item's own owner is Control Center's for every
        // item it hosts.
        //
        // What the click path saw goes through the same test as what a scan
        // finds. ``ClickReactionVerifier`` is answering a different question —
        // did the owner react at all — and settles for any new window of the
        // owner's when no menu-level one appeared, which is sound evidence of a
        // reaction and a poor guess at the menu.
        context.shownInterfaceWindow = MenuBarItemManager.interfaceWindowToTrack(
            among: interfaceCandidates,
            interfacePIDs: context.interfacePIDs
        )

        return .movedAndClicked
    }

    /// Resolves the best move destination for returning a temporarily shown
    /// item to its original section.
    ///
    /// Tries destinations in order of preference:
    /// 1. The captured ``TemporarilyShownItemContext/returnDestination``
    ///    (primary neighbor, refreshed with current bounds).
    /// 2. The ``TemporarilyShownItemContext/fallbackNeighbor`` (the
    ///    neighbor on the opposite side, to preserve relative ordering).
    /// 3. The control item for the item's original section (guarantees
    ///    the item ends up in the correct section, though ordering within
    ///    the section may differ).
    private func resolveReturnDestination(
        for context: TemporarilyShownItemContext,
        in items: [MenuBarItem]
    ) -> MoveDestination? {
        // 1. Try the primary neighbor-based destination.
        //    Re-wrap with the fresh item so the move uses current bounds.
        let targetTag = context.returnDestination.targetItem.tag
        let targetPID = context.returnDestination.targetItem.sourcePID ?? context.returnDestination.targetItem.ownerPID
        if let freshTarget = items.first(matchingTag: targetTag, pid: targetPID) {
            switch context.returnDestination {
            case .leftOfItem:
                return .leftOfItem(freshTarget)
            case .rightOfItem:
                return .rightOfItem(freshTarget)
            }
        }

        // 2. Try the fallback neighbor (opposite side).
        if let fallbackNeighbor = context.fallbackNeighbor,
           let freshFallback = items.first(matchingTag: fallbackNeighbor.tag, pid: fallbackNeighbor.pid)
        {
            switch context.returnDestination {
            case .leftOfItem:
                return .rightOfItem(freshFallback)
            case .rightOfItem:
                return .leftOfItem(freshFallback)
            }
        }

        // 3. Fallback: use the control item for the original section.
        MenuBarItemManager.diagLog.debug(
            """
            Return destination neighbors not found for \(context.tag); \
            falling back to section-level destination for \(context.originalSection.logString)
            """
        )
        guard let destination = sectionDestination(for: context.originalSection, in: items) else {
            MenuBarItemManager.diagLog.error(
                """
                No section destination to resolve return destination for \
                \(context.tag) in \(context.originalSection.logString)
                """
            )
            return nil
        }
        return destination
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items, unless `force`
    /// is `true`, in which case all items are rehidden immediately.
    ///
    /// - Parameter force: If `true`, skip the interface-showing and
    ///   user-input guards and rehide all items immediately.
    func rehideTemporarilyShownItems(force: Bool = false, isCalledFromTemporarilyShow: Bool = false) async {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }

        MenuBarItemManager.diagLog.debug("rehideTemporarilyShownItems: started (force=\(force), isCalledFromTemporarilyShow=\(isCalledFromTemporarilyShow))")

        if !force {
            // interfaceState is computed, and its terminal case enumerates
            // every on-screen window; on a 1-second poll, evaluate it once
            // per context per check and answer both questions from that.
            let interfaceStates = temporarilyShownItemContexts.map {
                ($0, $0.interfaceState)
            }
            guard !interfaceStates.contains(where: { $0.1 == .showing }) else {
                MenuBarItemManager.diagLog.debug("Menu bar item interface is shown, so waiting to rehide")
                runRehideTimer(for: Self.rehidePollInterval)
                return
            }

            // No context reports a showing interface, but some may report that
            // they never identified one. Rehiding on that is a guess, and the
            // cost of guessing wrong is the user's open menu being dragged off
            // the bar (#924). Spend a bounded number of further checks looking
            // before treating it as closed.
            let undetected = interfaceStates.filter { $0.1 == .unknown }.map(\.0)
            let stillWorthChecking = undetected.filter {
                $0.undetectedInterfaceChecks < TemporarilyShownItemContext.maxUndetectedInterfaceChecks
            }
            if !stillWorthChecking.isEmpty {
                for context in stillWorthChecking {
                    context.undetectedInterfaceChecks += 1
                }
                MenuBarItemManager.diagLog.debug(
                    "Interface never identified for \(stillWorthChecking.count) temporarily shown item(s); waiting to rehide rather than assuming it closed"
                )
                runRehideTimer(for: 3)
                return
            }
            if !undetected.isEmpty {
                MenuBarItemManager.diagLog.info(
                    "Interface still unidentified for \(undetected.count) temporarily shown item(s) after \(TemporarilyShownItemContext.maxUndetectedInterfaceChecks) checks; rehiding anyway"
                )
            }
            guard hasUserPausedInput(for: .milliseconds(250)) else {
                MenuBarItemManager.diagLog.debug("Found recent user input, so waiting to rehide")
                runRehideTimer(for: Self.rehidePollInterval)
                return
            }
        }

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // Use a shorter settle time when called from temporarilyShow; the user
        // is actively waiting for the next click. The eventSemaphore and
        // waitForMoveOperationBuffer in move() provide adequate race protection.
        await eventSleep(for: isCalledFromTemporarilyShow ? .milliseconds(50) : .milliseconds(250))

        MenuBarItemManager.diagLog.debug("Rehiding temporarily shown items")

        // Use the same 30 s watchdog as the bulk-apply path so the 1 s
        // default cursor-watchdog cannot force-show the cursor mid-batch
        // (#899). Without this, a rehide that takes longer than 1 s
        // (eventSleep + moves) lets the watchdog fire, flash the cursor,
        // and reset hideCount to 0 — observed as cursor flicker.
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer {
            MouseHelpers.showCursor()
        }

        // Suppress per-item cursor hide/show inside the move loop so the
        // outer pair owns visibility for the whole batch. Without this,
        // each move() does its own hide/show and the cursor oscillates
        // per item — observed as flicker during rehide.
        let wasBulkApplyInProgress = isBulkApplyInProgress
        isBulkApplyInProgress = true
        defer {
            isBulkApplyInProgress = wasBulkApplyInProgress
        }

        while let context = currentContexts.popLast() {
            guard let item = items.first(matchingTag: context.tag, pid: context.sourcePID) else {
                context.notFoundAttempts += 1
                MenuBarItemManager.diagLog.debug(
                    """
                    Missing temporarily shown item \(context.tag) on active space \
                    (not-found attempt \(context.notFoundAttempts)); will retry
                    """
                )
                // Keep the context for retry; the item may be on another
                // space or the app may have briefly hidden it. After enough
                // attempts, drop the in-memory context and rely on the
                // persisted pendingRelocations entry to recover on the next
                // cache cycle (relocatePendingItems).
                if context.notFoundAttempts < 10 {
                    failedContexts.append(context)
                } else {
                    MenuBarItemManager.diagLog.warning(
                        """
                        Giving up in-memory retry for \(context.tag) after \
                        \(context.notFoundAttempts) not-found attempts; \
                        pendingRelocations will handle recovery
                        """
                    )
                }
                continue
            }

            // Resolve the best return destination using fresh items.
            guard let destination = resolveReturnDestination(for: context, in: items) else {
                MenuBarItemManager.diagLog.error(
                    """
                    Could not resolve return destination for \(item.logString); \
                    item will remain in visible section until next cache cycle handles pendingRelocations
                    """
                )
                // Don't remove pendingRelocations; let relocatePendingItems handle it.
                continue
            }

            do {
                try await move(item: item, to: destination, on: context.displayID, skipInputPause: true)
                // Successfully rehidden; remove the pending relocation entry.
                let tagIdentifier = context.tag.tagIdentifier
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            } catch {
                context.rehideAttempts += 1
                MenuBarItemManager.diagLog.warning(
                    """
                    Attempt \(context.rehideAttempts) to rehide \
                    \(item.logString) failed with error: \
                    \(error)
                    """
                )
                // Maximum total attempts across all timer rounds.
                // 3 per-call attempts × 3 timer rounds = 9. Beyond this the
                // item is permanently stuck (dead PID, broken EventTap, etc.)
                // and retrying only keeps the event semaphore saturated.
                let maxTotalRehideAttempts = 9
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again immediately.
                } else if context.rehideAttempts < maxTotalRehideAttempts {
                    // Per-call cap reached; schedule a longer-delay retry.
                    failedContexts.append(context)
                } else {
                    // Total cap reached; drop this context from same-session retries.
                    // Overwrite the pendingRelocations entry with a waitForRelaunch
                    // sentinel so relocatePendingItems() skips move() this session.
                    // The sentinel encodes the current windowID; when the app
                    // relaunches its status item gets a new windowID, clearing the
                    // suppression automatically.
                    let tagIdentifier = context.tag.tagIdentifier
                    pendingRelocations[tagIdentifier] = waitForRelaunchValue(
                        windowID: item.windowID,
                        section: context.originalSection
                    )
                    persistPendingRelocations()
                    MenuBarItemManager.diagLog.error(
                        """
                        Giving up rehide for \(item.logString) after \
                        \(context.rehideAttempts) total attempts; \
                        marked waitForRelaunch; relocatePendingItems will \
                        retry only after app relaunch (new windowID)
                        """
                    )
                }
            }
        }

        persistPendingRelocations()

        // If force-hiding, we don't want to re-queue them for long delays.
        // We want them back in the section immediately or kept in context.
        if failedContexts.isEmpty {
            MenuBarItemManager.diagLog.debug("All items were successfully rehidden")
        } else {
            MenuBarItemManager.diagLog.error(
                """
                Some items failed to rehide; keeping in context for retry: \
                \(failedContexts.map(\.tag))
                """
            )
            temporarilyShownItemContexts.append(contentsOf: failedContexts.reversed())
            if !force {
                runRehideTimer(for: 3)
            }
        }
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(with tag: MenuBarItemTag) {
        while let index = temporarilyShownItemContexts.firstIndex(where: { $0.tag.matchesIgnoringWindowID(tag) }) {
            MenuBarItemManager.diagLog.debug(
                """
                Removing temporarily shown item from cache: \
                \(tag)
                """
            )
            temporarilyShownItemContexts.remove(at: index)
        }
        // Also clear any pending relocation since the user explicitly
        // placed the item in a new position.
        let tagIdentifier = tag.tagIdentifier
        if pendingRelocations.removeValue(forKey: tagIdentifier) != nil {
            pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            persistPendingRelocations()
        }
    }
}
