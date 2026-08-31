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

        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if arrangedViews.count == 1 {
                willMove = true
                Task {
                    guard case let .item(item) = draggingSource.kind else {
                        self.container.canSetArrangedViews = true
                        sourceContainer?.canSetArrangedViews = true
                        return
                    }
                    if let destination = await self.liveFallbackDestinationForDraggedItem() {
                        self.move(item: item, to: destination, sourceContainer: sourceContainer)
                    } else {
                        Self.diagLog.error("No target item for layout bar drag")
                        self.container.canSetArrangedViews = true
                        sourceContainer?.canSetArrangedViews = true
                    }
                }
            } else if case let .item(item) = draggingSource.kind {
                if let targetItem = nearestItem(toRightOf: index) {
                    willMove = true
                    move(item: item, to: .leftOfItem(targetItem), sourceContainer: sourceContainer)
                } else if let targetItem = nearestItem(toLeftOf: index) {
                    willMove = true
                    move(item: item, to: .rightOfItem(targetItem), sourceContainer: sourceContainer)
                } else if !arrangedViews.isEmpty {
                    willMove = true
                    Task {
                        if let destination = await self.liveFallbackDestinationForDraggedItem() {
                            self.move(item: item, to: destination, sourceContainer: sourceContainer)
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
                        await MainActor.run {
                            self.isStabilizing = false
                            self.showOverlay(false)
                            self.container.canSetArrangedViews = true
                            if sourceContainer !== self.container {
                                sourceContainer?.canSetArrangedViews = true
                            }
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

            let watchdogTask = Task { [weak self, weak appState, revealedSections] in
                try? await Task.sleep(for: MenuBarItemManager.layoutWatchdogTimeout + .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.resetStabilizingStateIfNeeded()
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

            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
                )
                // Record the user move before stabilization so the save
                // gate's cooldown exemption is armed when stabilizePlacement's
                // own cache pass reaches it. Recording it only after stabilize
                // returned meant the first cache pass inside stabilize hit
                // the 5s move cooldown with no user-move exemption, so the
                // save was skipped; by the time the exemption armed, the
                // mid-transition cache gate had re-armed and no accepting
                // pass coincided with the cooldown window. The drag never
                // saved (#983). move() threw no error, so the user's drag
                // did land; the rescue-and-retry catch block below still
                // owns the case where macOS didn't settle it.
                appState.itemManager.recordExternalMoveOperation()
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                _ = await stabilizePlacement(
                    of: item,
                    to: destination,
                    expectedSection: container.section,
                    appState: appState
                )
            } catch MenuBarItemManager.EventError.menuTrackingActive {
                // A menu bar item's menu (Wi-Fi picker, input method panel,
                // etc.) was open and the move was deferred to avoid tearing
                // down the user's interaction. This isn't a failure worth
                // alerting on — log only.
                Self.diagLog.info("Move deferred, a menu bar item menu was open")
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
                        // Same #983 reorder as the primary path: arm the
                        // save-gate user-move exemption before stabilize so
                        // its cache pass can persist the retry.
                        appState.itemManager.recordExternalMoveOperation()
                        appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                        _ = await stabilizePlacement(
                            of: item,
                            to: destination,
                            expectedSection: container.section,
                            appState: appState
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
            showOverlay(false)
            container.canSetArrangedViews = true
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
