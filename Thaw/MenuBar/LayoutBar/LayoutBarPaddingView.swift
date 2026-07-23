//
//  LayoutBarPaddingView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import PlatformRuntimeKit

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
        if let displayID = appState.itemManager.itemCache.displayID {
            return appState.settings.displaySettings.useIceBar(for: displayID)
        }
        return appState.settings.displaySettings.configurationForActiveDisplay().useIceBar
    }

    private static func anchoredSystemItemsTrail(in items: [MenuBarItem]) -> [MenuBarItem] {
        MenuBarSectionController.anchoredSystemItemsTrail(in: items)
    }

    private func layoutWatchdogDuration() -> Duration? {
        switch MenuBarItemManager.layoutWatchdogTimeout {
        case let .seconds(s):
            return .seconds(s)
        case let .milliseconds(ms):
            return .milliseconds(ms)
        default:
            return nil
        }
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
        if sender.draggingSource is LayoutBarGroupHandleView {
            // The whole-group drop mutates order/assignment on drop rather than
            // reordering arranged views mid-drag, so just accept the move.
            return .move
        }
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
        if sender.draggingSource is LayoutBarGroupHandleView {
            return .move
        }
        return container.updateArrangedViewsForDrag(with: sender, phase: .updated)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard !isStabilizing else { return }
        container.updateArrangedViewsForDrag(with: sender, phase: .ended)
        restoreArrangedViewsAfterDrag(from: sender)
    }

    /// Re-enables cache-driven layout updates when a drag ends without a
    /// successful drop (cancelled or rejected). `performDragOperation` (or the
    /// async `move()` task it spawns) resets the flag on success; without
    /// this, a cancelled drag leaves every container frozen and the bars stop
    /// accepting moves. Also runs after successful drops (`draggingEnded`
    /// fires unconditionally), so `finishDrag` must stay idempotent.
    private func restoreArrangedViewsAfterDrag(from draggingInfo: NSDraggingInfo) {
        guard let draggingSource = draggingInfo.draggingSource as? LayoutBarArrangedView else {
            container.canSetArrangedViews = true
            return
        }
        finishDrag(draggingSource, sourceContainer: draggingSource.oldContainerInfo?.container)
    }

    /// Restores drag-cleanup state on the destination container and, if
    /// different, the source container, and clears the dragged view's stale
    /// container info. Centralizes the cleanup triple every
    /// `performDragOperation` exit path (and `move()`'s own exit paths) used
    /// to hand-write, which is what let past return paths forget a piece and
    /// leave a container permanently frozen.
    ///
    /// `source` is optional so this can be called from contexts (like the
    /// async `move()` task) that only know the source *container*, not the
    /// dragged view itself.
    private func finishDrag(
        _ source: LayoutBarArrangedView?,
        sourceContainer: LayoutBarContainer?
    ) {
        source?.oldContainerInfo = nil
        container.canSetArrangedViews = true
        if sourceContainer !== container {
            sourceContainer?.canSetArrangedViews = true
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let handle = sender.draggingSource as? LayoutBarGroupHandleView {
            return performGroupHandleDrop(handle, sender: sender)
        }

        guard let draggingSource = sender.draggingSource as? LayoutBarArrangedView else {
            container.canSetArrangedViews = true
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

            return false
        }

        // macOS 27 uses assignment-backed concealment, but the real divider is
        // still the spatial boundary between sections. Cross-section drops first
        // Command-drag the live item across that divider and only commit the new
        // assignment after AX order verifies the physical transition.
        if !MenuBarBackendProvider.current.supportsLegacySectionHiding {
            if draggingSource.isNewItemsBadge {
                container.appState?.itemManager.updateNewItemsPlacement(
                    section: container.section,
                    arrangedViews: arrangedViews
                )
                if let appState = container.appState {
                    sourceContainer?.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: sourceContainer?.section ?? container.section))
                    if sourceContainer !== container {
                        container.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: container.section))
                    }
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
                guard MenuBarSectionController.canAssign(
                    item,
                    to: container.section,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                ),
                    sourceSection != container.section || container.section != .visible
                else {
                    Self.diagLog.warning("Ignoring drag for anchored system item \(item.logString)")
                    container.updateArrangedViewsForDrag(with: sender, phase: .exited)
                    draggingSource.hasContainer = false
                    return false
                }

                controller?.setSection(container.section, item: item)
                controller?.setSectionOrder(from: orderedItems, for: container.section)
                if let appState = container.appState {
                    Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
                }
                return true
            }

            if sourceSection != container.section {
                // A physically-orderable item can still be un-hideable when its
                // owner is on the hiding denylist. Reject a drop into a
                // non-visible section and snap it back, rather than committing a
                // hidden assignment the assertion can't honor.
                guard MenuBarSectionController.canAssign(
                    item,
                    to: container.section,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                ) else {
                    Self.diagLog.warning("Refusing to assign non-hideable \(item.logString) to \(container.section.logString)")
                    container.updateArrangedViewsForDrag(with: sender, phase: .exited)
                    draggingSource.hasContainer = false
                    return false
                }

                // macOS 27: a section change is driven by the assertion
                // (assignment), NOT a physical divider-crossing drag. The synthetic
                // cross-divider move is unreliable — it exhausts its attempts and
                // the item snaps back, freezing the editor while it retries
                // (EventError.cannotComplete). The assertion conceals/reveals
                // immediately from the new assignment, and physical order within a
                // section is reconciled separately on reveal, so just commit the
                // new section + order here.
                //
                // "One section per group": when the dragged item belongs to a
                // multi-item bundle group in its source section, relocate the whole
                // group so a bundle's items never split across sections. The batch
                // `setSection` appends every member to the target section's order in
                // group order, so the per-item order commit is skipped in that case.
                if let groupMembers = crossSectionGroupMembers(
                    for: item,
                    sourceSection: sourceSection,
                    controller: controller
                ) {
                    controller?.setSection(container.section, items: groupMembers)
                } else {
                    controller?.setSection(container.section, item: item)
                    controller?.setSectionOrder(from: orderedItems, for: container.section)
                }
                if let appState = container.appState {
                    Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
                }
                return true
            }

            if let index = arrangedViews.firstIndex(of: draggingSource) {
                if macOS27SectionIsPhysicallyLive(container.section, controller: controller) {
                    if container.section == .visible,
                       let appState = container.appState
                    {
                        let liveItems = appState.itemManager.itemCache.managedItems(for: .visible)
                        let desiredIDs = orderedItems.map(\.uniqueIdentifier)
                        let achievableItems = RuntimeLayoutCoordinator.achievableOrderSegments(
                            items: liveItems,
                            desiredOrder: desiredIDs,
                            experimentalSystemItemHiding: physicalOrderExperimentalSystemItemHiding
                        ).flatMap(\.self)

                        let destination = RuntimeLayoutCoordinator.achievableDestination(
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
                                sectionOrderToCommit: orderedItems
                            )
                        } else {
                            // The requested order is either already live or would
                            // cross a fixed anchor. Persist only its achievable
                            // projection so reconciliation cannot retry forever.
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
                            sectionOrderToCommit: orderedItems
                        )
                        return true
                    }
                }

                // Concealed sections only persist layout-bar order; the items
                // are snapshots with no live AX element to Command-drag.
                controller?.setSection(container.section, item: item)
                controller?.setSectionOrder(from: orderedItems, for: container.section)

                if let appState = container.appState {
                    Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
                }
                return true
            }

            return false
        }

        if draggingSource.isNewItemsBadge {
            container.appState?.itemManager.updateNewItemsPlacement(
                section: container.section,
                arrangedViews: arrangedViews
            )
            if let appState = container.appState {
                sourceContainer?.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: sourceContainer?.section ?? container.section))
                if sourceContainer !== container {
                    container.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: container.section))
                }
            }
            return true
        }

        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if arrangedViews.count == 1 {
                cleanupDeferredToMoveTask = true
                Task {
                    guard case let .item(item) = draggingSource.kind else {
                        self.finishDrag(draggingSource, sourceContainer: sourceContainer)
                        return
                    }
                    if let destination = await self.liveFallbackDestinationForDraggedItem() {
                        draggingSource.oldContainerInfo = nil
                        self.move(item: item, to: destination, sourceContainer: sourceContainer)
                    } else {
                        Self.diagLog.error("No target item for layout bar drag")
                        self.finishDrag(draggingSource, sourceContainer: sourceContainer)
                    }
                }
            } else if case let .item(item) = draggingSource.kind {
                if let targetItem = nearestItem(toRightOf: index) {
                    cleanupDeferredToMoveTask = true
                    draggingSource.oldContainerInfo = nil
                    move(item: item, to: .leftOfItem(targetItem), sourceContainer: sourceContainer)
                } else if let targetItem = nearestItem(toLeftOf: index) {
                    cleanupDeferredToMoveTask = true
                    draggingSource.oldContainerInfo = nil
                    move(item: item, to: .rightOfItem(targetItem), sourceContainer: sourceContainer)
                } else if !arrangedViews.isEmpty {
                    cleanupDeferredToMoveTask = true
                    Task {
                        if let destination = await self.liveFallbackDestinationForDraggedItem() {
                            draggingSource.oldContainerInfo = nil
                            self.move(item: item, to: destination, sourceContainer: sourceContainer)
                        } else {
                            Self.diagLog.error("No target item for layout bar drag")
                            self.finishDrag(draggingSource, sourceContainer: sourceContainer)
                        }
                    }
                }
            }
        }

        // If a move was initiated above, `cleanupDeferredToMoveTask` is set and
        // the top-level `defer` skips its cleanup — the move() Task re-enables
        // view updates itself after stabilization.
        return true
    }

    private func move(
        item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        sourceContainer: LayoutBarContainer? = nil,
        sectionOrderToCommit: [MenuBarItem]? = nil
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
                guard let duration = self?.layoutWatchdogDuration() else { return }
                try? await Task.sleep(for: duration + .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.resetStabilizingStateIfNeeded()
                guard let appState else { return }
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                if #available(macOS 27, *) {
                    await appState.imageCache.prewarmConcealedImagesMacOS27(
                        sections: MenuBarSection.Name.allCases,
                        onlyMissingImages: true
                    )
                }
                await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            }
            do {
                let recoveringStrandedVisibleControl = item.tag.matchesVisibleControlItem
                    && (item.bounds.origin.x == MenuBarItemGeometry.transientSentinelX || item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY)
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout,
                    allowParkedOffMenuBarSource: recoveringStrandedVisibleControl,
                    skipPreferredPositionMove: recoveringStrandedVisibleControl
                )
                if let sectionOrderToCommit {
                    appState.menuBarManager.sectionController?.setSectionOrder(
                        from: sectionOrderToCommit,
                        for: container.section
                    )
                }
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                await stabilizePlacement(of: item, to: destination, expectedSection: container.section, appState: appState)
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
                if !MenuBarBackendProvider.current.supportsLegacySectionHiding {
                    // macOS 27 verification must come from fresh AX order inside
                    // MenuBarItemManager. The layout cache may still contain the
                    // user's visual drop intent, so do not treat it as proof.
                    Self.diagLog.error("macOS 27: reorder move failed for \(item.logString); visible order was not persisted")
                } else if didItemReachIntendedPosition(
                    item: item,
                    destination: destination,
                    expectedSection: container.section,
                    cache: appState.itemManager.itemCache
                ) {
                    Self.diagLog.info("Move verification failed but \(item.logString) reached intended position in \(container.section.logString); suppressing alert")
                } else {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
            watchdogTask.cancel()
            if let appState = container.appState {
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
            await MainActor.run {
                self.isStabilizing = false
                self.setDimmed(false)
                // Update the badge anchor BEFORE re-enabling view updates, using
                // the current visual arrangement from the drag. This ensures the
                // didSet refresh uses the correct anchor position.
                // Only update if this section actually contains the badge.
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
    private func resetStabilizingStateIfNeeded() async {
        if isStabilizing {
            isStabilizing = false
            setDimmed(false)
            container.canSetArrangedViews = true
        }
    }

    private func setDimmed(_ visible: Bool) {
        container.alphaValue = visible ? 0.6 : 1.0
    }

    /// Whether items in the section currently have live AX elements to reorder.
    private func macOS27SectionIsPhysicallyLive(
        _ section: MenuBarSection.Name,
        controller: MenuBarSectionController?
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
    /// arrangement. The visible Thaw control (`Thaw.ControlItem.Visible`) is
    /// included so a layout-bar drag can commit the icon's new slot; hidden
    /// section dividers stay structural and are omitted.
    static func layoutItemsForPersistence(from arrangedViews: [LayoutBarArrangedView]) -> [MenuBarItem] {
        arrangedViews.compactMap { view in
            guard case let .item(item) = view.kind else { return nil }
            if item.isControlItem {
                return item.tag.matchesVisibleControlItem ? item : nil
            }
            return item
        }
    }

    private func orderedLayoutItems() -> [MenuBarItem] {
        Self.layoutItemsForPersistence(from: arrangedViews)
    }

    /// The members of the dragged item's bundle group in its source section, or
    /// `nil` when the item is ungrouped (single-item bundle or not groupable).
    ///
    /// Grouping is by bundle, so the whole bundle travels together on a
    /// cross-section drop — honoring "one section per group" — even if its items
    /// are not currently adjacent in the source section.
    private func crossSectionGroupMembers(
        for item: MenuBarItem,
        sourceSection: MenuBarSection.Name,
        controller: MenuBarSectionController?
    ) -> [MenuBarItem]? {
        guard let appState = container.appState else {
            return nil
        }
        let managed = appState.itemManager.itemCache.managedItems(for: sourceSection)
        let sourceItems = controller?.ordered(managed, in: sourceSection) ?? managed
        let tags = sourceItems.map(\.tag)
        guard let index = sourceItems.firstIndex(where: { $0.tag == item.tag }),
              let group = MenuBarItemGrouping.group(containing: index, in: tags),
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
    /// per group". Either way the group stays intact — individual items never
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
        container.canSetArrangedViews = true
        handle.sourceContainer?.canSetArrangedViews = true
    }

    /// Reorders a group as one contiguous block within its current section,
    /// **gathering** its members even if they start scattered.
    ///
    /// In a concealed section the items are snapshots, so persisting the new
    /// order is enough. In a physically-live section (Visible, or a revealed
    /// hidden section) persistence alone does not move anything — the block is
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

        // Members in their current left-to-right order — the sequence the
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

        // Drop cursor position in the *original* array's index space.
        let destination = groupHandleDestinationIndex(in: identifiers, dropX: dropX)

        // Gather: remove every member, then insert the block so it begins at the
        // drop cursor. Members sitting before the cursor shift the insertion left.
        var reordered = orderedItems.filter { !memberIDSet.contains($0.uniqueIdentifier) }
        let membersBefore = orderedItems.prefix(min(destination, orderedItems.count))
            .filter { memberIDSet.contains($0.uniqueIdentifier) }
            .count
        let insertionIndex = (destination - membersBefore).clamped(to: 0 ... reordered.count)
        reordered.insert(contentsOf: members, at: insertionIndex)

        // Dropped where the block already sits — nothing to do.
        guard reordered.map(\.uniqueIdentifier) != identifiers else {
            restoreAfterGroupDrop(handle)
            return true
        }

        if macOS27SectionIsPhysicallyLive(container.section, controller: controller) {
            let firstIndex = insertionIndex
            let afterBlockIndex = firstIndex + members.count
            moveGroupSequentially(
                members: members,
                rightAnchor: afterBlockIndex < reordered.count ? reordered[afterBlockIndex] : nil,
                leftAnchor: firstIndex > 0 ? reordered[firstIndex - 1] : nil,
                sectionOrderToCommit: reordered,
                sourceContainer: handle.sourceContainer
            )
            // The async task calls `finishDrag`, which restores view updates.
            return true
        }

        controller?.setSectionOrder(from: reordered, for: container.section)
        Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
        restoreAfterGroupDrop(handle)
        return true
    }

    /// Realizes a block move in a physically-live section with sequential AX
    /// moves.
    ///
    /// The members are anchored to a *fixed external neighbor* — the item that
    /// borders the block's destination and is not itself a group member — never
    /// to a just-moved member (whose cached AX element is momentarily stale, the
    /// cause of members landing apart). Inserting each member adjacent to that
    /// stable anchor in the right order keeps the block contiguous:
    /// - against a right neighbor: insert members front-to-back, each to its
    ///   left, so each new member pushes the previous ones further left;
    /// - against a left neighbor (block goes to the end): insert back-to-front,
    ///   each to its right.
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
        // `members` in left-to-right order — the sequence the block must end in.
        let memberOrder = members.map(\.tag)

        // Insert every member against a stable external anchor (never a
        // just-moved member). Front-to-back to the anchor's left, or — when the
        // block goes to the very end — back-to-front to a left anchor's right.
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
                appState.itemManager.itemCache.managedItems(for: section)
            }
            let liveItem: @MainActor (MenuBarItemTag) -> MenuBarItem? = { tag in
                liveOrder().first { $0.tag == tag }
            }
            // Whether the members already sit contiguously, in order, immediately
            // beside the anchor — i.e., the block move is complete.
            let isPlaced: @MainActor () -> Bool = {
                let live = liveOrder()
                guard let anchorIndex = live.firstIndex(where: { $0.tag == anchorTag }) else {
                    return false
                }
                let start = insertToLeftOfAnchor ? anchorIndex - memberOrder.count : anchorIndex + 1
                guard start >= 0, start + memberOrder.count <= live.count else {
                    return false
                }
                return memberOrder.indices.allSatisfy { live[start + $0].tag == memberOrder[$0] }
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
                            watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
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
            }

            appState.menuBarManager.sectionController?.setSectionOrder(
                from: sectionOrderToCommit,
                for: section
            )
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
        let controller = appState.menuBarManager.sectionController
        let sourceItems = appState.itemManager.itemCache.managedItems(for: handle.sourceSection)
        let members = handle.memberIdentifiers.compactMap { identifier in
            sourceItems.first { $0.uniqueIdentifier == identifier }
        }
        guard !members.isEmpty else {
            return false
        }

        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        guard members.allSatisfy({
            MenuBarSectionController.canAssign(
                $0,
                to: container.section,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        }) else {
            Self.diagLog.warning("Refusing group move to \(container.section.logString): a member is non-hideable")
            return false
        }

        controller?.setSection(container.section, items: members)
        Task { await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
        return true
    }

    /// The insertion index (in `identifiers` space) for a group dropped at
    /// `dropX`, resolved from the nearest arranged item view.
    private func groupHandleDestinationIndex(in identifiers: [String], dropX: CGFloat) -> Int {
        guard let nearest = container.arrangedView(nearestTo: dropX, excludingBadge: true),
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
    ) async {
        // First refresh caches and verify placement.
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
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout,
                    allowParkedOffMenuBarSource: recoveringStrandedVisibleControl,
                    skipPreferredPositionMove: recoveringStrandedVisibleControl
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
        if #available(macOS 27, *) {
            await appState.imageCache.prewarmConcealedImagesMacOS27(
                sections: MenuBarSection.Name.allCases,
                onlyMissingImages: true
            )
        }
        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
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

        appState.menuBarManager.$averageColorInfo
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] colorInfo in
                self?.notchView?.averageColorInfo = colorInfo
            }
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
