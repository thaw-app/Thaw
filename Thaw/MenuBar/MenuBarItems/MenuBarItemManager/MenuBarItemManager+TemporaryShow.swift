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
        let tag: MenuBarItemTag

        /// The PID used to match this item back on the bar at rehide time.
        let sourcePID: pid_t

        /// Every process that could plausibly own this item's interface.
        ///
        /// On macOS 26 Control Center owns the item's window while the app
        /// draws its menu, so either PID alone misses the open menu and the
        /// rehide tears it down (#924). Matches
        /// ``ClickReactionVerifier/Snapshot/pids``.
        let interfacePIDs: Set<pid_t>

        /// The display identifier where the item was shown.
        let displayID: CGDirectDisplayID

        /// Captured at show time; may be stale by rehide time.
        let returnDestination: MoveDestination

        /// The neighbor opposite ``returnDestination``, a fallback for
        /// preserving order when that target is gone.
        let fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?

        /// Last-resort destination when both neighbors are stale.
        let originalSection: MenuBarSection.Name

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// When the item's menu was first seen closed since its last
        /// interaction. The user's hide-again delay counts from here.
        var closedSince: Date?

        /// Separate from ``rehideAttempts`` to allow more retries: the app may
        /// be on another space or briefly invisible.
        var notFoundAttempts = 0

        /// The number of rehide checks that have found the interface
        /// ``InterfaceState/unknown``.
        ///
        /// Bounded by ``maxUndetectedInterfaceChecks`` so the item still goes
        /// home eventually.
        var undetectedInterfaceChecks = 0

        /// How many `unknown` readings to sit through before rehiding anyway.
        ///
        /// Checks are three seconds apart. Lingering is far cheaper than a menu
        /// closing under the user.
        static let maxUndetectedInterfaceChecks = 4

        /// Starts the grace period for menus with nonstandard windows.
        private let firstShownDate = Date.now

        /// How long to assume "showing" without a detected popup.
        private let graceInterval: TimeInterval = 2

        /// What is known about the item's interface.
        enum InterfaceState {
            /// A window belonging to the item was observed on screen.
            case showing

            /// The interface was identified and is no longer on screen, so it
            /// has been closed or dismissed. Positive evidence.
            case absent

            /// The interface was never identified. Unlike ``absent`` this is
            /// ignorance, so rehiding on it can close an open menu (#924).
            case unknown
        }

        /// What is currently known about the item's interface.
        var interfaceState: InterfaceState {
            // The tracked popup window is the most reliable signal.
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
                    // Trust on-screen state over isActive for .accessory apps,
                    // which never report active (BetterDisplay), and for
                    // menu-sized windows at odd levels that our click opened
                    // while the app wasn't frontmost (Electron).
                    if app.activationPolicy == .accessory
                        || current.bounds.height > MenuBarItemManager.maxMenuBarItemHeight
                    {
                        return current.isOnScreen ? .showing : .absent
                    }
                    return app.isActive && current.isOnScreen ? .showing : .absent
                }
                return current.isOnScreen ? .showing : .absent
            }

            // No tracked window: assume showing during the grace period.
            if Date.now.timeIntervalSince(firstShownDate) < graceInterval {
                return .showing
            }

            // A miss here isn't evidence the menu closed, so it's `unknown`.
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
    /// Matches pop-up menu level, plus status and main-menu levels for
    /// windows taller than a menu bar item (DisplayLink draws its menu
    /// there). Matching anything above normal caught floating panels and
    /// blocked rehide. See ``TemporarilyShownItemContext/interfacePIDs``.
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
        // A real menu at status/main-menu level is taller than an item.
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
    /// Picking wrong is worse than picking nothing: a tracked window skips
    /// the grace period and `unknown` budget, so latching onto a brief
    /// incidental window (Control Center opens some around a click) closes
    /// the menu within a second (#924).
    ///
    /// So take a menu-level window first, then one too tall to be a status
    /// item. Nothing qualifying leaves the reading `unknown`.
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
    /// On a cold start the caller's item can carry a pre-resolution tag like
    /// `com.apple.controlcenter:Item-0:N`, which the fresh fetch no longer
    /// has (#943). The window is stable, so match by windowID.
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
    /// Only neighbors in `section` count: anchoring to another section's item
    /// returns it into that section, which macOS then persists. Transient
    /// modules like `AudioVideoModule` are the usual culprit.
    private func getReturnDestination(
        for item: MenuBarItem,
        in items: [MenuBarItem],
        section: MenuBarSection.Name
    ) -> (destination: MoveDestination, fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?)? {
        // Items arrive in Window Server order; sort so index adjacency is
        // on-screen adjacency.
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

        // Prefer the right neighbor; fall back to the left.
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

        // No neighbor: aim at the section itself, losing only the ordering.
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
            // Visible items are never temporarily shown.
            nil
        }
    }

    /// Waits for a menu bar item's position to stabilize after a move.
    ///
    /// The app may lag behind WindowServer after a move and open its popup
    /// at the old location. Polls until two reads match, up to a cap.
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
    /// The fast path's lighter alternative to `waitForItemPositionToSettle`.
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
    /// Also how long the item lingers after the menu closes. Usually a single
    /// window lookup; the `unknown` branch spaces out the expensive one.
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
        // Also rehide when the frontmost app changes. `dropFirst` because
        // KVO replays the current value on every re-subscribe, which turned
        // each retry interval into 200 ms (#924). Debounced so Cmd-Tab spam
        // doesn't queue a costly window enumeration per switch.
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
        /// The item was never moved and is still hidden; don't attempt a
        /// fallback click.
        case showFailed
        case movedAndClicked
        /// The icon is visible but the click failed; callers may retry with
        /// live bounds.
        case movedButClickFailed
    }

    /// Temporarily moves `item` into the visible area next to the Ice icon,
    /// clicks it, then schedules a rehide.
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

        let resolvedDisplayID: CGDirectDisplayID
        if let displayID {
            resolvedDisplayID = displayID
        } else {
            let itemBounds = item.liveBounds
            let screen = NSScreen.screens.first { $0.frame.intersects(itemBounds) }
            resolvedDisplayID = screen?.displayID ?? Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        // Resolve against the caller's cache snapshot, before the item is
        // re-mapped to a fresh tag below.
        let originalSection = itemCache.address(for: item.tag)?.section ?? .hidden

        // Rehide earlier items first so stale contexts don't accumulate.
        if !temporarilyShownItemContexts.isEmpty {
            rehideTimer?.invalidate()
            rehideCancellable?.cancel()
            await rehideTemporarilyShownItems(force: true, isCalledFromTemporarilyShow: true)

            // Only failed moves count as stuck. Not-found items are just on
            // another space; bailing on them would strand them.
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
                // Re-arm so stuck contexts are retried.
                runRehideTimer()
                return .showFailed
            }

            if temporarilyShownItemContexts.contains(where: { $0.tag.matchesIgnoringWindowID(item.tag) }) {
                // A fast double click; replace the old context.
                removeTemporarilyShownItemFromCache(with: item.tag)
            }
        }

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

        // Prefer left of the visible control item, else the first non-control item.
        let visibleControl = items.first(matching: .visibleControlItem)
        let targetItem = visibleControl ?? items.first(where: { !$0.isControlItem && $0.canBeHidden }) ?? items.first

        guard let anchor = targetItem else {
            MenuBarItemManager.diagLog.warning("Not enough room or no anchor to show \(item.logString)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Not enough room to show \"\(item.displayName)\"")
            alert.runModal()
            return .showFailed
        }

        let moveDestination: MoveDestination = .leftOfItem(anchor)

        // Recorded now in case the app quits before the rehide: macOS persists
        // the dragged position, so the icon would relaunch visible.
        pendingRelocations[tagIdentifier] = sectionKey(for: originalSection)

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

        // Lets the fast path see when WindowServer applied the new position.
        let preMoveOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin

        do {
            // Full attempt budget, not a 2-attempt cap: AppKit can place the
            // item on either side of the chevron's edge, and two attempts is
            // one wrong guess from giving up (#1035).
            try await move(
                item: item,
                to: moveDestination,
                on: resolvedDisplayID,
                skipInputPause: true,
                options: .init(isUserInitiated: true)
            )
        } catch {
            MenuBarItemManager.diagLog.error("Error showing item: \(error)")

            // itemCache is a pre-move snapshot, so compare live bounds with the
            // captured origin instead.
            let currentOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin
            // Any nil counts as moved, the safe side. The explicit nil checks
            // matter: `nil != nil` is false.
            let itemHasMoved = currentOrigin == nil || preMoveOrigin == nil || currentOrigin != preMoveOrigin

            if itemHasMoved {
                MenuBarItemManager.diagLog.warning("move() threw but item \(item.logString) is no longer in \(originalSection); preserving pending rehide metadata")
                // Re-assert in case a guard exit above skipped the write.
                pendingReturnDestinations[tagIdentifier] = returnDestinationRecord
                persistPendingRelocations()
            } else {
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
            // A poll, not the fifteen-second ceiling: closing a menu with
            // Escape re-arms nothing, so the item would sit visible for the
            // full ceiling.
            runRehideTimer(for: Self.rehidePollInterval)
        }

        if fastPath {
            // Shorter settle (max 150 ms) to keep Thaw Bar clicks snappy.
            if let preMoveOrigin {
                await waitForItemToLeaveOrigin(item: item, previousOrigin: preMoveOrigin, timeout: .milliseconds(150))
            }
        } else {
            await waitForItemPositionToSettle(item: item)
        }

        // Re-fetch so the click uses fresh bounds, not the pre-move struct.
        let clickItem = await refreshedClickTarget(for: item, on: resolvedDisplayID)

        if !fastPath {
            // Some apps (OneDrive) need more than a stable window position.
            await eventSleep(for: .milliseconds(25))
        }

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        // Set when the click path already saw the window it opened.
        var observedInterfaceWindowID: CGWindowID?

        // Electron/Chromium tray items ignore the synthetic click.
        if mouseButton == .left, isElectronItem(clickItem), pressItemViaAccessibility(clickItem) {
            MenuBarItemManager.diagLog.info("Activated \(clickItem.logString) via AX press")
        } else {
            do {
                // Single attempt; on failure use the fallback below rather
                // than spending 3x the semaphore timeout.
                let reaction = try await click(item: clickItem, with: mouseButton, skipInputPause: true, maxAttempts: 1)
                observedInterfaceWindowID = reaction.openedWindowID
            } catch {
                MenuBarItemManager.diagLog.error("Error clicking item (first attempt): \(error); attempting fallback click")

                let fallbackItem = await refreshedClickTarget(for: clickItem, on: resolvedDisplayID)

                do {
                    let reaction = try await click(item: fallbackItem, with: mouseButton, skipInputPause: true)
                    observedInterfaceWindowID = reaction.openedWindowID
                } catch {
                    MenuBarItemManager.diagLog.error("Fallback click also failed for \(item.logString): \(error)")
                    return .movedButClickFailed
                }
            }
        }

        // Only the AX press path still has to scan for the opened window.
        let interfaceCandidates: [WindowInfo]
        if let observedInterfaceWindowID, let observed = WindowInfo(windowID: observedInterfaceWindowID) {
            interfaceCandidates = [observed]
        } else {
            await eventSleep(for: .milliseconds(100))
            interfaceCandidates = WindowInfo.createWindows(option: .onScreen)
                .filter { !idsBeforeClick.contains($0.windowID) }
        }

        // The click path's window gets the same test as a scan's:
        // ``ClickReactionVerifier`` accepts any new window as a reaction,
        // which is a poor guess at the menu.
        context.shownInterfaceWindow = MenuBarItemManager.interfaceWindowToTrack(
            among: interfaceCandidates,
            interfacePIDs: context.interfacePIDs
        )

        return .movedAndClicked
    }

    /// Resolves the best move destination for returning a temporarily shown
    /// item to its original section.
    ///
    /// Tries ``TemporarilyShownItemContext/returnDestination``, then
    /// ``TemporarilyShownItemContext/fallbackNeighbor``, then the original
    /// section's control item.
    private func resolveReturnDestination(
        for context: TemporarilyShownItemContext,
        in items: [MenuBarItem]
    ) -> MoveDestination? {
        // Re-wrap with the fresh item so the move uses current bounds.
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
            // interfaceState can enumerate every window; evaluate it once.
            let interfaceStates = temporarilyShownItemContexts.map {
                ($0, $0.interfaceState)
            }
            guard !interfaceStates.contains(where: { $0.1 == .showing }) else {
                for context in temporarilyShownItemContexts {
                    context.closedSince = nil
                }
                MenuBarItemManager.diagLog.debug("Menu bar item interface is shown, so waiting to rehide")
                runRehideTimer(for: Self.rehidePollInterval)
                return
            }

            // An unidentified interface may still be open (#924), so spend a
            // bounded number of checks before treating it as closed.
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

            // The user's hide-again delay, counted from the menu closing, so
            // an accidental click away leaves the item within reach (#342).
            let delay = appState.settings.general.tempShowInterval
            if delay > 0 {
                let now = Date()
                for context in temporarilyShownItemContexts where context.closedSince == nil {
                    context.closedSince = now
                }
                let closedFor = temporarilyShownItemContexts
                    .compactMap { $0.closedSince.map { now.timeIntervalSince($0) } }
                    .min() ?? delay
                if closedFor < delay {
                    runRehideTimer(for: min(Self.rehidePollInterval, delay - closedFor))
                    return
                }
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

        // Shorter from temporarilyShow, where the user is waiting; move()
        // guards the race itself.
        await eventSleep(for: isCalledFromTemporarilyShow ? .milliseconds(50) : .milliseconds(250))

        MenuBarItemManager.diagLog.debug("Rehiding temporarily shown items")

        // 30 s watchdog, or the 1 s default fires mid-rehide and flickers the
        // cursor (#899).
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer {
            MouseHelpers.showCursor()
        }

        // The outer hide/show owns the cursor, or it flickers per item.
        let wasBulkApplyInProgress = isBulkApplyInProgress
        isBulkApplyInProgress = true
        defer {
            isBulkApplyInProgress = wasBulkApplyInProgress
        }

        while let context = currentContexts.popLast() {
            guard let item = items.first(matchingTag: context.tag, pid: context.sourcePID) else {
                // The owning process is gone, so the item never comes back;
                // drop it now instead of retrying for a dead icon. (#1149)
                if context.sourcePID > 0, !Self.previousPIDIsLive(context.sourcePID) {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Dropping temporarily shown item \(context.tag) after its \
                        source process (\(context.sourcePID)) terminated
                        """
                    )
                    // Keep the persisted records for relocatePendingItems.
                    continue
                }
                context.notFoundAttempts += 1
                MenuBarItemManager.diagLog.debug(
                    """
                    Missing temporarily shown item \(context.tag) on active space \
                    (not-found attempt \(context.notFoundAttempts)); will retry
                    """
                )
                // Retry: it may be on another space. After enough attempts,
                // leave recovery to relocatePendingItems.
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
                // Rehiding completes the user's reveal, so it is theirs too.
                try await move(
                    item: item,
                    to: destination,
                    on: context.displayID,
                    skipInputPause: true,
                    options: .init(isUserInitiated: true)
                )
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
                // 3 per call x 3 timer rounds. Beyond this, retrying only
                // saturates the event semaphore.
                let maxTotalRehideAttempts = 9
                if context.rehideAttempts < 3 {
                    currentContexts.append(context)
                } else if context.rehideAttempts < maxTotalRehideAttempts {
                    failedContexts.append(context)
                } else {
                    // Give up this session. The waitForRelaunch sentinel holds
                    // the windowID, so a relaunch clears it.
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
        // The user placed the item explicitly.
        let tagIdentifier = tag.tagIdentifier
        if pendingRelocations.removeValue(forKey: tagIdentifier) != nil {
            pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            persistPendingRelocations()
        }
    }
}
