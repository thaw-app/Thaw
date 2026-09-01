//
//  LayoutBarPaddingView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Observation

/// A Cocoa view that manages the menu bar layout interface.
final class LayoutBarPaddingView: NSView {
    private static let diagLog = DiagLog(category: "LayoutBarPaddingView")

    private let container: LayoutBarContainer
    private var isStabilizing = false

    private var notchView: NotchIndicatorView?
    private var notchWidthConstraint: NSLayoutConstraint?
    private var notchTrailingConstraint: NSLayoutConstraint?
    private var minWidthConstraint: NSLayoutConstraint?
    private var containerLeadingAfterNotchConstraint: NSLayoutConstraint?
    private var containerLeadingInsetConstraint: NSLayoutConstraint?
    private var notchObservers = Set<AnyCancellable>()

    /// Task observing `menuBarManager.averageColorInfo` (wave 3), replacing
    /// the old `$averageColorInfo` sink.
    private var averageColorInfoObservationTask: Task<Void, Never>?

    deinit {
        averageColorInfoObservationTask?.cancel()
    }

    /// The layout view's arranged views.
    var arrangedViews: [LayoutBarArrangedView] {
        get { container.arrangedViews }
        set { container.arrangedViews = newValue }
    }

    /// Creates a layout bar view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    init(appState: AppState, section: MenuBarSection.Name) {
        self.container = LayoutBarContainer(appState: appState, section: section)

        super.init(frame: .zero)

        addSubview(container)
        self.translatesAutoresizingMaskIntoConstraints = false

        let leadingInsetConstraint = leadingAnchor.constraint(lessThanOrEqualTo: container.leadingAnchor, constant: -7.5)
        self.containerLeadingInsetConstraint = leadingInsetConstraint

