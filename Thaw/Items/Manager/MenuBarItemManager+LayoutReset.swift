//
//  MenuBarItemManager+LayoutReset.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit
import ThawLayout

// MARK: Layout Reset

extension MenuBarItemManager {
    enum LayoutResetError: LocalizedError {
        case missingAppState
        case missingControlItems
        /// No assignments were read or written; callers must not report this as a reset with zero failures.
        case engineNotRunning

        var errorDescription: String? {
            switch self {
            case .missingAppState:
                "Unable to access app state"
            case .missingControlItems:
                "Couldn't find section dividers in the menu bar"
            case .engineNotRunning:
                "The menu bar engine is not running, so nothing was moved"
            }
        }

        var recoverySuggestion: String? {
            "Make sure \(Constants.displayName) is running and try again."
        }
    }

    static nonisolated func overflowControlUIDs(
        in items: [MenuBarItem]
    ) -> ControlUIDs {
        // ControlItemPair removes Hidden before caching; use its stable tag when the managed cache lacks it.
        let hiddenUID = items.first(where: { $0.tag == .hiddenControlItem })?.uniqueIdentifier
            ?? MenuBarItemTag.hiddenControlItem.tagIdentifier
        return ControlUIDs(
            visible: items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier,
            hidden: hiddenUID,
            alwaysHidden: items.first(where: { $0.tag == .alwaysHiddenControlItem })?.uniqueIdentifier
        )
    }

    /// Indivisible groups resolved against the budgeted items so member IDs match desiredFiltered.
    static func groupPolicySet(
        for items: [MenuBarItem],
        appState: AppState?
    ) -> MenuBarItemGroupPolicy.GroupSet {
        guard let appState,
              !items.isEmpty
        else {
            return .empty
        }
        let resolved = MenuBarItemGroupResolver.resolve(
            tags: items.map(\.tag),
            groupSet: appState.itemGroupManager.groupSet
        )
        return MenuBarItemGroupPolicy.GroupSet(
            groups: resolved.map { group in
                group.memberIndices.compactMap { index in
                    items.indices.contains(index) ? items[index].uniqueIdentifier : nil
                }
            }
        )
    }

    /// Log oversized groups and missing widths, which otherwise silently change the pure planner's outcome.
    private static func logOverflowDiagnostics(_ result: LayoutSolver.NotchOverflowResult) {
        if !result.groupsOverflowedWhole.isEmpty {
            diagLog.info(
                "macOS 27 overflow: moved \(result.groupsOverflowedWhole.count) group(s) to hidden as one unit"
            )
        }
        for group in result.oversizedGroups {
            diagLog.warning(
                "macOS 27 overflow: group \(group.joined(separator: ", ")) is wider than the whole " +
                    "budget and can never fit; moved to hidden without ejecting the rest of the bar"
            )
        }
        if !result.missingWidthUIDs.isEmpty {
            diagLog.warning(
                "macOS 27 overflow: \(result.missingWidthUIDs.count) item(s) had no measured width " +
                    "and were budgeted as zero: \(result.missingWidthUIDs.joined(separator: ", "))"
            )
        }
    }

    /// Assignment backends bypass legacy overflow; conceal visible items exceeding the app-menu-to-Control-Center budget here.
    /// Only explicit requests reorder; observations only conceal and are rate-limited unless a probe needs an immediate pass.
    @MainActor
    @discardableResult
    func rebalanceOverflowIfNeeded(
        items liveItems: [MenuBarItem]? = nil,
        reason: LayoutChangeReason,
        immediate: Bool = false
    ) async -> Bool {
        guard let appState else { return false }
        let controller = appState.menuBarManager.sectionController

        guard configuration.enableMenuBarItemOverflow else {
            lastOverflowRebalance = nil
            return controller.setOverflowHiddenIdentifiers([])
        }

        // Explicit requests and dependent probe transitions bypass the observation rate limit.
        if !immediate, !reason.permitsOrderEnforcement,
           let last = lastOverflowRebalance,
           Date().timeIntervalSince(last) < 2.0
        {
            return false
        }

        let items: [MenuBarItem] = if let liveItems {
            liveItems.filter { !$0.isSystemClone && !$0.isNativeOverflowControl }
        } else if !itemCache.managedItems.isEmpty {
            itemCache.managedItems.filter { !$0.isSystemClone && !$0.isNativeOverflowControl }
        } else {
            await (MenuBarItem.getMenuBarItems(option: .activeSpace))
                .filter { !$0.isSystemClone && !$0.isNativeOverflowControl }
        }
        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return false
        }

        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding
        /// Control Center modules hide via System Settings toggles, so overflow cannot reclaim their width.
        func isProfileItem(_ item: MenuBarItem) -> Bool {
            !item.isControlItem
                && !RuntimeModuleController.isGovernable(itemIdentifier: item.uniqueIdentifier)
                && MenuBarBackendProvider.current.canAssign(
                    item,
                    to: .hidden,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                )
        }

