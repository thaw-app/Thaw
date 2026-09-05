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
    private static let stabilizationRecoveryTimeout: Duration = .seconds(45)

    private let container: LayoutBarContainer
    private var isStabilizing = false
    private var stabilizationGeneration = 0
    private var stabilizationTask: Task<Void, Never>?
    private weak var acceptedDraggingSource: LayoutBarArrangedView?

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
        stabilizationTask?.cancel()
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
        guard !isStabilizing,
              let sourceView = sender.draggingSource as? LayoutBarArrangedView,
              Self.canAcceptDrag(
                  containerAllowsUpdates: container.canSetArrangedViews,
                  beganInContainer: sourceView.beganDragging(in: container),
                  alreadyAccepted: acceptedDraggingSource === sourceView
              )
        else { return [] }
        acceptedDraggingSource = sourceView
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
        guard let acceptedDraggingSource else { return }
        if let sender {
            guard sender.draggingSource as? LayoutBarArrangedView === acceptedDraggingSource else {
                return
            }
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
        }

        // A pointer can cross one or more rows before it reaches the final
        // destination. Each entered row is frozen above, so thaw a row as
        // soon as it is no longer participating in the drag. Keep only the
        // original source frozen; refreshing it now would reinsert a duplicate
        // item behind the dragging image.
        if !acceptedDraggingSource.beganDragging(in: container) {
            container.resumeArrangedViewUpdatesWithoutAnimation()
        }
        self.acceptedDraggingSource = nil
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isStabilizing,
              sender.draggingSource as? LayoutBarArrangedView === acceptedDraggingSource
        else { return [] }
        return container.updateArrangedViewsForDrag(with: sender, phase: .updated)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard !isStabilizing,
              sender.draggingSource as? LayoutBarArrangedView === acceptedDraggingSource
        else { return }
        container.updateArrangedViewsForDrag(with: sender, phase: .ended)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggingSource = sender.draggingSource as? LayoutBarArrangedView,
              acceptedDraggingSource === draggingSource
        else {
            return false
        }
        defer { acceptedDraggingSource = nil }

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

            container.resumeArrangedViewUpdatesWithoutAnimation()
            // The dragging session froze the source row too, and the refusal
            // starts no move task that would thaw it later. Resume it like
            // every other refusal path; `oldContainerInfo` stays so the drag
            // session's end can restore the original view to its old slot.
            if let sourceContainer = draggingSource.oldContainerInfo?.container,
               sourceContainer !== container
            {
                sourceContainer.resumeArrangedViewUpdatesWithoutAnimation()
            }
            return false
        }

        if draggingSource.isNewItemsBadge {
            let sourceContainer = draggingSource.oldContainerInfo?.container
            container.appState?.itemManager.updateNewItemsPlacement(
                section: container.section,
                arrangedViews: arrangedViews
            )
            draggingSource.oldContainerInfo = nil
            container.resumeArrangedViewUpdatesWithoutAnimation()
            sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
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
                // The unit comes back in the order of the items it was
                // resolved against, and the block move commits that order, so
                // the source bar has to lead: put the dragged view back in the
                // slot it left and let the destination fill in behind it.
                // Leading with the destination would rank the dragged member
                // ahead of the siblings it was taken from and turn a group of
                // a1, a2, a3 into a2, a1, a3 as soon as a2 is the one dragged.
                var sourceViews = sourceContainer.arrangedViews
                if !sourceViews.contains(draggingSource),
                   let oldIndex = draggingSource.oldContainerInfo?.index
                {
                    sourceViews.insert(draggingSource, at: min(oldIndex, sourceViews.count))
                }
                arrangedItems = Self.groupResolutionItems(
                    sourceItems: items(in: sourceViews),
                    destinationItems: arrangedItems
                )
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
                        self.container.resumeArrangedViewUpdatesWithoutAnimation()
                        sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
                        return
                    }
                    if let destination = await self.liveFallbackDestinationForDraggedItem() {
                        self.move(items: draggedUnit, startingWith: draggingItem, to: destination, sourceContainer: sourceContainer)
                    } else {
                        Self.diagLog.error("No target item for layout bar drag")
                        self.container.resumeArrangedViewUpdatesWithoutAnimation()
                        sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
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
                            self.container.resumeArrangedViewUpdatesWithoutAnimation()
                            sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
                        }
                    }
                }
            }
        }

        // Only re-enable view updates here if no move was initiated.
        // When a move IS initiated, the move() Task re-enables after stabilization.
        if !willMove {
            container.resumeArrangedViewUpdatesWithoutAnimation()
            if sourceContainer !== container {
                sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
            }
            draggingSource.oldContainerInfo = nil
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
            var failedMemberCount = 0
            do {
                var previous: MenuBarItem?
                for item in items {
                    // The first member takes the drop destination; each next
                    // member chains to the previous one's right, keeping the
                    // unit's relative order.
                    let target: MenuBarItemManager.MoveDestination =
                        previous.map { .rightOfItem($0) } ?? destination
                    pendingMove = (item, target)
                    do {
                        try await appState.itemManager.move(
                            item: item,
                            to: target,
                            skipInputPause: true,
                            options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout)
                        )
                    } catch {
                        // One member failing must not strand the rest of the
                        // unit half-moved and silent. Recover this member the
                        // way a single-item move does -- it alerts only when
                        // the item truly never reached its slot -- then keep
                        // chaining the remaining members from the last
                        // successful position, which preserves the order of
                        // everything that did move.
                        failedMemberCount += 1
                        Self.diagLog.error(
                            "Group move failed on member \(failedMemberCount)/\(items.count) (\(item.logString)); recovering and continuing"
                        )
                        await recoverFromFailedMove(
                            of: item,
                            to: target,
                            error: error,
                            appState: appState
                        )
                        continue
                    }
                    appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                    previous = item
                }
                if let last = previous {
                    // Re-chain to the member before the last, not to the
                    // head's destination: re-asserting the head's drop slot
                    // would land the retried member AHEAD of the block,
                    // scrambling the order the chaining loop produced.
                    let lastTarget: MenuBarItemManager.MoveDestination =
                        items.dropLast().last.map { .rightOfItem($0) } ?? destination
                    // A stabilization that cannot confirm the block's
                    // placement is a failed group move, not a success. The
                    // recovery re-verifies from a fresh cache: when the block
                    // actually settled, the alert is suppressed and the
                    // operation is recorded; when it did not, the rescue and
                    // the alert fire as they would for a single item.
                    if await stabilizePlacement(
                        of: last,
                        to: lastTarget,
                        expectedSection: container.section,
                        appState: appState,
                        generation: stabilizationGeneration
                    ) {
                        appState.itemManager.recordExternalMoveOperation()
                    } else {
                        Self.diagLog.warning(
                            "Group move of \(items.count) items could not confirm placement; verifying"
                        )
                        await recoverFromFailedMove(
                            of: last,
                            to: lastTarget,
                            error: GroupMoveStabilizationError(),
                            appState: appState
                        )
                    }
                }
                if failedMemberCount > 0 {
                    Self.diagLog.warning(
                        "Group move finished with \(failedMemberCount)/\(items.count) member(s) recovered after failure"
                    )
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

    /// Puts the view and the bar back in order after a drag's move never
    /// returned.
    ///
    /// Lives here rather than inside the watchdog task so its body is not a
    /// third closure nested inside the two ``move(item:to:sourceContainer:)``
    /// already opens.
    private func recoverFromUnreturnedMove(
        revealedSections: [MenuBarSection],
        appState: AppState?
    ) async {
        await resetStabilizingStateIfNeeded()
        if !revealedSections.isEmpty {
            // The move never returned, so the completion path that
            // re-conceals the sections revealed for the drag (#988)
            // has not run and may never run. Restore them here, the
            // same way, and give the spacer a beat to re-park the
            // divider before the closing cache pass records the
            // settled bar. Idempotent with a late completion: the
            // restore recomputes the persisted presentation.
            await MainActor.run {
                for section in revealedSections {
                    section.updateControlItemState(for: nil)
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let appState else { return }
        await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
    }

    /// A frozen row accepts only the drag that already owns that freeze. This
    /// prevents a second cross-row move from being reconciled by the first
    /// move's eventual thaw.
    static nonisolated func canAcceptDrag(
        containerAllowsUpdates: Bool,
        beganInContainer: Bool,
        alreadyAccepted: Bool
    ) -> Bool {
        containerAllowsUpdates || beganInContainer || alreadyAccepted
    }

    private func move(
        item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        sourceContainer: LayoutBarContainer? = nil
    ) {
        guard let appState = container.appState else {
            container.resumeArrangedViewUpdatesWithoutAnimation()
            sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
            return
        }
        guard !isStabilizing else {
            container.resumeArrangedViewUpdatesWithoutAnimation()
            sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
            return
        }
        isStabilizing = true
        stabilizationGeneration &+= 1
        let generation = stabilizationGeneration

        // Explicit strong captures: the move must complete even if the view
        // is torn down mid-drag; only the longer-lived watchdog below holds
        // weak references.
        stabilizationTask = Task { [self, appState] in
            var didValidateUserMove = false
            @MainActor
            func acceptValidatedUserMove() {
                // Clear an unfinished automatic-batch latch only after the
                // editor move has reached its requested settled placement.
                appState.itemManager.recordExternalMoveOperation()
                didValidateUserMove = true
            }

            // Increased delay to allow macOS to settle after operations like Reset Layout.
            // Prevents transient errors when dragging items immediately after reset.
            // A cancelled sleep must not leave the layouts frozen or isStabilizing
            // stuck true (the watchdog that would reset them hasn't started yet).
            guard await (try? Task.sleep(for: .milliseconds(150))) != nil else {
                _ = await resetStabilizingStateIfNeeded(
                    generation: generation,
                    sourceContainer: sourceContainer
                )
                return
            }

            // A drop into a section resolves to that section's divider when
            // the section has no other anchor. A concealed section parks its
            // divider offscreen, so the drag must not hand it to move() (#923):
            // the synthetic drag would target a click point far offscreen,
            // yank the item offscreen, and macOS would snap it straight back
            // until the retry budget ran out. When the destination section is
            // also EMPTY, though, refusing deadlocks the user (#988): the
            // parked divider is the only anchor the drop can ever resolve to,
            // and the refusal's "open the section and try dragging again"
            // advice has nothing to open. In that one state, reveal the
            // section to bring its divider back onscreen, retarget the move
            // onto the fresh divider, and re-conceal the section once the
            // item has settled. The always-hidden divider parks to the left
            // of the hidden section's content, so revealing the destination
            // alone is not enough to bring it onscreen when the hidden
            // section is also collapsed (#1010): the reveal covers every
            // section whose parked content would keep the divider offscreen.
            var destination = destination
            var revealedSections: [MenuBarSection] = []
            let targetItem = destination.targetItem
            if targetItem.isControlItem {
                let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
                // The destination comes from the frozen arranged views, whose
                // bounds were captured before the drag began. A divider that
                // parked in between would still read as on screen, so the
                // gate asks the window server where it is now. A window the
                // server cannot answer for counts as unreachable too: this
                // gate exists to keep a stranded divider away from move(),
                // and a stale snapshot is no evidence that the divider is
                // reachable.
                let targetBounds = Bridging.getWindowBounds(for: targetItem.windowID)
                let isReachable = targetBounds.map {
                    LayoutSolver.isOnScreen(bounds: $0, screenFrames: screenFrames)
                } ?? false
                if !isReachable {
                    if let (sections, freshDivider) = await revealEmptySectionDivider(
                        for: targetItem,
                        appState: appState
                    ) {
                        revealedSections = sections
                        destination = switch destination {
                        case .leftOfItem: .leftOfItem(freshDivider)
                        case .rightOfItem: .rightOfItem(freshDivider)
                        }
                    } else {
                        Self.diagLog.warning(
                            "Skipping drag of \(item.logString): destination divider \(targetItem.logString) is parked offscreen (\(targetBounds.map { "minX=\($0.minX)" } ?? "no window bounds")); section is collapsed"
                        )
                        await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                        _ = await self.resetStabilizingStateIfNeeded(
                            generation: generation,
                            sourceContainer: sourceContainer
                        )
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.alertStyle = .warning
                            alert.messageText = String(localized: "Couldn't move \(item.displayName) right now.")
                            alert.informativeText = String(localized: "The \(container.section.displayString) section is collapsed, so its divider is offscreen. Open the section and try dragging the item again.")
                            alert.runModal()
                        }
                        return
                    }
                }
            }

            let watchdogTask = Task { [weak self, weak appState, weak sourceContainer, revealedSections] in
                try? await Task.sleep(for: Self.stabilizationRecoveryTimeout)
                guard let self, !Task.isCancelled else { return }
                guard await self.resetStabilizingStateIfNeeded(
                    generation: generation,
                    sourceContainer: sourceContainer,
                    cancelOwningTask: true
                ) else { return }
                guard let appState else { return }
                // A drag that revealed a collapsed section (#988, #1010)
                // must re-conceal it even when the move never returned: the
                // completion path that re-conceals has not run and may never
                // run. The reset above thawed the bars; park the divider
                // back and give the spacer a beat before the closing cache
                // pass records the settled bar.
                if !revealedSections.isEmpty {
                    await MainActor.run {
                        for section in revealedSections {
                            section.updateControlItemState(for: nil)
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                // The owner task's cancellation runs its defer and cancels
                // this watchdog. Launch recovery independently so that mutual
                // cancellation cannot abort it, and retry until the old cache
                // owner actually releases CacheGate instead of issuing a
                // one-shot refresh that will probably be dropped.
                Task { [weak appState] in
                    guard let appState else { return }
                    guard await appState.itemManager.refreshCacheAfterLayoutEditorMove() else {
                        return
                    }
                    await appState.imageCache.updateCacheWithoutChecks(
                        sections: MenuBarSection.Name.allCases
                    )
                }
            }
            defer { watchdogTask.cancel() }
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout)
                )
                guard isCurrentStabilization(generation) else { return }
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                if await stabilizePlacement(
                    of: item,
                    to: destination,
                    expectedSection: container.section,
                    appState: appState,
                    generation: generation
                ), isCurrentStabilization(generation) {
                    acceptValidatedUserMove()
                }
            } catch MenuBarItemManager.EventError.menuTrackingActive {
                // A menu bar item's menu (Wi-Fi picker, input method panel,
                // etc.) was open and the move was deferred to avoid tearing
                // down the user's interaction. This isn't a failure worth
                // alerting on — log only.
                Self.diagLog.info("Move deferred, a menu bar item menu was open")
            } catch MenuBarItemManager.EventError.moveEngineBusy {
                // Another move held the bar for the whole wait. Nothing was
                // tried, so nothing failed; the editor snaps the item back
                // and the user can drag again once the bar is free.
                Self.diagLog.info("Move deferred, another move held the bar")
            } catch {
                guard isCurrentStabilization(generation) else { return }
                Self.diagLog.error("Error moving menu bar item: \(error)")
                // The system event-driven move sometimes throws cannotComplete
                // after macOS has already settled the item into the requested
                // slot: the click sequence bounces the item past the target
                // and back during verification, but a subsequent reconciliation
                // lands it where the user asked. Resample the cache after a
                // short settle window and only show the alert when the item
                // is NOT in the position the user actually dragged it to;
                // showing it for a move that visibly worked is a false alarm.
                try? await Task.sleep(for: .milliseconds(250))
                guard isCurrentStabilization(generation) else { return }
                _ = await appState.itemManager.refreshCacheAfterLayoutEditorMove()
                guard isCurrentStabilization(generation) else { return }
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
                guard isCurrentStabilization(generation) else { return }
                let action = MenuBarItemManager.classifyHiddenDragFailure(
                    reachedPosition: reachedPosition,
                    isBlocked: isBlocked,
                    controlItemsMissing: appState.itemManager.areControlItemsMissing
                )
                switch action {
                case .suppress:
                    Self.diagLog.info("Move verification failed but \(item.logString) reached intended position in \(container.section.logString); suppressing alert")
                    acceptValidatedUserMove()
                case .rescueAndRetry:
                    // The item is stuck at the x=-1 sentinel. Rescue it to
                    // the visible section, let macOS settle, then retry the
                    // original move exactly once (no loop). Only if that
                    // retry also fails do we alert, and with a calm message
                    // rather than the raw error, matching the safe-harbor
                    // behavior of restoreBlockedItemsToVisible.
                    Self.diagLog.warning("\(item.logString) is blocked (x=-1); attempting one rescue-and-retry before alerting")
                    _ = await appState.itemManager.rescueBlockedItemToVisible(item)
                    guard isCurrentStabilization(generation) else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    guard isCurrentStabilization(generation) else { return }
                    _ = await appState.itemManager.refreshCacheAfterLayoutEditorMove()
                    guard isCurrentStabilization(generation) else { return }
                    do {
                        try await appState.itemManager.move(
                            item: item,
                            to: destination,
                            skipInputPause: true,
                            options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout)
                        )
                        guard isCurrentStabilization(generation) else { return }
                        appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                        if await stabilizePlacement(
                            of: item,
                            to: destination,
                            expectedSection: container.section,
                            appState: appState,
                            generation: generation
                        ), isCurrentStabilization(generation) {
                            acceptValidatedUserMove()
                        }
                    } catch MenuBarItemManager.EventError.menuTrackingActive {
                        // Same deferral the outer catch handles: the user
                        // opened a menu bar item's menu while the retry was
                        // in flight. Nothing failed, so don't alert.
                        Self.diagLog.info("Rescue-and-retry deferred, a menu bar item menu was open")
                    } catch {
                        guard isCurrentStabilization(generation) else { return }
                        Self.diagLog.error("Rescue-and-retry failed for \(item.logString): \(error)")
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = container.section == .alwaysHidden
                            ? String(localized: "Couldn't move \(item.displayName) to the always-hidden section.")
                            : String(localized: "Couldn't move \(item.displayName) to the hidden section.")
                        alert.informativeText = String(localized: "The item was left in the visible section so it isn't stuck offscreen. Try dragging it again in a moment.")
                        let report = await MoveFailureDiagnosticReport.generate(
                            for: .init(
                                item: item,
                                destination: destination,
                                expectedSection: container.section,
                                error: error,
                                note: "The item was stuck at x=-1; a rescue to the visible section and one retry of the move also failed."
                            ),
                            appState: appState
                        )
                        guard isCurrentStabilization(generation) else { return }
                        report.run(alert, in: window)
                    }
                case .alertControlItemsMissing:
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = String(localized: "Couldn't move the item right now.")
                    alert.informativeText = String(localized: "\(Constants.displayName) can't locate its hidden-section divider right now. It is attempting recovery in the background — try again in a few seconds.")
                    let report = await MoveFailureDiagnosticReport.generate(
                        for: .init(
                            item: item,
                            destination: destination,
                            expectedSection: container.section,
                            error: error,
                            note: "The hidden-section divider could not be located; recovery was started in the background."
                        ),
                        appState: appState
                    )
                    guard isCurrentStabilization(generation) else { return }
                    report.run(alert, in: window)
                case .alertGeneric:
                    // Generated before the alert shows so the "Save Diagnostic
                    // Report…" button has the bar as it was at the failure,
                    // not as it settles while the alert is up.
                    let report = await MoveFailureDiagnosticReport.generate(
                        for: .init(
                            item: item,
                            destination: destination,
                            expectedSection: container.section,
                            error: error
                        ),
                        appState: appState
                    )
                    guard isCurrentStabilization(generation) else { return }
                    report.run(NSAlert(error: error), in: window)
                }
            }
            if !revealedSections.isEmpty {
                // Re-conceal the sections that were revealed for the drag
                // (#988). desiredState was never modified, so
                // updateControlItemState restores whatever presentation the
                // user configured — including the ice-bar overrides that
                // force these sections collapsed — and parks the divider
                // with the newly moved item back offscreen.
                await MainActor.run {
                    for section in revealedSections {
                        section.updateControlItemState(for: nil)
                    }
                }
                // Give the spacer a beat to re-park the divider before the
                // closing cache pass records the settled bar.
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard isCurrentStabilization(generation) else { return }
            let didRefresh = await appState.itemManager.refreshCacheAfterLayoutEditorMove(
                forcePersistSavedOrder: didValidateUserMove
            )
            guard isCurrentStabilization(generation) else { return }
            if !didRefresh {
                Self.diagLog.error(
                    "Thawing Layout editor after post-move cache refresh timed out"
                )
            }
            let didThawCurrentMove = await MainActor.run {
                guard self.isStabilizing,
                      self.stabilizationGeneration == generation
                else {
                    return false
                }
                self.isStabilizing = false
                self.stabilizationTask = nil
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
                self.container.resumeArrangedViewUpdatesWithoutAnimation()
                if sourceContainer !== self.container {
                    sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
                }
                return true
            }

            // Thumbnail capture is allowed to lag behind geometry. The moved
            // view retains its last stable image, so holding both rows frozen
            // while capture retries only makes the editor feel stuck.
            if didThawCurrentMove {
                await MainActor.run {
                    appState.imageCache.performCacheCleanup()
                }
                await appState.imageCache.updateCacheWithoutChecks(
                    sections: MenuBarSection.Name.allCases
                )
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
                    options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout)
                )
                // Same #983 reorder as the primary path: arm the
                // save-gate user-move exemption before stabilize so
                // its cache pass can persist the retry.
                appState.itemManager.recordExternalMoveOperation()
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                _ = await stabilizePlacement(
                    of: item,
                    to: destination,
                    expectedSection: container.section,
                    appState: appState,
                    generation: stabilizationGeneration
                )
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
        Self.itemReachedIntendedPosition(
            item: item,
            destination: destination,
            sectionItems: cache[expectedSection]
        )
    }

    /// Whether `item` sits in `sectionItems` where `destination` asked for
    /// it. Pure, so the identity rule below can be tested.
    static nonisolated func itemReachedIntendedPosition(
        item: MenuBarItem,
        destination: MenuBarItemManager.MoveDestination,
        sectionItems: [MenuBarItem]
    ) -> Bool {
        guard let itemIndex = sectionItems.firstIndex(where: { Self.isSameItem($0, item) }) else {
            return false
        }
        let target = destination.targetItem
        if target.isControlItem {
            return true
        }
        guard let targetIndex = sectionItems.firstIndex(where: { Self.isSameItem($0, target) }) else {
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
            container.canSetArrangedViews = true
            // The source bar is frozen by the dragging session, so an abnormal
            // exit has to thaw it too or it stays at its mid-drag snapshot
            // until an unrelated later drag resets it.
            if sourceContainer !== container {
                sourceContainer?.canSetArrangedViews = true
            }
        }
    }

    /// Whether a cached item is the item that was dragged.
    ///
    /// The dragged item's tag is a snapshot. The cache refreshed after the
    /// move can name the same window differently — a provisional
    /// `com.apple.controlcenter:Item-0` resolves to its app's identifier
    /// once the source process is known — and an exact tag comparison then
    /// misses the item that just landed, which re-drags it (the move engine
    /// finds it already in place and cancels) and, on the failure path,
    /// alerts for a move that worked. The window is what moved: match it
    /// first, and fall back to the tag without its window for a window that
    /// was recreated in between.
    static nonisolated func isSameItem(_ cached: MenuBarItem, _ dragged: MenuBarItem) -> Bool {
        cached.windowID == dragged.windowID || cached.tag.matchesIgnoringWindowID(dragged.tag)
    }

    /// Whether the async continuation still belongs to the move that owns the
    /// frozen editor rows. The recovery watchdog invalidates the generation
    /// and cancels that task before reopening the editor, so a slow old move
    /// cannot resume later and reorder the bar over a newer drag.
    private func isCurrentStabilization(_ generation: Int) -> Bool {
        isStabilizing && stabilizationGeneration == generation && !Task.isCancelled
    }

    @MainActor
    private func resetStabilizingStateIfNeeded(
        generation: Int,
        sourceContainer: LayoutBarContainer? = nil,
        cancelOwningTask: Bool = false
    ) async -> Bool {
        guard isStabilizing, stabilizationGeneration == generation else {
            return false
        }
        if cancelOwningTask {
            stabilizationTask?.cancel()
            stabilizationGeneration &+= 1
        }
        stabilizationTask = nil
        isStabilizing = false
        container.resumeArrangedViewUpdatesWithoutAnimation()
        if sourceContainer !== container {
            sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
        }
        return true
    }

    private func containsNewItemsBadge() -> Bool {
        for arrangedView in container.arrangedViews where arrangedView.isNewItemsBadge {
            return true
        }
        return false
    }

    /// The items a cross-container drop resolves its drag unit against.
    ///
    /// The source bar leads: the members that stayed behind still hold their
    /// pre-drag order there, and that is the order the unit has to keep. The
    /// destination contributes whatever the source does not already hold, so a
    /// member that was already sitting there is still gathered into the block.
    static nonisolated func groupResolutionItems(
        sourceItems: [MenuBarItem],
        destinationItems: [MenuBarItem]
    ) -> [MenuBarItem] {
        let known = Set(sourceItems.map(\.tag))
        return sourceItems + destinationItems.filter { !known.contains($0.tag) }
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
        // This fallback only needs the section's control item. Resolving every
        // item's source process can block on Accessibility for many seconds,
        // leaving both drag rows frozen before move() can start its watchdog.
        let items = await MenuBarItem.getMenuBarItems(
            option: .activeSpace,
            resolveSourcePID: false
        )
        return switch container.section {
        case .visible:
            nil
        case .hidden:
            items.first(matching: .hiddenControlItem).map { .leftOfItem($0) }
        case .alwaysHidden:
            items.first(matching: .alwaysHiddenControlItem).map { .leftOfItem($0) }
        }
    }

    /// Maps a section-divider tag to the name of the section it bounds.
    private static nonisolated func sectionName(forDividerTag tag: MenuBarItemTag) -> MenuBarSection.Name? {
        switch tag {
        case .hiddenControlItem: .hidden
        case .alwaysHiddenControlItem: .alwaysHidden
        default: nil
        }
    }

    /// Whether an editor drag onto a parked divider should reveal the
    /// destination section instead of refusing (#988).
    ///
    /// Only the empty-section deadlock qualifies. With items in the section,
    /// the drop anchors on those items and the existing clamp-and-retry move
    /// path owns the case; a divider whose section is already showing is on
    /// screen and passes the reachability gate; a disabled section is never
    /// revealed; and a non-divider tag (the visible chevron, a regular item)
    /// never routes through this decision.
    static nonisolated func shouldRevealSectionForEditorDrag(
        dividerTag: MenuBarItemTag,
        isSectionConcealed: Bool,
        isEnabled: Bool,
        sectionItemCount: Int
    ) -> Bool {
        guard sectionItemCount == 0 else { return false }
        guard sectionName(forDividerTag: dividerTag) != nil else { return false }
        return isSectionConcealed && isEnabled
    }

    /// Which sections must expand inline so the given section divider can
    /// return onscreen for an editor drag.
    ///
    /// The always-hidden divider sits to the LEFT of everything in the
    /// hidden section. Revealing the always-hidden section alone shrinks
    /// its 10000-point parked spacer back to a normal-width item, but AppKit
    /// re-places that item just left of the hidden section's own content —
    /// which is still parked offscreen behind the hidden divider's
    /// 10000-point spacer while the hidden section is collapsed (#1010).
    /// Both sections must expand together; a hidden destination needs only
    /// itself. Pure over its input.
    static nonisolated func sectionsToRevealForEditorDrag(
        forDividerTag dividerTag: MenuBarItemTag
    ) -> [MenuBarSection.Name] {
        switch dividerTag {
        case .hiddenControlItem: [.hidden]
        case .alwaysHiddenControlItem: [.hidden, .alwaysHidden]
        default: []
        }
    }

    /// Reveals an empty, concealed destination section — together with every
    /// section whose parked content would keep its divider offscreen
    /// (#1010) — so the divider returns onscreen, and returns the revealed
    /// sections together with the divider's fresh live item (#988).
    ///
    /// Returns nil — leaving the bar untouched — when the state does not
    /// qualify per `shouldRevealSectionForEditorDrag`, or the divider did
    /// not come back onscreen; the caller then refuses the
    /// drag exactly as it did before (#923).
    private func revealEmptySectionDivider(
        for divider: MenuBarItem,
        appState: AppState
    ) async -> (sections: [MenuBarSection], divider: MenuBarItem)? {
        guard let sectionName = Self.sectionName(forDividerTag: divider.tag) else {
            return nil
        }
        guard let section = await MainActor.run(body: {
            appState.menuBarManager.section(withName: sectionName)
        }) else {
            return nil
        }
        let (isConcealed, isEnabled) = await MainActor.run {
            // Compare inside the actor: HidingState's Equatable conformance
            // is MainActor-isolated.
            (section.controlItem.state == .hideSection, section.isEnabled)
        }
        let itemCount = appState.itemManager.itemCache[sectionName].count
        guard Self.shouldRevealSectionForEditorDrag(
            dividerTag: divider.tag,
            isSectionConcealed: isConcealed,
            isEnabled: isEnabled,
            sectionItemCount: itemCount
        ) else {
            return nil
        }

        // Resolve the full reveal scope. Sections ahead of the destination
        // are expanded regardless of their own state: the gate above only
        // qualifies the destination, and the leading sections exist purely
        // to bring the destination's divider onscreen (#1010).
        let revealNames = Self.sectionsToRevealForEditorDrag(forDividerTag: divider.tag)
        var sections: [MenuBarSection] = []
        for name in revealNames {
            guard let resolved = await MainActor.run(body: {
                appState.menuBarManager.section(withName: name)
            }) else {
                return nil
            }
            sections.append(resolved)
        }

        Self.diagLog.info(
            "Revealing \(revealNames.map(\.logString).joined(separator: " + ")) to bring the \(sectionName.logString) divider onscreen for the editor drag (#988, #1010)"
        )
        await MainActor.run {
            for revealedSection in sections {
                revealedSection.controlItem.state = .showSection
            }
        }

        // A cancelled drag must not leave the revealed sections showing: the
        // reveal is a Thaw-internal detour, so every cancellation exit
        // restores the sections' persisted state, the same way the timeout
        // path below does.
        if Task.isCancelled {
            await revertRevealedSections(sections)
            return nil
        }

        // The divider slides back beside the visible section once the
        // control item's spacer collapses. Poll for its live window to come
        // back within a display before trusting it as a move anchor; the
        // captured item's windowID survives the state change, but its
        // bounds snapshot does not, so resolve a fresh item.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(50))
            // A cancelled sleep returns immediately, so without this check a
            // cancelled task would burn through the remaining iterations and
            // fall into the revert below, which owns the timeout path — not
            // cancellation. Exit the reveal outright.
            if Task.isCancelled {
                await revertRevealedSections(sections)
                return nil
            }
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            if let fresh = items.first(matching: divider.tag),
               let bounds = Bridging.getWindowBounds(for: fresh.windowID),
               LayoutSolver.isOnScreen(bounds: bounds, screenFrames: screenFrames)
            {
                return (sections, fresh)
            }
        }

        // The divider never came back. Undo the reveal so an empty section
        // is not left showing, and let the caller refuse as before.
        Self.diagLog.warning(
            "The \(sectionName.logString) divider did not come onscreen after revealing; refusing the drag"
        )
        await revertRevealedSections(sections)
        return nil
    }

    /// Returns every revealed section's control item to its persisted state
    /// after a temporary reveal, on the main actor. Shared by the
    /// cancellation and timeout exits so a cancelled or failed reveal cannot
    /// leave a section showing.
    private func revertRevealedSections(_ sections: [MenuBarSection]) async {
        await MainActor.run {
            for section in sections {
                section.updateControlItemState(for: nil)
            }
        }
    }

    /// Ensures the dragged item remains in the intended section and its icon appears.
    private func stabilizePlacement(
        of item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        expectedSection: MenuBarSection.Name,
        appState: AppState,
        generation: Int
    ) async -> Bool {
        guard isCurrentStabilization(generation) else { return false }
        // A dropped refresh is not evidence. Keep the drag projection frozen
        // until this move owns and completes a fast geometry cache pass.
        guard await appState.itemManager.refreshCacheAfterLayoutEditorMove() else {
            return false
        }
        guard isCurrentStabilization(generation) else { return false }

        func isInExpectedSection() -> Bool {
            appState.itemManager.itemCache[expectedSection].contains { Self.isSameItem($0, item) }
        }

        if !isInExpectedSection() {
            // Allow macOS a brief moment to settle, then retry once.
            try? await Task.sleep(for: .milliseconds(120))
            guard isCurrentStabilization(generation) else { return false }
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout)
                )
                guard isCurrentStabilization(generation) else { return false }
                guard await appState.itemManager.refreshCacheAfterLayoutEditorMove() else {
                    return false
                }
                guard isCurrentStabilization(generation) else { return false }
            } catch {
                guard isCurrentStabilization(generation) else { return false }
                Self.diagLog.error("Stabilize move failed: \(error)")
            }
        }

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

/// A calm, localized stand-in for the error a group move reports when its
/// final placement could not be confirmed. ``LayoutBarPaddingView/recoverFromFailedMove``
/// re-verifies from a fresh cache before this ever surfaces, so a user only
/// sees it when the block genuinely did not land.
private struct GroupMoveStabilizationError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Couldn't confirm that the group settled into place.")
    }
}