        NSLayoutConstraint.activate([
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 7.5),
            leadingInsetConstraint,
        ])

        registerForDraggedTypes([.layoutBarItem])

        configureNotchObservers(appState: appState)
        updateNotchPresentation()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isStabilizing else { return [] }
        // Freeze the destination's arrangedViews so that the cache refresh
        // triggered while the system move is in flight cannot overwrite the
        // mid-drag visual state. updateNewItemsPlacement at the end of move()
        // depends on that state to capture the badge's new neighbors; without
        // this guard the dropped item bounces to the wrong side of the badge.
        container.canSetArrangedViews = false
        return container.updateArrangedViewsForDrag(with: sender, phase: .entered)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard !isStabilizing else { return }
        if let sender {
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
        }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isStabilizing else { return [] }
        return container.updateArrangedViewsForDrag(with: sender, phase: .updated)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard !isStabilizing else { return }
        container.updateArrangedViewsForDrag(with: sender, phase: .ended)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggingSource = sender.draggingSource as? LayoutBarArrangedView else {
            container.canSetArrangedViews = true
            return false
        }

        if case let .item(draggingItem) = draggingSource.kind,
           draggingItem.tag == .visibleControlItem,
           container.section != .visible
        {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Cannot move \(Constants.displayName) icon.")
            alert.informativeText = String(localized: "The \(Constants.displayName) icon must always remain in the visible section.")

            if let window {
                alert.beginSheetModal(for: window)
            }

            // Revert the visual state: remove the item from the container it was dropped into
            // and set hasContainer to false so it snaps back to its original container.
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
            draggingSource.hasContainer = false

            container.canSetArrangedViews = true
            return false
        }

        if draggingSource.isNewItemsBadge {
            let sourceContainer = draggingSource.oldContainerInfo?.container
            container.appState?.itemManager.updateNewItemsPlacement(
                section: container.section,
                arrangedViews: arrangedViews
            )
            draggingSource.oldContainerInfo = nil
            container.canSetArrangedViews = true
            sourceContainer?.canSetArrangedViews = true
            if let appState = container.appState {
                sourceContainer?.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: sourceContainer?.section ?? container.section))
                if sourceContainer !== container {
                    container.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: container.section))
                }
            }
            return true
        }

        var willMove = false
        let sourceContainer = draggingSource.oldContainerInfo?.container

        // A grouped item drags its whole group: resolve the drag unit once
        // and move members as one block, preserving their relative order.
        var draggedUnit = [MenuBarItem]()
        if case let .item(draggedItem) = draggingSource.kind,
           let appState = container.appState
        {
            // A cross-container drop only inserts the dragged view here, so
            // the group's other members are still arranged in the source bar.
            // Resolving against the destination alone would see a lone member,
            // skip the group, and split it across sections.
            var arrangedItems = items(in: arrangedViews)
            if let sourceContainer, sourceContainer !== container {
                let known = Set(arrangedItems.map(\.tag))
                arrangedItems += items(in: sourceContainer.arrangedViews).filter { !known.contains($0.tag) }
            }
            draggedUnit = appState.itemGroupManager.dragUnit(for: draggedItem, in: arrangedItems)
        } else if case let .item(draggedItem) = draggingSource.kind {
            draggedUnit = [draggedItem]
        }

        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if arrangedViews.count == 1 {
                willMove = true
                Task {
                    guard case let .item(draggingItem) = draggingSource.kind else {
                        self.container.canSetArrangedViews = true
                        sourceContainer?.canSetArrangedViews = true
                        return
                    }
                    if let destination = await self.liveFallbackDestinationForDraggedItem() {
                        self.move(items: draggedUnit, startingWith: draggingItem, to: destination, sourceContainer: sourceContainer)
                    } else {
                        Self.diagLog.error("No target item for layout bar drag")
                        self.container.canSetArrangedViews = true
                        sourceContainer?.canSetArrangedViews = true
                    }
                }
            } else if case let .item(draggingItem) = draggingSource.kind {
                if let targetItem = nearestItem(toRightOf: index) {
                    willMove = true
                    move(items: draggedUnit, startingWith: draggingItem, to: .leftOfItem(targetItem), sourceContainer: sourceContainer)
                } else if let targetItem = nearestItem(toLeftOf: index) {
                    willMove = true
                    move(items: draggedUnit, startingWith: draggingItem, to: .rightOfItem(targetItem), sourceContainer: sourceContainer)
                } else if !arrangedViews.isEmpty {
                    willMove = true
                    Task {
                        if let destination = await self.liveFallbackDestinationForDraggedItem() {
                            self.move(items: draggedUnit, startingWith: draggingItem, to: destination, sourceContainer: sourceContainer)
                        } else {
                            Self.diagLog.error("No target item for layout bar drag")
                            self.container.canSetArrangedViews = true
                            sourceContainer?.canSetArrangedViews = true
                        }
                    }
                }
            }
        }

        // Only re-enable view updates here if no move was initiated.
        // When a move IS initiated, the move() Task re-enables after stabilization.
        if !willMove {
            container.canSetArrangedViews = true
        }

        return true
    }

    /// Moves a group's drag unit as one block.
    ///
    /// The unit's leftmost member takes `destination`; every remaining member
    /// is then chained to its right, so the unit keeps its internal order.
    /// Members that were scattered are pulled to the drop point, which is what
    /// makes "drag any member" gather the whole group.
    private func move(
        items: [MenuBarItem],
        startingWith draggedItem: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        sourceContainer: LayoutBarContainer? = nil
    ) {
        guard let appState = container.appState else {
            return
        }
        // `items` is already in arranged-view order, so its first element is
        // the group's leftmost member — the same anchor that gathering a group
        // uses. Promoting the dragged member instead would land it ahead of
        // the siblings to its left and reorder the group.
        guard items.count > 1 else {
            move(item: draggedItem, to: destination, sourceContainer: sourceContainer)
            return
        }

        Task { [self, appState, sourceContainer] in
            guard !isStabilizing else {
                // Bail without leaving either container frozen: the drop
                // container was frozen by draggingEntered, the source by the
                // dragging session.
                await MainActor.run {
                    self.container.canSetArrangedViews = true
                    if sourceContainer !== self.container {
                        sourceContainer?.canSetArrangedViews = true
                    }
                }
                return
            }
            isStabilizing = true
            await MainActor.run { self.showOverlay(true) }
            guard await (try? Task.sleep(for: .milliseconds(150))) != nil else {
                await resetStabilizingStateIfNeeded(sourceContainer: sourceContainer)
                return
            }

            // One awaited move per member, so the window in which a move can
            // still be in flight scales with the unit. Without this, a move
            // that never returns leaves isStabilizing true and both bars
            // frozen for the rest of the session.
            let watchdogTask = Task { [weak self, weak appState, weak sourceContainer] in
                try? await Task.sleep(for: (MenuBarItemManager.layoutWatchdogTimeout * items.count) + .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.resetStabilizingStateIfNeeded(sourceContainer: sourceContainer)
                guard let appState else { return }
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            }

            var pendingMove: (item: MenuBarItem, destination: MenuBarItemManager.MoveDestination)?
            do {
                var previous: MenuBarItem?
                for item in items {
                    // The first member takes the drop destination; each next
                    // member chains to the previous one's right, keeping the
                    // unit's relative order.
                    let target: MenuBarItemManager.MoveDestination =
                        previous.map { .rightOfItem($0) } ?? destination
                    pendingMove = (item, target)
                    try await appState.itemManager.move(
                        item: item,
                        to: target,
                        skipInputPause: true,
                        watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
                    )
                    appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                    previous = item
                }
                if let last = previous,
                   await stabilizePlacement(
                       of: last,
                       // Re-chain to the member before the last, not to the
                       // head's destination: re-asserting the head's drop slot
                       // would land the retried member AHEAD of the block,
                       // scrambling the order the chaining loop produced.
                       to: items.dropLast().last.map { .rightOfItem($0) } ?? destination,
                       expectedSection: container.section,
                       appState: appState
                   )
                {
                    appState.itemManager.recordExternalMoveOperation()
                }
            } catch MenuBarItemManager.EventError.menuTrackingActive {
                Self.diagLog.info("Group move deferred, a menu bar item menu was open")
            } catch {
                Self.diagLog.error("Error moving menu bar item group: \(error)")
                // Earlier members may already have moved, so logging alone
                // leaves the unit split with no user-visible signal. Recover
                // the member that failed the way a single-item move does,
                // alerting only if it never reaches its slot.
                if let pendingMove {
                    await recoverFromFailedMove(
                        of: pendingMove.item,
                        to: pendingMove.destination,
                        error: error,
                        appState: appState
                    )
                }
            }
            watchdogTask.cancel()
            // Mirror the single-item move's completion: re-anchor the New
            // Items badge and re-enable BOTH containers before the flags are
            // reset. The source bar was frozen by the dragging session and
            // would stay stuck at its mid-drag snapshot until an unrelated
            // later drag reset it.
            if let appState = container.appState {
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
            await MainActor.run {
                if let appState = self.container.appState,
                   self.containsNewItemsBadge()
                {
                    appState.itemManager.updateNewItemsPlacement(
                        section: self.container.section,
                        arrangedViews: self.container.arrangedViews
                    )
                }
                self.container.canSetArrangedViews = true
                if sourceContainer !== self.container {
                    sourceContainer?.canSetArrangedViews = true
                }
            }
            await resetStabilizingStateIfNeeded()
        }
    }

    private func move(
        item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        sourceContainer: LayoutBarContainer? = nil
    ) {
        guard let appState = container.appState else {
            return
        }
        // Explicit strong captures: the move must complete even if the view
        // is torn down mid-drag; only the longer-lived watchdog below holds
        // weak references.
        Task { [self, appState] in
            guard !isStabilizing else { return }
            isStabilizing = true
            await MainActor.run { self.showOverlay(true) }
            // Increased delay to allow macOS to settle after operations like Reset Layout.
            // Prevents transient errors when dragging items immediately after reset.
            // A cancelled sleep must not leave the overlay up and isStabilizing
            // stuck true (the watchdog that would reset them hasn't started yet).
            guard await (try? Task.sleep(for: .milliseconds(150))) != nil else {
                await resetStabilizingStateIfNeeded()
                return
            }

            let watchdogTask = Task { [weak self, weak appState] in
                try? await Task.sleep(for: MenuBarItemManager.layoutWatchdogTimeout + .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.resetStabilizingStateIfNeeded()
                guard let appState else { return }
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            }
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
                )
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                if await stabilizePlacement(
                    of: item,
                    to: destination,
                    expectedSection: container.section,
                    appState: appState
                ) {
                    appState.itemManager.recordExternalMoveOperation()
                }
            } catch MenuBarItemManager.EventError.menuTrackingActive {
                // A menu bar item's menu (Wi-Fi picker, input method panel,
                // etc.) was open and the move was deferred to avoid tearing
                // down the user's interaction. This isn't a failure worth
                // alerting on — log only.
                Self.diagLog.info("Move deferred, a menu bar item menu was open")
            } catch {
                Self.diagLog.error("Error moving menu bar item: \(error)")
                await recoverFromFailedMove(of: item, to: destination, error: error, appState: appState)
            }
            watchdogTask.cancel()
            if let appState = container.appState {
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
            await MainActor.run {
                self.isStabilizing = false
                self.showOverlay(false)
                // Update the badge anchor BEFORE re-enabling view updates, using
                // the current visual arrangement from the drag. This ensures the
                // didSet refresh uses the correct anchor position.
                // Only update if this section actually contains the badge.
                if let appState = self.container.appState,
                   self.containsNewItemsBadge()
                {
                    appState.itemManager.updateNewItemsPlacement(
                        section: self.container.section,
                        arrangedViews: self.container.arrangedViews
                    )
                }
                // Re-enable view updates on both the destination (frozen by
                // draggingEntered) and the source (frozen by willBeginAt on
                // the dragging session). Without resetting the source, its
                // arrangedViews would stay frozen at the mid-drag snapshot
                // until the next drag originated from that container.
                self.container.canSetArrangedViews = true
                if sourceContainer !== self.container {
                    sourceContainer?.canSetArrangedViews = true
                }
            }
        }
    }

    /// Recovers from a failed move, alerting the user only when the item
    /// did not reach the slot it was dragged to.
    ///
    /// Shared by the single-item and group paths so a failed member of a
    /// group move is as informative as a failed single-item move.
    private func recoverFromFailedMove(
        of item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        error: any Error,
        appState: AppState
    ) async {
        // The system event-driven move sometimes throws cannotComplete
        // after macOS has already settled the item into the requested
        // slot: the click sequence bounces the item past the target
        // and back during verification, but a subsequent reconciliation
        // lands it where the user asked. Resample the cache after a
        // short settle window and only show the alert when the item
        // is NOT in the position the user actually dragged it to;
        // showing it for a move that visibly worked is a false alarm.
        try? await Task.sleep(for: .milliseconds(250))
        await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        let reachedPosition = didItemReachIntendedPosition(
            item: item,
            destination: destination,
            expectedSection: container.section,
            cache: appState.itemManager.itemCache
        )
        let isBlocked = if reachedPosition {
            false
        } else {
            await appState.itemManager.isItemCurrentlyBlocked(item)
        }
        let action = MenuBarItemManager.classifyHiddenDragFailure(
            reachedPosition: reachedPosition,
            isBlocked: isBlocked,
            controlItemsMissing: appState.itemManager.areControlItemsMissing
        )
        switch action {
        case .suppress:
            Self.diagLog.info("Move verification failed but \(item.logString) reached intended position in \(container.section.logString); suppressing alert")
            appState.itemManager.recordExternalMoveOperation()
        case .rescueAndRetry:
            // The item is stuck at the x=-1 sentinel. Rescue it to
            // the visible section, let macOS settle, then retry the
            // original move exactly once (no loop). Only if that
            // retry also fails do we alert, and with a calm message
            // rather than the raw error, matching the safe-harbor
            // behavior of restoreBlockedItemsToVisible.
            Self.diagLog.warning("\(item.logString) is blocked (x=-1); attempting one rescue-and-retry before alerting")
            _ = await appState.itemManager.rescueBlockedItemToVisible(item)
            try? await Task.sleep(for: .milliseconds(250))
            await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
                )
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                if await stabilizePlacement(
                    of: item,
                    to: destination,
                    expectedSection: container.section,
                    appState: appState
                ) {
                    appState.itemManager.recordExternalMoveOperation()
                }
            } catch MenuBarItemManager.EventError.menuTrackingActive {
                // Same deferral the outer catch handles: the user
                // opened a menu bar item's menu while the retry was
                // in flight. Nothing failed, so don't alert.
                Self.diagLog.info("Rescue-and-retry deferred, a menu bar item menu was open")
            } catch {
                Self.diagLog.error("Rescue-and-retry failed for \(item.logString): \(error)")
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = container.section == .alwaysHidden
                    ? String(localized: "Couldn't move \(item.displayName) to the always-hidden section.")
                    : String(localized: "Couldn't move \(item.displayName) to the hidden section.")
                alert.informativeText = String(localized: "The item was left in the visible section so it isn't stuck offscreen. Try dragging it again in a moment.")
                alert.runModal()
            }
        case .alertControlItemsMissing:
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn't move the item right now.")
            alert.informativeText = String(localized: "\(Constants.displayName) can't locate its hidden-section divider right now. It is attempting recovery in the background — try again in a few seconds.")
            alert.runModal()
        case .alertGeneric:
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    /// Returns true when the dragged item is sitting in the slot the user
    /// asked for: in the destination section, immediately adjacent to the
    /// target on the requested side. For control-item targets (section
    /// dividers) there is no array entry to anchor against, so containment
    /// in the destination section is the strongest claim we can make.
    private func didItemReachIntendedPosition(
        item: MenuBarItem,
        destination: MenuBarItemManager.MoveDestination,
        expectedSection: MenuBarSection.Name,
        cache: MenuBarItemManager.ItemCache
    ) -> Bool {
        let sectionItems = cache[expectedSection]
        guard let itemIndex = sectionItems.firstIndex(where: { $0.tag == item.tag }) else {
            return false
        }
        let target = destination.targetItem
        if target.isControlItem {
            return true
        }
        guard let targetIndex = sectionItems.firstIndex(where: { $0.tag == target.tag }) else {
            return false
        }
        return switch destination {
        case .leftOfItem: itemIndex + 1 == targetIndex
        case .rightOfItem: itemIndex == targetIndex + 1
        }
    }

    @MainActor
    private func resetStabilizingStateIfNeeded(sourceContainer: LayoutBarContainer? = nil) async {
        if isStabilizing {
            isStabilizing = false
            showOverlay(false)
            container.canSetArrangedViews = true
            // The source bar is frozen by the dragging session, so an abnormal
            // exit has to thaw it too or it stays at its mid-drag snapshot
            // until an unrelated later drag resets it.
            if sourceContainer !== container {
                sourceContainer?.canSetArrangedViews = true
            }
        }
    }

    private func showOverlay(_ visible: Bool) {
        container.alphaValue = visible ? 0.6 : 1.0
    }

    private func containsNewItemsBadge() -> Bool {
        for arrangedView in container.arrangedViews where arrangedView.isNewItemsBadge {
            return true
        }
        return false
    }

    private func items(in views: [LayoutBarArrangedView]) -> [MenuBarItem] {
        views.compactMap { view -> MenuBarItem? in
            if case let .item(item) = view.kind {
                return item
            }
            return nil
        }
    }

    private func nearestItem(toRightOf index: Int) -> MenuBarItem? {
        guard arrangedViews.indices.contains(index + 1) else {
            return nil
        }
        for candidateIndex in (index + 1) ..< arrangedViews.count {
            if case let .item(item) = arrangedViews[candidateIndex].kind {
                return item
            }
        }
        return nil
    }

    private func nearestItem(toLeftOf index: Int) -> MenuBarItem? {
        guard arrangedViews.indices.contains(index - 1) else {
            return nil
        }
        for candidateIndex in stride(from: index - 1, through: 0, by: -1) {
            if case let .item(item) = arrangedViews[candidateIndex].kind {
                return item
            }
        }
        return nil
    }

    private func liveFallbackDestinationForDraggedItem() async -> MenuBarItemManager.MoveDestination? {
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        return switch container.section {
        case .visible:
            nil
        case .hidden:
            items.first(matching: .hiddenControlItem).map { .leftOfItem($0) }
        case .alwaysHidden:
            items.first(matching: .alwaysHiddenControlItem).map { .leftOfItem($0) }
        }
    }

    /// Ensures the dragged item remains in the intended section and its icon appears.
    private func stabilizePlacement(
        of item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        expectedSection: MenuBarSection.Name,
        appState: AppState
    ) async -> Bool {
        // First refresh caches and verify placement.
        await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)

        func isInExpectedSection() -> Bool {
            appState.itemManager.itemCache[expectedSection].contains { $0.tag == item.tag }
        }

        if !isInExpectedSection() {
            // Allow macOS a brief moment to settle, then retry once.
            try? await Task.sleep(for: .milliseconds(120))
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
                )
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            } catch {
                Self.diagLog.error("Stabilize move failed: \(error)")
            }
        }

        // Refresh images so icons show immediately in the UI without clearing to avoid temporary gaps.
        await MainActor.run {
            appState.imageCache.performCacheCleanup()
        }
        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        return isInExpectedSection()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateNotchPresentation()
        }
    }

    private func configureNotchObservers(appState: AppState) {
        guard container.section == .visible else {
            return
        }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNotchPresentation()
            }
            .store(in: &notchObservers)

        NotificationCenter.default
            .publisher(for: NSWindow.didChangeScreenNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let notifyingWindow = notification.object as? NSWindow,
                      notifyingWindow === self.window
                else { return }
                self.updateNotchPresentation()
            }
            .store(in: &notchObservers)

        // `menuBarManager` is now `@Observable` (wave 3), so it no longer has
        // an `$averageColorInfo` publisher.
        averageColorInfoObservationTask = Task { [weak self, weak appState] in
            var previous: MenuBarAverageColorInfo?
            let changes = Observations { appState?.menuBarManager.averageColorInfo }
            for await colorInfo in changes {
                guard let self else { return }
                guard colorInfo != previous else { continue }
                previous = colorInfo
                self.notchView?.averageColorInfo = colorInfo
            }
        }
    }

    private func updateNotchPresentation() {
        guard
            container.section == .visible,
            let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main,
            screen.hasNotch,
            let notch = screen.frameOfNotch
        else {
            tearDownNotchPresentation()
            return
        }

        let notchIndicatorWidth = notch.width + MenuBarSection.notchGap
        // Distance from the bar's trailing edge to the notch indicator's
        // trailing edge — equals the real-world items area (everything
        // right of `notch.maxX + notchGap` in the menu bar) plus the 7.5pt
        // cosmetic inset that sits between items and the rounded edge.
        let notchTrailingOffset = max(0, screen.frame.maxX - notch.maxX - MenuBarSection.notchGap) + 7.5
        // Bar must always be wide enough to represent the real-world span
        // from `notch.minX` to `screen.maxX`, with no inset on the left
        // (the notch itself sits flush) and 7.5pt cosmetic inset on the
        // right. When the Settings pane is wider, the bar grows past this
        // and the empty area is shown to the LEFT of the notch.
        let barMinWidth = max(0, screen.frame.maxX - notch.minX) + 7.5
        let colorInfo = container.appState?.menuBarManager.averageColorInfo

        if let notchView {
            notchView.isHidden = false
            notchView.averageColorInfo = colorInfo
            notchWidthConstraint?.constant = notchIndicatorWidth
            notchTrailingConstraint?.constant = -notchTrailingOffset
            minWidthConstraint?.constant = barMinWidth
            containerLeadingInsetConstraint?.constant = 0
            return
        }

        let view = NotchIndicatorView(averageColorInfo: colorInfo)
        addSubview(view, positioned: .below, relativeTo: container)
        self.notchView = view

        let widthConstraint = view.widthAnchor.constraint(equalToConstant: notchIndicatorWidth)
        let trailingConstraint = view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -notchTrailingOffset)
        // Lower priority so the bar can grow leftward when the user has
        // more items than fit between the notch and the bar's trailing
        // edge. With this at .required, container.leading is hard-pinned
        // at notchView.trailing, the container's slot is fixed in width,
        // and overflowing items get clipped without ever pushing the
        // documentView wider than the scroll view's visible area, so no
        // horizontal scrollbar appears. Dropping to .defaultHigh keeps
        // the notch as the preferred boundary while letting AutoLayout
        // break it when items need more room — paddingView then extends
        // further left (via the existing leading inset constraint),
        // NSScrollView observes documentView wider than visible and
        // surfaces the horizontal scroller. The container is z-above
        // notchView, so items rendered over the notch indicator stay
        // draggable.
        let containerLeading = container.leadingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor)
        containerLeading.priority = .defaultHigh
        let minWidth = widthAnchor.constraint(greaterThanOrEqualToConstant: barMinWidth)

        NSLayoutConstraint.activate([
            trailingConstraint,
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint,
            containerLeading,
            minWidth,
        ])

        notchWidthConstraint = widthConstraint
        notchTrailingConstraint = trailingConstraint
        containerLeadingAfterNotchConstraint = containerLeading
        minWidthConstraint = minWidth
        containerLeadingInsetConstraint?.constant = 0
    }

    private func tearDownNotchPresentation() {
        notchWidthConstraint?.isActive = false
        notchTrailingConstraint?.isActive = false
        containerLeadingAfterNotchConstraint?.isActive = false
        minWidthConstraint?.isActive = false
        notchWidthConstraint = nil
        notchTrailingConstraint = nil
        containerLeadingAfterNotchConstraint = nil
        minWidthConstraint = nil
        containerLeadingInsetConstraint?.constant = -7.5
        notchView?.removeFromSuperview()
        notchView = nil
    }
}