        let transientTags: [MenuBarItemTag] = [
            .audioVideoModule,
            .faceTime,
            .screenCaptureUI,
            .gameMode,
        ]
        let permanentNonProfileBounds = items.compactMap { item -> CGRect? in
            guard !isProfileItem(item),
                  item.tag != .controlCenter,
                  item.tag != .visibleControlItem
            else { return nil }
            if transientTags.contains(where: {
                $0.namespace == item.tag.namespace && $0.title == item.tag.title
            }) || item.isTransientControlCenterItem {
                return nil
            }
            return item.bounds
        }

        let overflowControlBounds = controller.nativeOverflowControlBounds(on: screen.displayID)
        let capacity = MenuBarCapacitySnapshot.capture(
            on: screen,
            items: items,
            overflowControlBounds: overflowControlBounds
        )
        let availableWidth = capacity.availableWidth(
            in: .trailing,
            applicationMenus: .visible,
            reserving: permanentNonProfileBounds
        )

        let controlUIDs = Self.overflowControlUIDs(in: items)
        let visibleCtrl = items.first(where: { $0.tag == .visibleControlItem })
        let ahCtrl = items.first(where: { $0.tag == .alwaysHiddenControlItem })

        let authoredVisibleByGeometry = items
            .filter { item in
                !item.isControlItem
                    && controller.authoredSection(for: item.uniqueIdentifier) == .visible
                    && isProfileItem(item)
            }
            .sorted { lhs, rhs in
                if lhs.bounds.midX == rhs.bounds.midX {
                    return lhs.uniqueIdentifier < rhs.uniqueIdentifier
                }
                return lhs.bounds.midX < rhs.bounds.midX
            }
        let recordedVisibleOrder = controller.sectionItemOrder[.visible]
            ?? savedSectionOrder[MenuBarSection.Name.visible.rawValue]
            ?? []
        let visibleLive = MenuBarBackendProvider.current.overflowOrderedVisibleItems(
            authoredVisibleByGeometry,
            using: recordedVisibleOrder
        )

        let hiddenLive = items.filter {
            controller.authoredSection(for: $0.uniqueIdentifier) == .hidden && !$0.isControlItem
        }
        let alwaysHiddenLive = items.filter {
            controller.authoredSection(for: $0.uniqueIdentifier) == .alwaysHidden && !$0.isControlItem
        }

        let visibleSegment: [MenuBarItem] = if let visibleCtrl {
            Self.structuralVisibleSegment(
                ordinaryVisibleItems: visibleLive,
                visibleControl: visibleCtrl,
                savedOrder: recordedVisibleOrder
            )
        } else {
            visibleLive
        }
        var desiredFiltered = visibleSegment.map(\.uniqueIdentifier)
        let hiddenCtrlUID = controlUIDs.hidden
        desiredFiltered.append(hiddenCtrlUID)
        desiredFiltered.append(contentsOf: hiddenLive.map(\.uniqueIdentifier))
        if let ahCtrlUID = ahCtrl?.uniqueIdentifier {
            desiredFiltered.append(ahCtrlUID)
            desiredFiltered.append(contentsOf: alwaysHiddenLive.map(\.uniqueIdentifier))
        }

        var sectionMap = [String: String]()
        for item in visibleSegment {
            sectionMap[item.uniqueIdentifier] = MenuBarSection.Name.visible.rawValue
        }
        for item in hiddenLive {
            sectionMap[item.uniqueIdentifier] = MenuBarSection.Name.hidden.rawValue
        }
        for item in alwaysHiddenLive {
            sectionMap[item.uniqueIdentifier] = MenuBarSection.Name.alwaysHidden.rawValue
        }

        let savedVisible = Set(
            MenuBarItemTag.canonicalPersistentIdentifiers(recordedVisibleOrder)
        )
        let unmanagedUIDs = visibleLive
            .map(\.uniqueIdentifier)
            .filter { !savedVisible.contains(MenuBarItemTag.canonicalPersistentIdentifier($0)) }

