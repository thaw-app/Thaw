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

    private var averageColorInfoObservationTask: Task<Void, Never>?

    deinit {
        averageColorInfoObservationTask?.cancel()
        stabilizationTask?.cancel()
    }

    var arrangedViews: [LayoutBarArrangedView] {
        get { container.arrangedViews }
        set { container.arrangedViews = newValue }
    }

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
        // Freeze so a cache refresh mid-move can't overwrite the drag state.
        // updateNewItemsPlacement needs it, or the item lands on the wrong
        // side of the badge.
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

        // Thaw rows the pointer only passed through. The source stays frozen,
        // or a refresh reinserts a duplicate behind the drag image.
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

            // Snap the item back to its original container.
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
            draggingSource.hasContainer = false

            container.resumeArrangedViewUpdatesWithoutAnimation()
            // No move task will thaw the source row, so resume it here.
            // `oldContainerInfo` stays so the session end can restore the view.
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

        // A grouped item drags its whole group as one block.
        var draggedUnit = [MenuBarItem]()
        if case let .item(draggedItem) = draggingSource.kind,
           let appState = container.appState
        {
            // The other members are still in the source bar; resolving against
            // the destination alone would split the group across sections.
            var arrangedItems = items(in: arrangedViews)
            if let sourceContainer, sourceContainer !== container {
                // The source bar leads, with the dragged view back in its
                // slot, or dragging a2 turns a1, a2, a3 into a2, a1, a3.
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

        // When a move starts, its task re-enables updates after stabilizing.
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
    /// The leftmost member takes `destination` and the rest chain to its
    /// right, which also gathers scattered members.
    private func move(
        items: [MenuBarItem],
        startingWith draggedItem: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        sourceContainer: LayoutBarContainer? = nil
    ) {
        guard let appState = container.appState else {
            return
        }
        // Anchor on the leftmost member, not the dragged one, or the group
        // reorders.
        guard items.count > 1 else {
            move(item: draggedItem, to: destination, sourceContainer: sourceContainer)
            return
        }

        Task { [self, appState, sourceContainer] in
            guard !isStabilizing else {
                // Don't leave either container frozen.
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

            // Scales with the unit. A move that never returns would otherwise
            // leave both bars frozen for the session.
            let watchdogTask = Task { [weak self, weak appState, weak sourceContainer] in
                try? await Task.sleep(for: (MenuBarItemManager.layoutWatchdogTimeout * items.count) + .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.resetStabilizingStateIfNeeded(sourceContainer: sourceContainer)
                guard let appState else { return }
                await Self.recoverAfterUnreturnedMove(revealedSections: [], appState: appState)
            }

            var pendingMove: (item: MenuBarItem, destination: MenuBarItemManager.MoveDestination)?
            var failedMemberCount = 0
            do {
                var previous: MenuBarItem?
                for item in items {
                    let target: MenuBarItemManager.MoveDestination =
                        previous.map { .rightOfItem($0) } ?? destination
                    pendingMove = (item, target)
                    do {
                        try await appState.itemManager.move(
                            item: item,
                            to: target,
                            skipInputPause: true,
                            options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout, isUserInitiated: true)
                        )
                    } catch {
                        // Recover this member like a single move, then keep
                        // chaining from the last successful position.
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
                    // Chain to the previous member, not the head's slot, or
                    // the retried member lands ahead of the block.
                    let lastTarget: MenuBarItemManager.MoveDestination =
                        items.dropLast().last.map { .rightOfItem($0) } ?? destination
                    // Unconfirmed placement is a failure. Recovery re-checks
                    // a fresh cache and alerts only if the block didn't land.
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
                // Earlier members may have moved, so recover rather than
                // only log.
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
            // Like a single move: re-anchor the badge and thaw both
            // containers, or the source stays at its mid-drag snapshot.
            if let appState = container.appState {
                await appState.itemManager.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
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

    /// A frozen row accepts only the drag that froze it, so the first move's
    /// thaw can't reconcile a second.
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

        // Strong captures: the move must finish even if the view goes away.
        stabilizationTask = Task { [self, appState] in
            var didValidateUserMove = false
            @MainActor
            func acceptValidatedUserMove() {
                // Only after the move reached its settled placement.
                appState.itemManager.recordExternalMoveOperation()
                didValidateUserMove = true
            }

            // Let macOS settle after e.g. Reset Layout. On cancellation, thaw
            // here since the watchdog hasn't started.
            guard await (try? Task.sleep(for: .milliseconds(150))) != nil else {
                _ = await resetStabilizingStateIfNeeded(
                    generation: generation,
                    sourceContainer: sourceContainer
                )
                return
            }

            // A concealed section parks its divider offscreen, and moving onto
            // it yanks the item offscreen until retries run out (#923). If the
            // section is also empty, refusing deadlocks the user (#988), so
            // reveal it, retarget onto the fresh divider, and re-conceal after.
            // The always-hidden divider also needs the hidden section revealed
            // (#1010).
            var destination = destination
            var revealedSections: [MenuBarSection] = []
            let targetItem = destination.targetItem
            if targetItem.isControlItem {
                let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
                // Frozen bounds predate the drag, so ask the window server.
                // No answer counts as unreachable.
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
                        await appState.itemManager.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
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
                await Self.recoverAfterUnreturnedMove(revealedSections: revealedSections, appState: appState)
            }
            defer { watchdogTask.cancel() }
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout, isUserInitiated: true)
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
                // Deferred so an open menu isn't torn down. Not a failure.
                Self.diagLog.info("Move deferred, a menu bar item menu was open")
            } catch MenuBarItemManager.EventError.moveEngineBusy {
                // Nothing was tried, so nothing failed.
                Self.diagLog.info("Move deferred, another move held the bar")
            } catch {
                guard isCurrentStabilization(generation) else { return }
                Self.diagLog.error("Error moving menu bar item: \(error)")
                // cannotComplete can fire after the item already settled in
                // place. Resample and alert only if it isn't where it was
                // dragged.
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
                    // Stuck at x=-1. Rescue to visible, retry once, and only
                    // then alert with a calm message.
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
                            options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout, isUserInitiated: true)
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
                        // A menu opened during the retry. Nothing failed.
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
                    // Before the alert, so the report shows the bar at the
                    // failure.
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
                // Re-conceal revealed sections. desiredState was never
                // changed, so this restores the user's presentation.
                await MainActor.run {
                    for section in revealedSections {
                        section.updateControlItemState(for: nil)
                    }
                }
                // Let the spacer re-park the divider before the cache pass.
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
                // Before re-enabling updates, so didSet uses the new anchor.
                if let appState = self.container.appState,
                   self.containsNewItemsBadge()
                {
                    appState.itemManager.updateNewItemsPlacement(
                        section: self.container.section,
                        arrangedViews: self.container.arrangedViews
                    )
                }
                // Thaw both destination and source.
                self.container.resumeArrangedViewUpdatesWithoutAnimation()
                if sourceContainer !== self.container {
                    sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
                }
                return true
            }

            // Thumbnails may lag geometry; don't hold rows frozen for them.
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
    /// Shared by the single-item and group paths.
    private func recoverFromFailedMove(
        of item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        error: any Error,
        appState: AppState
    ) async {
        // cannotComplete can fire after the item already settled in place.
        // Resample and alert only if it isn't where the user dragged it.
        try? await Task.sleep(for: .milliseconds(250))
        await appState.itemManager.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
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
            // Stuck at x=-1. Rescue to visible, retry once, and only then
            // alert with a calm message.
            Self.diagLog.warning("\(item.logString) is blocked (x=-1); attempting one rescue-and-retry before alerting")
            _ = await appState.itemManager.rescueBlockedItemToVisible(item)
            try? await Task.sleep(for: .milliseconds(250))
            await appState.itemManager.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout, isUserInitiated: true)
                )
                // Arm the save-gate exemption before stabilizing so the
                // retry persists.
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
                // A menu opened during the retry. Nothing failed.
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

    /// Whether the item is adjacent to the target on the requested side. For
    /// divider targets, being in the section is the best available check.
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

    /// Puts the bar back after a drag's move never returned, once the
    /// watchdog has thawed the rows.
    private static func recoverAfterUnreturnedMove(
        revealedSections: [MenuBarSection],
        appState: AppState
    ) async {
        // The completion path that re-conceals revealed sections may never run.
        if !revealedSections.isEmpty {
            await MainActor.run {
                for section in revealedSections {
                    section.updateControlItemState(for: nil)
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Independent so mutual cancellation can't abort it. Retry until the
        // old owner releases CacheGate; a one-shot refresh would likely be dropped.
        Task { [weak appState] in
            guard let appState else { return }
            guard await appState.itemManager.refreshCacheAfterLayoutEditorMove() else {
                return
            }
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }
    }

    @MainActor
    private func resetStabilizingStateIfNeeded(sourceContainer: LayoutBarContainer? = nil) async {
        if isStabilizing {
            isStabilizing = false
            container.canSetArrangedViews = true
            // Thaw the source too.
            if sourceContainer !== container {
                sourceContainer?.canSetArrangedViews = true
            }
        }
    }

    /// Whether a cached item is the item that was dragged.
    ///
    /// Matches the window first: after the move a provisional
    /// `com.apple.controlcenter:Item-0` tag can resolve to the app's, and a
    /// tag match would alert for a move that worked. Falls back to the tag
    /// for a recreated window.
    static nonisolated func isSameItem(_ cached: MenuBarItem, _ dragged: MenuBarItem) -> Bool {
        cached.windowID == dragged.windowID || cached.tag.matchesIgnoringWindowID(dragged.tag)
    }

    /// So a slow old move can't resume and reorder the bar over a newer drag.
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
    /// The source bar leads, since it holds the pre-drag order. The
    /// destination adds members the source lacks.
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
        Self.nearestDropAnchor(in: arrangedItemSlots, from: index, towardRight: true)
    }

    private func nearestItem(toLeftOf index: Int) -> MenuBarItem? {
        Self.nearestDropAnchor(in: arrangedItemSlots, from: index, towardRight: false)
    }

    /// The item behind each arranged view, `nil` for non-item views, index for index.
    private var arrangedItemSlots: [MenuBarItem?] {
        arrangedViews.map { view in
            if case let .item(item) = view.kind {
                return item
            }
            return nil
        }
    }

    /// The closest item on one side of `index` that a drop may sit beside.
    ///
    /// Slots skipped as anchors leave the drop to the section's divider
    /// fallback when nothing else qualifies.
    static nonisolated func nearestDropAnchor(
        in slots: [MenuBarItem?],
        from index: Int,
        towardRight: Bool
    ) -> MenuBarItem? {
        let candidates = towardRight
            ? Array(slots.indices.filter { $0 > index })
            : Array(slots.indices.filter { $0 < index }.reversed())
        for candidate in candidates {
            if let item = slots[candidate], item.isLayoutDropAnchor {
                return item
            }
        }
        return nil
    }

    private func liveFallbackDestinationForDraggedItem() async -> MenuBarItemManager.MoveDestination? {
        // Skip source resolution: it can block on Accessibility for seconds
        // before move() starts its watchdog.
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
    /// Only the empty, concealed, enabled section with a divider tag
    /// qualifies.
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
    /// The always-hidden divider sits left of the hidden section's content,
    /// which stays parked offscreen while hidden is collapsed, so both must
    /// expand (#1010).
    static nonisolated func sectionsToRevealForEditorDrag(
        forDividerTag dividerTag: MenuBarItemTag
    ) -> [MenuBarSection.Name] {
        switch dividerTag {
        case .hiddenControlItem: [.hidden]
        case .alwaysHiddenControlItem: [.hidden, .alwaysHidden]
        default: []
        }
    }

    /// Reveals an empty concealed section so its divider returns onscreen,
    /// and returns the revealed sections and the divider's fresh item (#988).
    ///
    /// Returns nil, leaving the bar untouched, when the state doesn't qualify
    /// or the divider never returns; the caller then refuses.
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
            // HidingState's Equatable is MainActor-isolated.
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

        // Sections ahead of the destination expand regardless of state.
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

        // Cancellation must not leave revealed sections showing.
        if Task.isCancelled {
            await revertRevealedSections(sections)
            return nil
        }

        // Poll until the divider is back on a display. The windowID survives
        // the state change but its bounds don't, so resolve a fresh item.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(50))
            // A cancelled sleep returns immediately; don't fall into the
            // timeout path.
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

        // Never came back. Undo the reveal and let the caller refuse.
        Self.diagLog.warning(
            "The \(sectionName.logString) divider did not come onscreen after revealing; refusing the drag"
        )
        await revertRevealedSections(sections)
        return nil
    }

    /// Returns revealed sections to their persisted state.
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
        // A dropped refresh is not evidence. Stay frozen until this move
        // completes its own cache pass.
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
                    options: .init(watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout, isUserInitiated: true)
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
        // The real items area right of the notch, plus the 7.5pt inset.
        let notchTrailingOffset = max(0, screen.frame.maxX - notch.maxX - MenuBarSection.notchGap) + 7.5
        // Wide enough for `notch.minX` to `screen.maxX` plus the 7.5pt inset.
        // A wider pane grows the bar to the left of the notch.
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
        // Not .required: overflowing items would be clipped with no
        // scrollbar. .defaultHigh lets the bar grow left past the notch.
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

/// Shown when a group move's placement can't be confirmed. Only surfaces
/// after ``LayoutBarPaddingView/recoverFromFailedMove`` re-verifies.
private struct GroupMoveStabilizationError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Couldn't confirm that the group settled into place.")
    }
}
