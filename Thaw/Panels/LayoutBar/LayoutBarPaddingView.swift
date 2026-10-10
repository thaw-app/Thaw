//
//  LayoutBarPaddingView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel

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

    /// Whether an item may be used as a layout-bar drag source on macOS 27.
    /// The visible Thaw control is a real movable status item; the zero-width
    /// divider controls remain structural and must never be reordered.
    static func acceptsLayoutDrag(of item: MenuBarItem) -> Bool {
        !item.isControlItem || item.tag.matchesVisibleControlItem
    }

    /// Whether anchored Apple system items may be freely reordered in the
    /// layout editor. Without Thaw Bar, hidden anchored items still mirror the
    /// real menu bar's trailing system-control placement.
    static func allowsAnchoredSystemItemReordering(appState: AppState?) -> Bool {
        guard let appState else {
            return false
        }
        if let displayID = appState.itemManager.itemDisplayID {
            return appState.settings.displaySettings.useThawBar(for: displayID)
        }
        return appState.settings.displaySettings.configurationForActiveDisplay().useThawBar
    }

    private static func anchoredSystemItemsTrail(in items: [MenuBarItem]) -> [MenuBarItem] {
        MenuBarBackendProvider.current.anchoredSystemItemsTrail(in: items)
    }

    /// Explains a refused drop rather than letting the item snap back in
    /// silence.
    ///
    /// The common case is an Apple item (often Weather) refused because the
    /// system item hiding switch, which sits below the editor, is off.
    ///
    /// Asking again with the switch flipped separates the two cases: if the
    /// assignment would then be allowed, the message names the setting;
    /// otherwise it says the item stays put.
    private func postAssignmentRefusal(
        for item: MenuBarItem,
        to section: MenuBarSection.Name,
        experimentalSystemItemHiding: Bool
    ) {
        guard let appState = container.appState else { return }

        let wouldBeAllowedWithSystemItemHiding = !experimentalSystemItemHiding
            && MenuBarBackendProvider.current.canAssign(
                item,
                to: section,
                experimentalSystemItemHiding: true
            )

        appState.layoutFeedback.post(
            wouldBeAllowedWithSystemItemHiding
                ? LayoutBarFeedbackCenter.systemItemHidingDisabled(
                    itemName: item.displayName,
                    section: section
                )
                : LayoutBarFeedbackCenter.itemCannotMove(
                    itemName: item.displayName,
                    section: section
                )
        )
    }

    private func layoutWatchdogDuration() -> Duration {
        MenuBarItemManager.layoutWatchdogTimeout
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

        registerForDraggedTypes([.layoutBarItem, .layoutBarGroupHandle])

        configureNotchObservers(appState: appState)
        updateNotchPresentation()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isStabilizing else { return [] }
        if let handle = sender.draggingSource as? LayoutBarGroupHandleView {
            // The whole-group drop mutates order/assignment on drop rather than
            // reordering arranged views mid-drag, so there is nothing to
            // preview, but the drop can still be refused, and discovering that
            // only on release means the drag just springs back with no cue.
            return groupDropOperation(for: handle)
        }
        // Freeze the destination's arrangedViews so that the cache refresh
        // triggered while the system move is in flight cannot overwrite the
        // mid-drag visual state. updateNewItemsPlacement at the end of move()
        // depends on that state to capture the badge's new neighbors; without
        // this guard the dropped item bounces to the wrong side of the badge.
        container.acceptsViewUpdates = false
        return container.handleDrag(sender, phase: .entered)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard !isStabilizing else { return }
        if let sender {
            container.handleDrag(sender, phase: .exited)
        }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isStabilizing else { return [] }
        if let handle = sender.draggingSource as? LayoutBarGroupHandleView {
            return groupDropOperation(for: handle)
        }
        return container.handleDrag(sender, phase: .updated)
    }

    /// Whether a group carried by handle may be dropped into this container's
    /// section, so the cursor shows "no drop" while the drag is still in flight
    /// instead of the user finding out on release.
    ///
    /// A same-section drop is a reorder and never changes membership, so it is
    /// always permitted.
    private func groupDropOperation(for handle: LayoutBarGroupHandleView) -> NSDragOperation {
        guard handle.sourceSection != container.section else { return .move }
        guard let appState = container.appState else { return .move }

        let sourceItems = appState.itemManager.managedItems(for: handle.sourceSection)
        let members = handle.memberIdentifiers.compactMap { identifier in
            sourceItems.first { $0.uniqueIdentifier == identifier }
        }
        guard !members.isEmpty else { return [] }

        let canMove = MenuBarBackendProvider.current.canMoveGroup(
            members: members,
            expectedMemberCount: handle.memberIdentifiers.count,
            to: container.section,
            experimentalSystemItemHiding: appState.settings.advanced.enableExperimentalSystemItemHiding,
            isHidingAvailable: appState.menuBarManager.sectionController.isHidingAvailable
        )
        return canMove ? .move : []
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard !isStabilizing else { return }
        container.handleDrag(sender, phase: .ended)
        restoreArrangedViewsAfterDrag(from: sender)
    }

    /// Re-enables cache-driven layout updates when a drag ends without a
    /// successful drop (cancelled or rejected). performDragOperation (or the
    /// async move() task it spawns) resets the flag on success; without
    /// this, a cancelled drag leaves every container frozen and the bars stop
    /// accepting moves. Also runs after successful drops (draggingEnded
    /// fires unconditionally), so finishDrag must stay idempotent.
    private func restoreArrangedViewsAfterDrag(from draggingInfo: NSDraggingInfo) {
        guard let draggingSource = draggingInfo.draggingSource as? LayoutBarArrangedView else {
            container.acceptsViewUpdates = true
            return
        }
        finishDrag(draggingSource, sourceContainer: draggingSource.oldContainerInfo?.container)
    }

    /// Restores drag-cleanup state on the destination container and, if
    /// different, the source container, and clears the dragged view's stale
    /// container info. Every performDragOperation and move() exit path must
    /// call this; a path that skips a piece leaves a container permanently
    /// frozen.
    ///
    /// source is optional so this can be called from contexts (like the
    /// async move() task) that only know the source container, not the
    /// dragged view itself.
    private func finishDrag(
        _ source: LayoutBarArrangedView?,
        sourceContainer: LayoutBarContainer?
    ) {
        source?.oldContainerInfo = nil
        container.acceptsViewUpdates = true
        if sourceContainer !== container {
            sourceContainer?.acceptsViewUpdates = true
        }
    }

    /// The first hide teaches itself: a drop that carries an item out of the
    /// visible section retires the layout hint and, the first time only,
    /// confirms with the HUD. Called at the moment the drop is accepted, not
    /// when the seat finishes, because the drop is the gesture the user made
    /// and the acknowledgment belongs to it.
    private func noteDropIntoHiddenSection(from sourceSection: MenuBarSection.Name) {
        guard sourceSection != container.section,
              container.section == .hidden || container.section == .alwaysHidden
        else {
            return
        }
        FirstRunHintStore.shared.dismiss(.hideByDrag)
        FirstRunHintStore.shared.markFirstHide()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // A drop is the user arranging in Layout, the one move Manual allows.
        ExplicitLayoutEdit.perform { performLayoutDrop(sender) }
    }

    private func performLayoutDrop(_ sender: NSDraggingInfo) -> Bool {
        if let handle = sender.draggingSource as? LayoutBarGroupHandleView {
            return performGroupHandleDrop(handle, sender: sender)
        }

        guard let draggingSource = sender.draggingSource as? LayoutBarArrangedView else {
            container.acceptsViewUpdates = true
            return false
        }

        let sourceContainer = draggingSource.oldContainerInfo?.container
        var cleanupDeferredToMoveTask = false
        defer {
            if !cleanupDeferredToMoveTask {
                finishDrag(draggingSource, sourceContainer: sourceContainer)
            }
        }

        if case let .item(draggingItem) = draggingSource.kind,
           draggingItem.tag.matchesVisibleControlItem,
           container.section != .visible
        {
            container.appState?.layoutFeedback.post(
                LayoutBarFeedbackCenter.Refusal(
                    title: String(
                        localized: "“\(Constants.displayName)” couldn’t move to \(MenuBarSection.Name.visible.displayString)",
                        comment: "Title shown when the Thaw control icon is dropped outside the Visible section"
                    ),
                    message: String(
                        localized: "The \(Constants.displayName) icon has to stay in Visible.",
                        comment: "Explanation shown when the Thaw control icon is dropped outside the Visible section"
                    )
                )
            )

            // Revert the visual state: remove the item from the container it was dropped into
            // and set hasContainer to false so it snaps back to its original container.
            container.handleDrag(sender, phase: .exited)
            draggingSource.hasContainer = false

            return false
        }

        // Concealment is assignment-backed, but the real divider is still the
        // spatial boundary between sections. Cross-section drops first
        // Command-drag the live item across that divider and only commit the new
        // assignment after AX order verifies the physical transition.
        if draggingSource.isNewItemsBadge {
            container.appState?.itemManager.updateNewItemsPlacement(
                section: container.section,
                arrangedViews: arrangedViews
            )
            sourceContainer?.rebuildViews()
            if sourceContainer !== container {
                container.rebuildViews()
            }
            return true
        }

        guard case let .item(item) = draggingSource.kind,
              Self.acceptsLayoutDrag(of: item)
        else {
            return false
        }

        let controller = container.appState?.menuBarManager.sectionController
        let sourceSection = sourceContainer?.section ?? container.section
        let orderedItems = orderedLayoutItemsForSectionOrder()
        let experimentalSystemItemHiding = container.appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        let physicalOrderExperimentalSystemItemHiding = experimentalSystemItemHiding &&
            Self.allowsAnchoredSystemItemReordering(appState: container.appState)

        guard item.isPhysicallyOrderable(experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding) else {
            guard MenuBarBackendProvider.current.canAssign(
                item,
                to: container.section,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ),
                sourceSection != container.section || container.section != .visible
            else {
                Self.diagLog.warning("Ignoring drag for anchored system item \(item.logString)")
                postAssignmentRefusal(
                    for: item,
                    to: container.section,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                )
                container.handleDrag(sender, phase: .exited)
                draggingSource.hasContainer = false
                return false
            }

            controller?.setSection(container.section, item: item)
            controller?.setSectionOrder(from: orderedItems, for: container.section)
            if let appState = container.appState {
                appState.itemManager.scheduleSectionOrderApply(for: container.section)
                Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
            }
            noteDropIntoHiddenSection(from: sourceSection)
            return true
        }

        if sourceSection != container.section {
            // A physically-orderable item can still be un-hideable when its
            // owner is on the hiding denylist. Reject a drop into a
            // non-visible section and snap it back, rather than committing a
            // hidden assignment the assertion can't honor.
            guard MenuBarBackendProvider.current.canAssign(
                item,
                to: container.section,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) else {
                Self.diagLog.warning("Refusing to assign non-hideable \(item.logString) to \(container.section.logString)")
                postAssignmentRefusal(
                    for: item,
                    to: container.section,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                )
                container.handleDrag(sender, phase: .exited)
                draggingSource.hasContainer = false
                return false
            }

            // Pre-seat, verification, and assignment share one mutation permit;
            // another drop must not re-space the bar during verification.
            //
            // One section per group: an item in a multi-item bundle group moves
            // with its whole group so a bundle never splits across sections.
            // The batch setSection appends every member in group order, so the
            // per-item order commit is skipped then.
            //
            // Seat the weights in the destination band before the assertion
            // flips. MenuBarAgent republishes an item at the weight it already
            // holds, so otherwise the icon reappears on its old side of the
            // divider and the boundary repair drags it back seconds later.
            let groupMembers = crossSectionGroupMembers(
                for: item,
                sourceSection: sourceSection,
                controller: controller
            )
            // The seat can be a real drag (an item leaving the visible bar is
            // dragged behind the divider before it is concealed), so the
            // assignment commit waits for it. The drop is accepted now; a
            // group refusal is surfaced through the feedback centre as before.
            let members = groupMembers ?? [item]
            let targetSection = container.section
            let orderedForCommit = orderedItems
            Task { @MainActor [weak self] in
                guard let self else { return }
                await container.appState?.itemManager.seatItemsForSectionTransition(
                    members,
                    to: targetSection,
                    orderedAs: orderedForCommit
                ) {
                    if let groupMembers {
                        // Dragging one member moves the whole group, so this must be
                        // atomic and must explain itself when it cannot apply.
                        if let refusal = container.appState?.menuBarManager.setSection(
                            targetSection,
                            items: groupMembers,
                            atomically: true
                        ) {
                            if let appState = container.appState {
                                let sourceItems = appState.itemManager.itemCache
                                    .managedItems(for: sourceSection)
                                appState.layoutFeedback.post(
                                    LayoutBarFeedbackCenter.blockedGroupMove(
                                        groupName: groupDisplayName(
                                            for: groupMembers,
                                            in: sourceItems,
                                            appState: appState
                                        ),
                                        section: targetSection,
                                        refusal: refusal
                                    )
                                )
                            }
                            return
                        }
                    } else {
                        controller?.setSection(targetSection, item: item)
                        controller?.setSectionOrder(from: orderedForCommit, for: targetSection)
                        container.appState?.itemManager.scheduleSectionOrderApply(for: targetSection)
                    }
                }
                await container.appState?.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
            noteDropIntoHiddenSection(from: sourceSection)
            return true
        }

        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if sectionIsPhysicallyLive(container.section, controller: controller) {
                if container.section == .visible,
                   let appState = container.appState
                {
                    // Concealed occupants of visible slots (parked
                    // hiding-unsupported apps) are not draggable anchors;
                    // planning against them strands the move.
                    // A hidden Thaw icon has no tile, so it is absent from the
                    // desired order; the planner refuses a live set it cannot order.
                    let desiredIDs = orderedItems.map(\.uniqueIdentifier)
                    let liveItems = appState.itemManager.managedItems(for: .visible)
                        .filter { $0.isOnScreen && !$0.bounds.isEmpty }
                        .filter { !$0.tag.matchesVisibleControlItem || desiredIDs.contains($0.uniqueIdentifier) }
                    let achievableItems = MenuBarLayoutPlannerProvider.current.achievableOrderSegments(
                        items: liveItems,
                        desiredOrder: desiredIDs,
                        experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                    ).flatMap(\.self)

                    let destination = MenuBarLayoutPlannerProvider.current.achievableDestination(
                        items: liveItems,
                        item: item,
                        desiredOrder: desiredIDs,
                        experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                    ) ?? visibleThawControlNeighborDestination(
                        for: item,
                        at: index,
                        experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                    )

                    if let destination {
                        draggingSource.oldContainerInfo = nil
                        cleanupDeferredToMoveTask = true
                        move(
                            item: item,
                            to: destination,
                            sourceContainer: sourceContainer,
                            sectionOrderToCommit: orderedItems,
                            anchorFallbacks: anchorFallbackChain(
                                for: destination,
                                planningItems: liveItems,
                                experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                            )
                        )
                    } else {
                        // The requested order is either already live or would
                        // cross a fixed anchor. Persist only its achievable
                        // projection so reconciliation cannot retry forever.
                        Self.diagLog.info(
                            """
                            Reorder of \(item.logString) has no achievable destination; \
                            desired=\(desiredIDs) live=\(MenuBarLayoutPlannerProvider.current.orderDescription(liveItems))
                            """
                        )
                        controller?.setSectionOrder(from: achievableItems, for: .visible)
                        Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
                    }
                    return true
                }

                let destination: MenuBarItemManager.MoveDestination? =
                    if let target = nearestItem(
                        toRightOf: index,
                        requiringMovable: true,
                        experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                    ) {
                        .leftOfItem(target)
                    } else if let target = nearestItem(
                        toLeftOf: index,
                        requiringMovable: true,
                        experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                    ) {
                        .rightOfItem(target)
                    } else {
                        nil
                    }
                if let destination {
                    draggingSource.oldContainerInfo = nil
                    cleanupDeferredToMoveTask = true
                    move(
                        item: item,
                        to: destination,
                        sourceContainer: sourceContainer,
                        sectionOrderToCommit: orderedItems,
                        anchorFallbacks: anchorFallbackChain(
                            for: destination,
                            planningItems: orderedItems,
                            experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                        )
                    )
                    return true
                }
            }

            // Non-live sections record intent, not a completed move. Visible
            // intent needs an explicit apply; concealed sections wait for reveal.
            controller?.setSection(container.section, item: item)
            controller?.setSectionOrder(from: orderedItems, for: container.section)

            if let appState = container.appState {
                appState.itemManager.scheduleSectionOrderApply(for: container.section)
                Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
            }
            return true
        }

        return false
    }

    /// The drop-time fallback chain for a planned move: the anchor's nearest
    /// orderable neighbours, then the section boundary. Captured here, while
    /// the drop's arrangement is still the truth, because the whole premise of
    /// the chain is that the live scan may no longer be trustworthy by the
    /// time the move runs.
    private func anchorFallbackChain(
        for destination: MenuBarItemManager.MoveDestination,
        planningItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> [MenuBarItemManager.MoveDestination] {
        let anchor = destination.targetItem
        // Left-to-right regardless of the enumeration's native direction: the
        // neighbour entries below name a slot by the edge it is read from.
        let ordered = MenuBarItem.sortByLeadingEdge(planningItems)
        guard let anchorIndex = ordered.firstIndex(where: {
            $0.uniqueIdentifier == anchor.uniqueIdentifier
        }) else {
            return []
        }

        var chain: [MenuBarItemManager.MoveDestination] = []

        // The anchor's left neighbour first: the slot the drop asked for is
        // its right edge.
        if let left = ordered[..<anchorIndex].last(where: {
            Self.isUsableAnchor($0, experimentalSystemItemHiding: experimentalSystemItemHiding)
        }) {
            chain.append(.rightOfItem(left))
        }

        // Then the right neighbour, naming the same slot from the other side.
        if anchorIndex + 1 < ordered.count,
           let right = ordered[(anchorIndex + 1)...].first(where: {
               Self.isUsableAnchor($0, experimentalSystemItemHiding: experimentalSystemItemHiding)
           })
        {
            chain.append(.leftOfItem(right))
        }

        // Last, the leading edge of the section, next to the chevron the
        // layout bar draws. The hidden dividers have no views here.
        if let boundary = ordered.first(where: { $0.tag.matchesVisibleControlItem }) {
            chain.append(.rightOfItem(boundary))
        }

        return chain
    }

    private static func isUsableAnchor(
        _ item: MenuBarItem,
        experimentalSystemItemHiding: Bool
    ) -> Bool {
        !item.isSystemClone &&
            item.bounds.width > 0 &&
            item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding)
    }

    private func move(
        item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        sourceContainer: LayoutBarContainer? = nil,
        sectionOrderToCommit: [MenuBarItem]? = nil,
        anchorFallbacks: [MenuBarItemManager.MoveDestination] = []
    ) {
        guard let appState = container.appState else {
            return
        }
        Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            guard !isStabilizing else {
                await MainActor.run {
                    self.finishDrag(nil, sourceContainer: sourceContainer)
                }
                return
            }
            isStabilizing = true
            await MainActor.run { self.setDimmed(true) }
            // Increased delay to allow macOS to settle after operations like Reset Layout.
            // Prevents transient errors when dragging items immediately after reset.
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                await MainActor.run {
                    self.isStabilizing = false
                    self.setDimmed(false)
                    self.finishDrag(nil, sourceContainer: sourceContainer)
                }
                return
            }

            let watchdogTask = Task { [weak self, weak appState] in
                guard let self else { return }
                try? await Task.sleep(for: self.layoutWatchdogDuration() + .seconds(1))
                guard !Task.isCancelled else { return }
                await self.resetStabilizingStateIfNeeded()
                guard let appState else { return }
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                await appState.imageCache.prewarmConcealedImages(
                    sections: MenuBarSection.Name.allCases,
                    onlyMissingImages: true
                )
                await appState.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
            }
            do {
                let recoveringStrandedVisibleControl = item.tag.matchesVisibleControlItem
                    && (item.bounds.origin.x == MenuBarItemGeometry.transientSentinelX || item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY)
                let attemptMove = { () async throws -> Bool in
                    try await appState.itemManager.move(
                        item: item,
                        to: destination,
                        skipInputPause: true,
                        // A divider-anchored destination is a deliberate section transition;
                        // without the opt-in, move() refuses control item targets on macOS 27.
                        allowSectionBoundaryTarget: destination.targetItem.isControlItem,
                        allowParkedOffMenuBarSource: recoveringStrandedVisibleControl,
                        anchorFallbacks: anchorFallbacks,
                        // A layout-pane drop is the user's direct action: it must preempt
                        // an in-flight background reconcile on the serial gate.
                        isUserInitiated: true,
                        // A drop is the user's explicit request; the drag runs only
                        // after the store write was refused.
                        allowSyntheticDrag: true
                    )
                }

                // The first attempt can fail while the bar is still settling after
                // a reset or a fresh reveal, by throwing or by answering false;
                // retry once either way, with refreshed bounds.
                var didMove = false
                var lastError: Error?
                for attempt in 1 ... 2 {
                    do {
                        didMove = try await attemptMove()
                        lastError = nil
                        if didMove {
                            break
                        }
                    } catch {
                        lastError = error
                    }
                    if attempt < 2 {
                        do {
                            try await Task.sleep(for: .milliseconds(150))
                        } catch {
                            break
                        }
                        await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                    }
                }
                if let lastError {
                    throw lastError
                }
                // false means unfulfilled, not success. Never turn it into
                // a saved full-section request that moves other items instead.
                guard didMove else { throw MenuBarItemManager.EventError.cannotComplete }
                if let sectionOrderToCommit {
                    guard let liveItems = await MenuBarItem.getFreshMenuBarItemsForMove(priorityPIDs: Set([
                        item.ownerPID, item.sourcePID,
                        destination.targetItem.ownerPID, destination.targetItem.sourcePID,
                    ].compactMap(\.self))) else {
                        throw MenuBarItemManager.EventError.cannotComplete
                    }
                    try Task.checkCancellation()
                    guard let completedOrder = MenuBarItemManager.sectionOrderAfterCompletedMove(
                        of: item,
                        proposedOrder: sectionOrderToCommit,
                        liveItems: liveItems
                    ) else { throw MenuBarItemManager.EventError.cannotComplete }
                    appState.menuBarManager.sectionController.setSectionOrder(
                        from: completedOrder,
                        for: container.section
                    )
                }
                await stabilizePlacement(
                    of: item,
                    to: destination,
                    expectedSection: container.section,
                    appState: appState,
                    anchorFallbacks: anchorFallbacks
                )
            } catch {
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
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                // Verification must come from fresh AX order inside
                // MenuBarItemManager. The layout cache may still contain the
                // user's visual drop intent, so do not treat it as proof.
                Self.diagLog.error("Reorder move failed for \(item.logString); visible order was not persisted")
            }
            watchdogTask.cancel()
            await MainActor.run {
                self.isStabilizing = false
                self.setDimmed(false)
            }
            if let appState = container.appState {
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
            await MainActor.run {
                if let appState = self.container.appState,
                   self.container.arrangedViews.contains(where: \.isNewItemsBadge)
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
                self.finishDrag(nil, sourceContainer: sourceContainer)
            }
        }
    }

    @MainActor
    private func resetStabilizingStateIfNeeded() async {
        if isStabilizing {
            isStabilizing = false
            setDimmed(false)
            container.acceptsViewUpdates = true
        }
    }

    private func setDimmed(_ visible: Bool) {
        container.alphaValue = visible ? 0.6 : 1.0
    }

    /// Whether items in the section currently have live AX elements to reorder.
    private func sectionIsPhysicallyLive(
        _ section: MenuBarSection.Name,
        controller: (any MenuBarSectionControlling)?
    ) -> Bool {
        switch section {
        case .visible:
            return true
        case .hidden:
            guard let revealed = controller?.revealedSection else {
                return false
            }
            return revealed == .hidden || revealed == .alwaysHidden
        case .alwaysHidden:
            return controller?.revealedSection == .alwaysHidden
        }
    }

    /// Builds the ordered item list from the layout bar's current visual
    /// arrangement. The visible Thaw control (Thaw.ControlItem.Visible) is
    /// included so a layout-bar drag can commit the icon's new slot; hidden
    /// section dividers stay structural and are omitted.
    /// A collapsed group is one arranged view standing in for several items, so
    /// it must be expanded back into its members here. Matching only .item
    /// would drop every member of a collapsed group out of the persisted section
    /// order, the items would silently vanish from the saved layout while still
    /// being in the menu bar.
    static func layoutItemsForPersistence(from arrangedViews: [LayoutBarArrangedView]) -> [MenuBarItem] {
        persistableItems(from: arrangedViews.map(\.kind))
    }

    /// The pure kind-list form, so the expansion rule can be tested without a
    /// view tree, LayoutBarArrangedView.kind is get-only and the concrete
    /// views need an AppState.
    static func persistableItems(from kinds: [LayoutBarArrangedView.Kind]) -> [MenuBarItem] {
        kinds.flatMap { kind -> [MenuBarItem] in
            switch kind {
            case let .item(item):
                if item.isControlItem {
                    return item.tag.matchesVisibleControlItem ? [item] : []
                }
                return [item]
            case let .collapsedGroup(members):
                return members.filter { !$0.isControlItem }
            case .opaqueSlot, .newItemsBadge:
                return []
            }
        }
    }

    private func orderedLayoutItems() -> [MenuBarItem] {
        Self.layoutItemsForPersistence(from: arrangedViews)
    }

    /// The members of the dragged item's group in its source section, or nil
    /// when the item belongs to no group.
    ///
    /// The whole group travels together on a cross-section drop, honoring "one
    /// section per group", even if its members are not currently adjacent in
    /// the source section. Resolution goes through the shared resolver, so a
    /// user-authored group spanning several bundles moves as one unit exactly
    /// like an automatic same-bundle cluster does.
    private func crossSectionGroupMembers(
        for item: MenuBarItem,
        sourceSection: MenuBarSection.Name,
        controller: (any MenuBarSectionControlling)?
    ) -> [MenuBarItem]? {
        guard let appState = container.appState else {
            return nil
        }
        let managed = appState.itemManager.managedItems(for: sourceSection)
        // Display order, not recorded order: the indices below are read back
        // against the rows the user is dragging, so a group has to be resolved
        // over the same sequence the layout editor is showing.
        let sourceItems = controller?.displayOrdered(managed, in: sourceSection) ?? managed
        guard let group = appState.itemGroupManager.resolvedGroup(containing: item, in: sourceItems),
              group.count >= 2
        else {
            return nil
        }
        return group.memberIndices.compactMap { sourceItems.indices.contains($0) ? sourceItems[$0] : nil }
    }

    // MARK: Group handle drops

    /// Commits a whole-group drag started from a cluster's drag handle.
    ///
    /// Within the same section it reorders the group as one contiguous block
    /// (via persisted order + reconciliation, the same path a single reorder
    /// uses). Across sections it relocates every member, honoring "one section
    /// per group". Either way the group stays intact, individual items never
    /// fall out of a handle drag.
    private func performGroupHandleDrop(_ handle: LayoutBarGroupHandleView, sender: NSDraggingInfo) -> Bool {
        if handle.sourceSection == container.section {
            let dropX = container.convert(sender.draggingLocation, from: nil).x
            // The reorder path restores view updates itself (immediately for a
            // concealed section, or after its async move task for a live one).
            return performGroupHandleReorder(handle, dropX: dropX)
        }
        defer { restoreAfterGroupDrop(handle) }
        return performGroupHandleCrossSection(handle)
    }

    /// Re-enables view updates on both the drop and source containers after a
    /// synchronous (no async move) group drop.
    private func restoreAfterGroupDrop(_ handle: LayoutBarGroupHandleView) {
        container.acceptsViewUpdates = true
        handle.sourceContainer?.acceptsViewUpdates = true
    }

    /// Reorders a group as one contiguous block within its current section,
    /// gathering its members even if they start scattered.
    ///
    /// In a concealed section the items are snapshots, so persisting the new
    /// order is enough. In a physically-live section (Visible, or a revealed
    /// hidden section) persistence alone does not move anything, the block is
    /// realized with real AX moves, one member at a time, then the final order
    /// is committed.
    private func performGroupHandleReorder(_ handle: LayoutBarGroupHandleView, dropX: CGFloat) -> Bool {
        guard let appState = container.appState else {
            restoreAfterGroupDrop(handle)
            return false
        }
        let controller = appState.menuBarManager.sectionController
        let orderedItems = orderedLayoutItems()
        let identifiers = orderedItems.map(\.uniqueIdentifier)

        // Members in their current left-to-right order, the sequence the
        // gathered block must end in. Membership is by identifier, so a bundle
        // whose items are not adjacent still contributes every member.
        let memberIDSet = Set(handle.memberIdentifiers)
        let members = orderedItems.filter { memberIDSet.contains($0.uniqueIdentifier) }
        guard members.count == handle.memberIdentifiers.count, members.count >= 2 else {
            // Some members are no longer present in this section (e.g. one was
            // pulled into another section); nothing to move as one block here.
            restoreAfterGroupDrop(handle)
            return false
        }

        // Drop cursor position in the original array's index space.
        let destination = groupHandleDestinationIndex(in: identifiers, dropX: dropX)

        // Gather: remove every member, then insert the block so it begins at the
        // drop cursor. Members sitting before the cursor shift the insertion left.
        var reordered = orderedItems.filter { !memberIDSet.contains($0.uniqueIdentifier) }
        let membersBefore = orderedItems.prefix(min(destination, orderedItems.count))
            .filter { memberIDSet.contains($0.uniqueIdentifier) }
            .count
        // The clamp is not a rendering detail to absorb quietly: firing at all
        // means the drag state disagrees with the section it dropped into, and
        // that disagreement is the defect worth logging.
        let rawInsertionIndex = destination - membersBefore
        let insertionIndex = rawInsertionIndex.clamped(to: 0 ... reordered.count)
        if rawInsertionIndex != insertionIndex {
            Self.diagLog.warning(
                "Group drop insertion index \(rawInsertionIndex) outside this section's 0...\(reordered.count); clamped to \(insertionIndex)"
            )
        }
        reordered.insert(contentsOf: members, at: insertionIndex)

        // Dropped where the block already sits, nothing to do.
        guard reordered.map(\.uniqueIdentifier) != identifiers else {
            restoreAfterGroupDrop(handle)
            return true
        }

        if sectionIsPhysicallyLive(container.section, controller: controller) {
            let firstIndex = insertionIndex
            let afterBlockIndex = firstIndex + members.count
            moveGroupSequentially(
                members: members,
                rightAnchor: afterBlockIndex < reordered.count ? reordered[afterBlockIndex] : nil,
                leftAnchor: firstIndex > 0 ? reordered[firstIndex - 1] : nil,
                sectionOrderToCommit: reordered,
                sourceContainer: handle.sourceContainer
            )
            // The async task calls finishDrag, which restores view updates.
            return true
        }

        controller.setSectionOrder(from: reordered, for: container.section)
        appState.itemManager.scheduleSectionOrderApply(for: container.section)
        Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
        restoreAfterGroupDrop(handle)
        return true
    }

    /// Realizes a block move in a physically-live section with sequential AX
    /// moves.
    ///
    /// The members are anchored to a fixed external neighbor, the item that
    /// borders the block's destination and is not itself a group member, never
    /// to a just-moved member (whose cached AX element is momentarily stale, the
    /// cause of members landing apart). Inserting each member adjacent to that
    /// stable anchor in the right order keeps the block contiguous: against a
    /// right neighbor, members go in front-to-back, each to its left; against
    /// a left neighbor, back-to-front, each to its right.
    private func moveGroupSequentially(
        members: [MenuBarItem],
        rightAnchor: MenuBarItem?,
        leftAnchor: MenuBarItem?,
        sectionOrderToCommit: [MenuBarItem],
        sourceContainer: LayoutBarContainer?
    ) {
        guard let appState = container.appState, !members.isEmpty else {
            finishDrag(nil, sourceContainer: sourceContainer)
            return
        }
        let section = container.section
        // Members in left-to-right order, the sequence the block must end in.
        let memberOrder = members.map(\.tag)

        // Insert every member against a stable external anchor (never a
        // just-moved member). Front-to-back to the anchor's left, or, when the
        // block goes to the very end, back-to-front to a left anchor's right.
        let anchorTag: MenuBarItemTag
        let orderedMemberTags: [MenuBarItemTag]
        let insertToLeftOfAnchor: Bool
        if let rightAnchor {
            anchorTag = rightAnchor.tag
            orderedMemberTags = memberOrder
            insertToLeftOfAnchor = true
        } else if let leftAnchor {
            anchorTag = leftAnchor.tag
            orderedMemberTags = memberOrder.reversed()
            insertToLeftOfAnchor = false
        } else {
            finishDrag(nil, sourceContainer: sourceContainer)
            return
        }

        Task { @MainActor [weak self, weak appState] in
            guard let self, let appState else { return }
            guard !self.isStabilizing else {
                self.finishDrag(nil, sourceContainer: sourceContainer)
                return
            }
            self.isStabilizing = true
            self.setDimmed(true)
            try? await Task.sleep(for: .milliseconds(150))

            let liveOrder: @MainActor () -> [MenuBarItem] = {
                appState.itemManager.managedItems(for: section)
            }
            let liveItem: @MainActor (MenuBarItemTag) -> MenuBarItem? = { tag in
                liveOrder().first { $0.tag == tag }
            }
            // Whether the members already sit contiguously, in order, immediately
            // beside the anchor, i.e., the block move is complete.
            let isPlaced: @MainActor () -> Bool = {
                let live = liveOrder()
                guard let anchorIndex = live.firstIndex(where: { $0.tag == anchorTag }) else {
                    return false
                }
                let rawStart = insertToLeftOfAnchor ? anchorIndex - memberOrder.count : anchorIndex + 1
                // Execution-time clamp: the drop's insertion index described a
                // section that may have changed shape mid-gesture, so the slot
                // it implies is clamped to the live section's bounds, and the
                // clamp logs when it fires. Clamping, rather than reporting
                // "not placed", also lets a block that genuinely converged at
                // a section edge confirm, instead of driving moves forever.
                let start = rawStart.clamped(to: 0 ... max(live.count - memberOrder.count, 0))
                if start != rawStart {
                    Self.diagLog.warning(
                        "Group block slot \(rawStart) outside the live section's 0...\(max(live.count - memberOrder.count, 0)); clamped to \(start)"
                    )
                }
                return memberOrder.indices.allSatisfy {
                    live.indices.contains(start + $0) && live[start + $0].tag == memberOrder[$0]
                }
            }

            // Repeat the placement pass until the whole block is contiguous; a
            // single AX move can transiently fail or lag the cache, which would
            // otherwise leave one member stranded outside the group.
            let maxPasses = 4
            var pass = 0
            while pass < maxPasses, !isPlaced() {
                pass += 1
                for tag in orderedMemberTags {
                    // Re-fetch both the member and the (stable) anchor so each
                    // move targets a current AX element.
                    guard let member = liveItem(tag), let anchor = liveItem(anchorTag) else {
                        continue
                    }
                    let destination: MenuBarItemManager.MoveDestination =
                        insertToLeftOfAnchor ? .leftOfItem(anchor) : .rightOfItem(anchor)
                    do {
                        _ = try await appState.itemManager.move(
                            item: member,
                            to: destination,
                            skipInputPause: true,
                            // User-driven group reorder: preempt background reconcile.
                            isUserInitiated: true,
                            allowSyntheticDrag: false
                        )
                    } catch {
                        Self.diagLog.error("Group reorder move failed for \(member.logString): \(error)")
                    }
                    await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                    // Let the AX order settle before the next member reads it.
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
            if !isPlaced() {
                Self.diagLog.warning("Group reorder did not fully converge after \(maxPasses) passes")
                // The persisted order below is still canonical; what failed is
                // the physical AX placement. Say so rather than leaving a
                // half-regrouped cluster with no explanation.
                let sourceItems = appState.itemManager.managedItems(for: section)
                appState.layoutFeedback.post(
                    LayoutBarFeedbackCenter.groupRegatherIncomplete(
                        groupName: groupDisplayName(for: members, in: sourceItems, appState: appState),
                        section: section
                    )
                )
            }

            appState.menuBarManager.sectionController.setSectionOrder(
                from: sectionOrderToCommit,
                for: section
            )
            if !isPlaced() {
                // An explicitly requested group order still needs convergence.
                appState.itemManager.scheduleSectionOrderApply(for: section)
            }
            await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            self.isStabilizing = false
            self.setDimmed(false)
            self.finishDrag(nil, sourceContainer: sourceContainer)
        }
    }

    /// Relocates every member of a group into the drop section.
    private func performGroupHandleCrossSection(_ handle: LayoutBarGroupHandleView) -> Bool {
        guard let appState = container.appState else {
            return false
        }
        let sourceItems = appState.itemManager.managedItems(for: handle.sourceSection)
        let members = handle.memberIdentifiers.compactMap { identifier in
            sourceItems.first { $0.uniqueIdentifier == identifier }
        }
        guard !members.isEmpty else {
            return false
        }

        // Seat the members in the destination band first; see
        // MenuBarItemManager.seatItemsForSectionTransition(_:to:commit:). The
        // seat may be a real drag, so the commit waits for it and the drop is
        // accepted now.
        let targetSection = container.section
        Task { @MainActor [weak self] in
            guard let self else { return }
            await appState.itemManager.seatItemsForSectionTransition(members, to: targetSection) {
                // Atomic: a group is indivisible, so a member that cannot move refuses
                // the whole batch rather than being quietly skipped. The refusal is
                // surfaced instead of only logged, otherwise the drag just snaps back
                // and reads as the app ignoring it.
                if let refusal = appState.menuBarManager.setSection(
                    targetSection,
                    items: members,
                    atomically: true
                ) {
                    appState.layoutFeedback.post(
                        LayoutBarFeedbackCenter.blockedGroupMove(
                            groupName: groupDisplayName(for: members, in: sourceItems, appState: appState),
                            section: targetSection,
                            refusal: refusal
                        )
                    )
                    return
                }
            }

            await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
        noteDropIntoHiddenSection(from: handle.sourceSection)
        return true
    }

    /// A user-facing name for the group these members belong to, for use in
    /// refusal copy.
    private func groupDisplayName(
        for members: [MenuBarItem],
        in sourceItems: [MenuBarItem],
        appState: AppState
    ) -> String {
        guard let first = members.first,
              let group = appState.itemGroupManager.resolvedGroup(containing: first, in: sourceItems)
        else {
            return members.first?.displayName ?? ""
        }
        return appState.itemGroupManager.displayName(for: group, in: sourceItems)
    }

    /// The insertion index (in identifiers space) for a group dropped at
    /// dropX, resolved from the nearest arranged item view.
    private func groupHandleDestinationIndex(in identifiers: [String], dropX: CGFloat) -> Int {
        guard let nearest = container.closestView(toX: dropX, excludingBadge: true),
              case let .item(item) = nearest.kind,
              let index = identifiers.firstIndex(of: item.uniqueIdentifier)
        else {
            return identifiers.count
        }
        return dropX > nearest.frame.midX ? index + 1 : index
    }

    private func orderedLayoutItemsForSectionOrder() -> [MenuBarItem] {
        let orderedItems = orderedLayoutItems()
        guard container.section != .visible,
              !Self.allowsAnchoredSystemItemReordering(appState: container.appState)
        else {
            return orderedItems
        }
        return Self.anchoredSystemItemsTrail(in: orderedItems)
    }

    /// Fallback move target for the visible Thaw control when the planner
    /// cannot derive a destination from persisted order alone.
    private func visibleThawControlNeighborDestination(
        for item: MenuBarItem,
        at index: Int,
        experimentalSystemItemHiding: Bool
    ) -> MenuBarItemManager.MoveDestination? {
        guard item.tag.matchesVisibleControlItem else { return nil }
        if let target = nearestItem(
            toRightOf: index,
            requiringMovable: true,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) {
            return .leftOfItem(target)
        }
        if let target = nearestItem(
            toLeftOf: index,
            requiringMovable: true,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) {
            return .rightOfItem(target)
        }
        return nil
    }

    private func nearestItem(
        toRightOf index: Int,
        requiringMovable: Bool = false,
        experimentalSystemItemHiding: Bool = false
    ) -> MenuBarItem? {
        guard arrangedViews.indices.contains(index + 1) else {
            return nil
        }
        for candidateIndex in (index + 1) ..< arrangedViews.count {
            if case let .item(item) = arrangedViews[candidateIndex].kind {
                if requiringMovable,
                   item.isControlItem ||
                   !item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding)
                {
                    continue
                }
                return item
            }
        }
        return nil
    }

    private func nearestItem(
        toLeftOf index: Int,
        requiringMovable: Bool = false,
        experimentalSystemItemHiding: Bool = false
    ) -> MenuBarItem? {
        guard arrangedViews.indices.contains(index - 1) else {
            return nil
        }
        for candidateIndex in stride(from: index - 1, through: 0, by: -1) {
            if case let .item(item) = arrangedViews[candidateIndex].kind {
                if requiringMovable,
                   item.isControlItem ||
                   !item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding)
                {
                    continue
                }
                return item
            }
        }
        return nil
    }

    /// Ensures the dragged item remains in the intended section and its icon appears.
    private func stabilizePlacement(
        of item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        expectedSection: MenuBarSection.Name,
        appState: AppState,
        anchorFallbacks: [MenuBarItemManager.MoveDestination] = []
    ) async {
        await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)

        func isInExpectedSection() -> Bool {
            appState.itemManager.itemCache[expectedSection].contains { $0.tag == item.tag }
        }

        if !isInExpectedSection() {
            // Allow macOS a brief moment to settle, then retry once.
            try? await Task.sleep(for: .milliseconds(120))
            do {
                let recoveringStrandedVisibleControl = item.tag.matchesVisibleControlItem
                    && (item.bounds.origin.x == MenuBarItemGeometry.transientSentinelX || item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY)
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    // A divider-anchored destination is a deliberate section
                    // transition; without the opt-in, move() refuses control
                    // item targets on macOS 27.
                    allowSectionBoundaryTarget: destination.targetItem.isControlItem,
                    allowParkedOffMenuBarSource: recoveringStrandedVisibleControl,
                    anchorFallbacks: anchorFallbacks,
                    // User-driven placement recovery: preempt background reconcile.
                    isUserInitiated: true,
                    allowSyntheticDrag: false
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
        // No concealed-glyph prewarm here: the dropped item's glyph is already
        // cached, and gap-filling the concealed sections after every drop
        // flashes the whole hidden set on the live bar. The pane's gap-fill
        // runs when it opens and from the stabilize watchdog instead.
        await appState.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
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

        // MenuBarManager is @Observable; the sequence already yields on the
        // main actor and skips runs of equal values by hand.
        // The tint is part of the background the indicator is read against,
        // as it is for the items beside it.
        let colorTask = Task { @MainActor [weak self, menuBarManager = appState.menuBarManager, appearanceManager = appState.appearanceManager] in
            let changes = Observations {
                MenuBarStyleTint.background(
                    menuBarManager.averageColorInfo,
                    tintedBy: appearanceManager.configuration.current
                )
            }
            var previous: MenuBarAverageColorInfo??
            for await colorInfo in changes {
                guard let self else { return }
                guard colorInfo != previous else { continue }
                previous = colorInfo
                notchView?.averageColorInfo = colorInfo
            }
        }
        AnyCancellable { colorTask.cancel() }
            .store(in: &notchObservers)
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
        // trailing edge, equals the real-world items area (everything
        // right of notch.maxX + notchGap in the menu bar) plus the 7.5pt
        // cosmetic inset that sits between items and the rounded edge.
        let notchTrailingOffset = max(0, screen.frame.maxX - notch.maxX - MenuBarSection.notchGap) + 7.5
        // Bar must always be wide enough to represent the real-world span
        // from notch.minX to screen.maxX, with no inset on the left
        // (the notch itself sits flush) and 7.5pt cosmetic inset on the
        // right. When the Settings pane is wider, the bar grows past this
        // and the empty area is shown to the LEFT of the notch.
        let barMinWidth = max(0, screen.frame.maxX - notch.minX) + 7.5
        let colorInfo = container.appState.flatMap { MenuBarStyleTint.currentBackground(appState: $0) }

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
        // .defaultHigh, not .required: a required pin at notchView.trailing
        // fixes the container's width, so overflowing items are clipped and
        // no horizontal scroller appears. At .defaultHigh the notch stays the
        // preferred boundary but AutoLayout can break it, the documentView
        // grows past the visible area and the scroller shows. The container
        // is z-above notchView, so items over the notch indicator stay
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