        // macOS 27 collapses hidden/overflow AX widths to about 2 pt; floor them to avoid underbudgeting.
        // visibleLive excludes controls, which retain their true thin widths.
        var uidWidths = [String: CGFloat]()
        var collapsedWidthCount = 0
        for item in visibleLive {
            let measured = item.bounds.width
            if measured < MenuBarItemImageCache.minimumTrustedGlyphWidth {
                collapsedWidthCount += 1
            }
            uidWidths[item.uniqueIdentifier] = Self.budgetWidth(forMeasuredWidth: measured)
        }
        if let visibleCtrl {
            uidWidths[visibleCtrl.uniqueIdentifier] = visibleCtrl.bounds.width
        }
        let trailingLaneItemWidth = uidWidths.values.reduce(0, +)

        MenuBarItemManager.diagLog.debug(
            """
            macOS 27 overflow budget: display=\(screen.displayID) \
            trailingBoundary=\(String(describing: capacity.trailingBoundary)) \
            availableWidth=\(String(describing: availableWidth)) \
            visibleCount=\(visibleLive.count) unmanagedCount=\(unmanagedUIDs.count) \
            trailingLaneItemWidth=\(trailingLaneItemWidth) collapsedWidthCount=\(collapsedWidthCount)
            """
        )

        // A zero/negative/non-finite budget means screen geometry is unsettled,
        // not that every automatically overflowed item suddenly fits.
        guard let availableWidth, availableWidth.isFinite, availableWidth > 0 else {
            return false
        }

        // Native overflow proves the modeled headroom is wrong; subtract its control width plus one nominal item.
        // The probe remeasures each cycle; a modest deficit avoids Visible/Hidden oscillation.
        var effectiveAvailableWidth = availableWidth
        let isNativeOverflowActive = controller.isNativeOverflowActive(on: screen.displayID)
        if isNativeOverflowActive {
            let controlWidth = controller.nativeOverflowControlBounds(on: screen.displayID)
                .map(\.width).max() ?? 0
            let deficit = controlWidth + Self.nominalStatusItemWidth
            effectiveAvailableWidth = max(1, availableWidth - deficit)
        }

        // A notch-covered control proves the budget is too large; only concealing more items makes room, not order repair.
        let occlusionDeficit = Self.notchOcclusionDeficit(
            previous: heldNotchOcclusionDeficit,
            occludedControlWidth: items
                .filter { $0.isControlItem && MenuBarNotchGeometry.isOccluded($0, by: MenuBarNotchGeometry.rects) }
                .map(\.bounds.width)
                .reduce(0, +),
            visibleUIDs: Set(visibleLive.map(\.uniqueIdentifier)),
            overflowUIDs: controller.overflowHiddenIdentifiers
        )
        if occlusionDeficit?.width != heldNotchOcclusionDeficit?.width {
            MenuBarItemManager.diagLog.info(
                "macOS 27 overflow: notch occlusion deficit \(occlusionDeficit?.width ?? 0) pt (was \(heldNotchOcclusionDeficit?.width ?? 0))"
            )
        }
        heldNotchOcclusionDeficit = occlusionDeficit
        if let occlusionDeficit {
            effectiveAvailableWidth = max(1, effectiveAvailableWidth - occlusionDeficit.width)
        }

        // Visible items parked at x == -1 indicate the bar had no room to draw them.
        // Only on a settled, concealed bar: a reveal fills the bar with hidden
        // items, or with whole apps under native hiding, and macOS parks Visible
        // items that fit again once it closes. Counting them hid them for good.
        let overflowIdentifiers = controller.overflowHiddenIdentifiers
        let concealedIdentifiers = controller.effectivelyConcealedIdentifiers
        let isBarSettled = controller.revealedSection == nil
            && !appState.menuBarManager.isRevealHideTransitionActive
        let parkedWidths = !isBarSettled ? [] : visibleLive
            .filter { item in
                let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
                return item.bounds.minX == MenuBarItemGeometry.transientSentinelX
                    && !overflowIdentifiers.contains(item.uniqueIdentifier)
                    && !concealedIdentifiers.contains(key)
            }
            .map(\.bounds.width)
        let parkedDeficit = Self.parkedLaneDeficit(
            previous: heldParkedLaneDeficit,
            parkedWidths: parkedWidths,
            isNativeOverflowActive: isNativeOverflowActive,
            modeledHeadroom: effectiveAvailableWidth - trailingLaneItemWidth,
            visibleUIDs: Set(visibleLive.map(\.uniqueIdentifier)),
            overflowUIDs: overflowIdentifiers
        )
        if parkedDeficit?.width != heldParkedLaneDeficit?.width {
            MenuBarItemManager.diagLog.info(
                "macOS 27 overflow: \(parkedWidths.count) visible item(s) left off the bar; deficit \(parkedDeficit?.width ?? 0) pt (was \(heldParkedLaneDeficit?.width ?? 0))"
            )
        }
        heldParkedLaneDeficit = parkedDeficit
        if !parkedWidths.isEmpty, !isNativeOverflowActive {
            MenuBarItemManager.diagLog.debug(
                "macOS 27 overflow: \(parkedWidths.count) visible item(s) off the bar without native overflow; not counted as a full bar"
            )
        }
        if let parkedDeficit {
            effectiveAvailableWidth = max(1, effectiveAvailableWidth - parkedDeficit.width)
        }

        let overflowResult = LayoutSolver.planNotchOverflow(
            desiredFiltered: desiredFiltered,
            unmanagedUIDs: unmanagedUIDs,
            controlUIDs: controlUIDs,
            sectionMap: sectionMap,
            uidWidths: uidWidths,
            availableWidth: effectiveAvailableWidth,
            groups: Self.groupPolicySet(for: visibleLive, appState: appState)
        )
        Self.logOverflowDiagnostics(overflowResult)

        lastOverflowRebalance = Date()
        let overflowSet = Set(overflowResult.overflowUIDs)
        let overflowItems = visibleLive.filter { overflowSet.contains($0.uniqueIdentifier) }
        if overflowItems.count != overflowSet.count {
            // The setter filters by authored section again, so this unexpected mismatch narrows the set twice.
            MenuBarItemManager.diagLog.warning(
                "macOS 27 overflow: \(overflowSet.count) planned but only \(overflowItems.count) resolved to live items"
            )
        }
        // Concealment needs no cursor or synthetic drag and is the only action permitted for observed changes.
        let didChange = controller.setOverflowHiddenItems(overflowItems)
        if didChange {
            MenuBarItemManager.diagLog.info(
                "macOS 27 overflow: temporarily concealing \(overflowSet.count) authored-visible item(s)"
            )
        }

        // Only explicit requests restore authored order; oscillating overflow sets would repeatedly drag the boundary item.
        if reason.permitsOrderEnforcement {
            await applySectionItemOrder(
                sections: [.visible],
                controller: controller,
                visibleOrderOverride: freshestRecordedVisibleOrder(controller: controller),
                reason: reason,
                preferredMoveUIDs: Set(unmanagedUIDs)
            )
            await cacheItemsRegardless(skipRecentMoveCheck: true)
        }
        return didChange
    }

    /// Writes membership and order through RuntimeSectionController rather than legacy bulk moves.
    /// - Returns: false if the controller is unavailable and nothing was written, not a successful apply.
    private func applyProfileLayoutToController(
        appState: AppState,
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        source: ApplySource
    ) async -> Bool {
        let controller = appState.menuBarManager.sectionController
        guard controller.isOperational else {
            MenuBarItemManager.diagLog.error("applyProfileLayout (macOS 27): missing RuntimeSectionController")
            return false
        }

        // Controller assignments drive the assertion and persist via Thaw.simpleSectionAssignment; only profiles overwrite them.
        // Mirror savedSectionOrder from the controller, since restoring its lagging copy on windowID changes undoes user drags.
        if source == .profile {
            controller.applyProfileLayout(
                itemSectionMap: itemSectionMap,
                itemOrder: itemOrder
            )

            savedSectionOrder = itemOrder
            persistSavedSectionOrder()
        }

        // Visible items have live AX elements, but only profiles reconcile synthetically; assignment mirroring owns membership.
        if source == .profile {
            await applySectionItemOrder(
                sections: [.visible],
                controller: controller,
                reason: .profileApply
            )
        }

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // Assignment backends bypass legacy overflow; rebalance here to populate Hidden and Thaw Bar.
        _ = await rebalanceOverflowIfNeeded(items: items, reason: .profileApply)

        MenuBarItemManager.diagLog.info(
            "applyProfileLayout (macOS 27): applied \(controller.sectionAssignment.count) assignment(s)"
        )

        persistProfileStateOnSuccess(source: source)
        clearProfileState(source: source)
        scheduleDeferredCacheRefresh()
        return true
    }

    /// Reassigns movable, hideable items except Thaw's control; protected system items require experimental hiding.
    /// - Returns: Always 0, since there are no physical moves; an unavailable engine throws LayoutResetError.engineNotRunning.
    private func resetAssignments(to target: MenuBarSection.Name = .hidden) async throws -> Int {
        isResettingLayout = true
        defer { isResettingLayout = false }

        guard let appState else { throw LayoutResetError.missingAppState }
        let controller = appState.menuBarManager.sectionController
        guard controller.isOperational else {
            MenuBarItemManager.diagLog.warning("macOS 27 reset: no RuntimeSectionController; nothing to do")
            throw LayoutResetError.engineNotRunning
        }

        // Drop any stale legacy persisted order so the two models never fight.
        savedSectionOrder.removeAll()
        persistSavedSectionOrder()

        // Refresh inventory to include layout-anchored system items for experimental hiding.
        await cacheItemsRegardless(skipRecentMoveCheck: true)

        // Use the cached inventory so the reset covers the same items as the layout bars.
        var assignment = [String: MenuBarSection.Name]()
        var skippedProtectedItems = [String]()
        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding
        for item in itemCache.managedItems
            where MenuBarBackendProvider.current.canAssign(
                item,
                to: target,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        {
            guard !MenuBarBackendProvider.current.isProtectedAssignmentItem(
                item,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) else {
                skippedProtectedItems.append(item.uniqueIdentifier)
                continue
            }
            assignment[item.uniqueIdentifier] = target
        }

        controller.resetAssignment(to: assignment)
        if !skippedProtectedItems.isEmpty {
            MenuBarItemManager.diagLog.info("macOS 27 reset: skipped \(skippedProtectedItems.count) protected item(s): \(skippedProtectedItems)")
        }
        MenuBarItemManager.diagLog.info("macOS 27 reset: swept \(assignment.count) item(s) to \(target.rawValue)")

        await cacheItemsRegardless(skipRecentMoveCheck: true)

        // Clock, Control Center, and Siri need an assertion teardown/reactivation to leave the bar after assignment.
        if experimentalSystemItemHiding,
           assignment.contains(where: { identifier, _ in
               itemCache.managedItems.contains {
                   $0.uniqueIdentifier == identifier && $0.tag.isLayoutAnchoredSystemItem
               }
                   || controller.snapshot(for: identifier)?.tag.isLayoutAnchoredSystemItem == true
           })
        {
            MenuBarItemManager.diagLog.info("macOS 27 reset: pulsing restriction for layout-anchored system items")
            controller.refresh(forceRestrictionPulse: true)
            await cacheItemsRegardless(skipRecentMoveCheck: true)
        }

        await MainActor.run {
            appState.imageCache.performCacheCleanup()
        }
        if itemCache.displayID != nil {
            await appState.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            await appState.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
        }

        return 0
    }

    /// Resets layout data and moves movable, hideable items except Thaw's icon to Hidden.
    /// - Returns: The number of items that failed to move.
    /// - Throws: LayoutResetError.engineNotRunning if nothing ran; do not treat that as zero failures.
    func resetLayoutToFreshState() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to fresh state")
        return try await executeReset(for: .freshInstallHidden)
    }

    private func executeReset(for target: SectionResetTarget) async throws -> Int {
        // Reassigning every item invalidates the swap state.
        appState?.menuBarManager.clearSwapState()
        switch target {
        case .freshInstallHidden:
            return try await resetAssignments(to: .hidden)
        case .allVisible:
            return try await clearAssignmentsToVisible()
        case .allAlwaysHidden:
            return try await resetAssignments(to: .alwaysHidden)
        @unknown default:
            return try await clearAssignmentsToVisible()
        }
    }

    /// Clears assignments to return hideable items to Visible through RuntimeSectionController.
    /// - Returns: Always 0, since there are no physical moves; an unavailable engine throws LayoutResetError.engineNotRunning.
    private func clearAssignmentsToVisible() async throws -> Int {
        isResettingLayout = true
        defer { isResettingLayout = false }

        guard let appState else { throw LayoutResetError.missingAppState }
        let controller = appState.menuBarManager.sectionController
        guard controller.isOperational else {
            MenuBarItemManager.diagLog.warning("macOS 27 reset-to-visible: no RuntimeSectionController; nothing to do")
            throw LayoutResetError.engineNotRunning
        }

        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        persistPinnedBundleIDs()
        savedSectionOrder.removeAll()
        persistSavedSectionOrder()

        controller.resetAssignment(to: [:])
        MenuBarItemManager.diagLog.info("macOS 27 reset-to-visible: cleared all section assignments")

        await cacheItemsRegardless(skipRecentMoveCheck: true)

        await MainActor.run {
            appState.imageCache.clearAll()
            appState.imageCache.performCacheCleanup()
        }
        await appState.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)

        return 0
    }

    /// Moves every movable, hideable item to the always-hidden section.
    /// - Returns: The number of items that failed to move.
    /// - Throws: LayoutResetError.engineNotRunning if nothing ran; do not treat that as zero failures.
    func resetLayoutToAlwaysHidden() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to always-hidden")
        return try await executeReset(for: .allAlwaysHidden)
    }

    /// Moves every movable, hideable item to the visible section.
    /// - Returns: The number of items that failed to move.
    /// - Throws: LayoutResetError.engineNotRunning if nothing ran; do not treat that as zero failures.
    func resetLayoutToVisible() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to visible")
        return try await executeReset(for: .allVisible)
    }

    /// Cancels preflight settling after a no-op spacing apply so restores are not needlessly suppressed.
    /// Refuses expected-set settling: concurrent no-op applies must not release a relaunch wait into a partial cache.
    func cancelSettlingPeriod(reason: String) {
        guard isInStartupSettling || startupSettlingTask != nil else { return }
        if !settlingExpectedBundleIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling cancel ignored; \(settlingExpectedBundleIDs.count) expected bundle ID(s) still pending"
            )
            return
        }
        // A boot-time no-op applyOffset must not cancel cold settling while apps are still reattaching.
        // A partial cache would falsely report that all items are in place.
        if settlingKind == .cold {
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling cancel ignored; performSetup settling in flight"
            )
            return
        }
        startupSettlingTask?.cancel()
        startupSettlingTask = nil
        isInStartupSettling = false
        settlingDeadline = nil
        settlingKind = nil
        MenuBarItemManager.diagLog.debug("\(reason): settling period cancelled")
    }

    func clearActiveProfileLayout() {
        activeProfileLayout = nil
        isApplyingProfileLayout = false
    }

    /// Recheck settling after each await: performSetup re-entry can cancel the captured task and start a new window.
    private func waitForStartupSettlingToEnd() async {
        while isInStartupSettling {
            guard let settlingTask = startupSettlingTask else { break }
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: waiting for startup settling to end"
            )
            await settlingTask.value
        }
    }

    /// Selects entry/exit state handling; the rest of the apply path is shared.
    enum ApplySource {
        /// A profile spec overwrites savedSectionOrder, the pinning sets and
        /// activeProfileLayout; isApplyingProfileLayout gates concurrent restores.
        case profile
        /// Re-applies the saved layout as is. Only isRestoringItemOrder is armed.
        case savedOrder
    }

    /// Centralizes profile state and gates; savedOrder leaves them untouched.
    /// Persist only after success so crashes or cancellations leave the previous profile on disk.
    func armProfileState(
        source: ApplySource,
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        suppressSpatialOrderPersistenceAfterFailedApply = false
        guard case .profile = source else { return }
        pinnedHiddenBundleIDs = pinnedHidden
        pinnedAlwaysHiddenBundleIDs = pinnedAlwaysHidden
        savedSectionOrder = sectionOrder

        isApplyingProfileLayout = true
        activeProfileLayout = (
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )
    }

    /// Refreshes the New Items placement spec after an active-profile update without moving items.
    /// Leaves saved order, live pinning sets, and the apply gate unchanged; the bar already matches the snapshot.
    func rearmActiveProfileLayout(
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        activeProfileLayout = (
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )
        MenuBarItemManager.diagLog.debug(
            "rearmActiveProfileLayout: refreshed cached profile spec after active-profile update"
        )
    }

    /// Commits profile pins and order only after the bar reflects them; savedOrder leaves both stores unchanged.
    private func persistProfileStateOnSuccess(source: ApplySource) {
        guard case .profile = source else { return }
        persistPinnedBundleIDs()
        persistSavedSectionOrder()
    }

    /// Clears the profile gate only for profile applies.
    private func clearProfileState(source: ApplySource) {
        guard case .profile = source else { return }
        isApplyingProfileLayout = false
    }

    /// Defer cache refresh, relocation, persistence, image cleanup, and notification until the outer cacheGate is released.
    /// Inline recursion is rejected and leaves stale items; uiSettleDelay lets WindowServer settle moves and windowID churn.
    private func scheduleDeferredCacheRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            guard let self else { return }
            // Skip reapplying to avoid a windowID-churn dispatch loop; uncheckedCacheItems still updates and saves.
            await self.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                skipSavedLayoutApply: true
            )
            guard let appState = self.appState else { return }
            appState.imageCache.performCacheCleanup()
            await appState.imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
        }
    }

    /// Keys sections and order per item because multiple Control Center items share a bundle ID.
    /// - Returns: false for missing app state or engine; true for cancellation by a newer apply or an empty order.
    func applyProfileLayout(
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        source: ApplySource = .profile
    ) async -> Bool {
        // MARK: Phase 0: gate on startup settling

        // cacheItemsRegardless skips restore during settling, which would silently shadow these moves.
        await waitForStartupSettlingToEnd()

        // A newer apply may cancel us during settling; do not arm the superseded profile's state.
        if Task.isCancelled {
            return true
        }

        // MARK: Phase 1: persist state and arm in-flight flags

        // savedOrder keeps its source order and skips profile state; relocateNewLeftmostItems handles its late arrivals.
        armProfileState(
            source: source,
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )

        // Both apply sources must prevent the cache from saving intermediate positions.
        isRestoringItemOrder = true
        isRestoringItemOrderTimestamp = Date()
        defer {
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        guard let appState else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing appState")
            return false
        }
        guard !itemOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applyProfileLayout: no item order, skipping")
            return true
        }

        // MenuBarAgent hosts every item, so membership uses RuntimeSectionController assignments, not window moves.
        return await applyProfileLayoutToController(
            appState: appState,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder,
            source: source
        )
    }

    /// Restores saved order without profile-specific state; on assignment backends only the Visible control is restored.
    /// Returns true when dispatched, with its own follow-up cache cycle (end the caller's cycle); false if guarded out.
    func applySavedLayout(
        items: [MenuBarItem],
        previousWindowIDs _: [CGWindowID],
        controlItems _: ControlItemPair,
        previousDisplayID _: CGDirectDisplayID? = nil,
        currentDisplayID _: CGDirectDisplayID? = nil
    ) async -> Bool {
        guard !isNotificationCenterLayoutSuspended else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: deferred during Notification Center assertion suspension")
            return false
        }
        guard !moveCircuitBreaker.isOpen else {
            MenuBarItemManager.diagLog.debug("Move circuit breaker open; skipping applySavedLayout")
            return false
        }
        // Log distinct guard reasons and check cheap state before building windowID/tag sets.
        // Manual arrangement forbids engine restores, repairs, and reorders because the user owns the order.
        guard !arrangementIsManual else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, manual arrangement is on")
            return false
        }
        guard !savedSectionOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, savedSectionOrder is empty")
            return false
        }
        guard !suppressNextNewLeftmostItemRelocation else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, suppressNextNewLeftmostItemRelocation armed")
            scheduleDeferredLayoutReconcile(after: .seconds(2), reason: "leftmost relocation suppressed")
            return false
        }
        // A savedOrder apply would fight the in-flight profile layout.
        guard !isApplyingProfileLayout else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, profile apply in flight")
            scheduleDeferredLayoutReconcile(after: .seconds(2), reason: "profile apply in flight")
            return false
        }
        // A 5 s move cooldown prevents cascading applies during rapid app relaunches.
        guard !lastMoveOperationOccurred(within: .seconds(5)) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, within 5s move cooldown")
            scheduleDeferredLayoutReconcile(after: .seconds(5), reason: "move cooldown")
            return false
        }
        // MoveInputSuppression cannot retract a delivered mouse-down; synthetic events during ⌘-drag can duplicate icons or crash Finder.
        // The drop republishes itemCache and starts the move cooldown before applying.
        if appState?.isDraggingMenuBarItem ?? false {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, user ⌘-drag in progress")
            scheduleDeferredLayoutReconcile(after: .seconds(1), reason: "user drag in progress")
            return false
        }
        if let lastRestrictionChange = lastRestrictionChangeTimestamp,
           lastRestrictionChange.duration(to: .now) < Self.restrictionChangeLayoutSettleWindow
        {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, within restriction-reflow settle window"
            )
            scheduleDeferredLayoutReconcile(
                after: Self.restrictionChangeLayoutSettleWindow,
                reason: "restriction-reflow settle"
            )
            return false
        }
        // Reset the deferral budget once reconciliation passes all transient guards.
        noteLayoutReconcileRan()
        // Mirror savedSectionOrder from assignments; items left of Hidden can still be Visible after assertion reflow.
        // Spatial-divergence reorders collide with volatile neighbors and can strand them off-bar.
        return await restoreVisibleControlOrder(items: items)
    }

    private func restoreVisibleControlOrder(items: [MenuBarItem]) async -> Bool {
        let desiredOrder = savedSectionOrder[sectionKey(for: .visible)] ?? []
        guard let plannedMove = MenuBarLayoutPlannerProvider.current.visibleControlRestoreMove(
            items: items,
            desiredOrder: desiredOrder,
            experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding
        ) else {
            // Distinguish unresolved saved entries from an actual match; both produce a nil plan.
            let liveIdentifiers = Set(items.map(\.uniqueIdentifier))
            let unresolved = desiredOrder.filter { !liveIdentifiers.contains($0) }
            let listsControl = items.contains {
                $0.tag.matchesVisibleControlItem && desiredOrder.contains($0.uniqueIdentifier)
            }
            if !desiredOrder.isEmpty, !listsControl {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, saved visible order (\(desiredOrder.count) entries, \(unresolved.count) unresolved) does not list the visible control"
                )
            } else if !unresolved.isEmpty {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, macOS 27 visible control order matches the saved entries that resolve; \(unresolved.count) of \(desiredOrder.count) resolve to no live item"
                )
            } else {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, macOS 27 visible control order already matches saved layout"
                )
            }
            return false
        }

        // Rate-limit by control, not destination: changing neighbors bypass destination-scoped failure backoff.
        // Count every outcome to cap futile nudges, including placements MenuBarAgent reverts.
        if let lastAttempt = lastVisibleControlRestoreAttempt,
           ContinuousClock.now - lastAttempt < Self.visibleControlRestoreCooldown
        {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping macOS 27 visible control restore; within attempt cooldown"
            )
            return false
        }

        lastVisibleControlRestoreAttempt = .now
        recordVisibleControlHostState(reason: "before-restore")
        do {
            let fulfilled = try await move(
                item: plannedMove.item,
                to: plannedMove.destination,
                skipInputPause: true,
                allowParkedOffMenuBarSource: true
            )
            guard fulfilled else {
                // MenuBarAgent can store a position without resorting; the control has no synthetic-drag fallback.
                // Retry once after a width nudge for fresh invalidation, except when the lock screen blocked the write.
                if !screenLockTransitions.isLocked,
                   appState?.menuBarManager.requestMenuBarAgentPositionRefresh() == true
                {
                    MenuBarItemManager.diagLog.info(
                        "applySavedLayout: re-nudging MenuBarAgent and retrying visible control restore for \(plannedMove.item.logString)"
                    )
                    let retried = try await move(
                        item: plannedMove.item,
                        to: plannedMove.destination,
                        skipInputPause: true,
                        allowParkedOffMenuBarSource: true
                    )
                    guard retried else {
                        recordVisibleControlHostState(reason: "restore-unfulfilled")
                        MenuBarItemManager.diagLog.debug(
                            "applySavedLayout: could not fulfill macOS 27 visible control restore via preferred positions " +
                                "\(plannedMove.item.logString) \(plannedMove.destination.logString)"
                        )
                        return false
                    }
                    MenuBarItemManager.diagLog.info(
                        "applySavedLayout: restored macOS 27 visible control order for \(plannedMove.item.logString) after re-nudge"
                    )
                    recordVisibleControlHostState(reason: "restore-fulfilled")
                    scheduleDeferredCacheRefresh()
                    return true
                }
                recordVisibleControlHostState(reason: "restore-unfulfilled")
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: could not fulfill macOS 27 visible control restore via preferred positions " +
                        "\(plannedMove.item.logString) \(plannedMove.destination.logString)"
                )
                return false
            }
            MenuBarItemManager.diagLog.info(
                "applySavedLayout: restored macOS 27 visible control order for \(plannedMove.item.logString)"
            )
            recordVisibleControlHostState(reason: "restore-fulfilled")
            scheduleDeferredCacheRefresh()
            return true
        } catch {
            recordVisibleControlHostState(reason: "restore-error")
            MenuBarItemManager.diagLog.error(
                "applySavedLayout: failed macOS 27 visible control restore \(plannedMove.item.logString): \(error)"
            )
            return false
        }
    }

    /// Stable termination call site; MenuBarAgent compositing leaves no blocked off-screen items to restore.
    @MainActor
    func restoreBlockedItemsToVisible() async -> Int {
        0
    }
}
