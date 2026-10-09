//
//  MenuBarItemManager+RestrictionRepair.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import CoreGraphics
import MenuBarModel
import ThawCapture

// MARK: - Restriction repair

extension MenuBarItemManager {
    /// Whether the kit's restriction was rebuilt recently enough that
    /// automatic visible-section reorders should stand down. The image cache's
    /// volatility recording reads it too, since a reflow shifts every crop.
    var isWithinRestrictionReflowSettleWindow: Bool {
        guard let lastRestrictionChange = lastRestrictionChangeTimestamp else {
            return false
        }
        return lastRestrictionChange.duration(to: .now) < Self.restrictionChangeLayoutSettleWindow
    }

    /// Forgets every stranded verdict after a positions reset, since the bar
    /// they described no longer exists. Otherwise the repair keeps skipping
    /// items it gave up on before the reset.
    func forgetStrandedRepairs() {
        failureLedger.removeAll()
        boundaryRepairBreaker.rearmAll()
    }

    private func parkedSetAndBarMidY(in items: [MenuBarItem]) -> (barMidY: CGFloat?, parkedIDs: Set<CGWindowID>) {
        let barMidY = items.first(where: {
            $0.tag.matchesVisibleControlItem && $0.bounds.midY <= MenuBarItemGeometry.maxOnBarMidY
        })?.bounds.midY
            ?? items.first(where: {
                $0.isControlItem && $0.bounds.width > 8 && $0.bounds.midY <= MenuBarItemGeometry.maxOnBarMidY
            })?.bounds.midY

        let parkedIDs = Set(items.compactMap { item -> CGWindowID? in
            guard item.bounds.width > 0, item.bounds.height > 0 else { return item.windowID }
            if item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY {
                return item.windowID
            }
            guard let barMidY else { return nil }
            return abs(item.bounds.midY - barMidY) > MenuBarItemGeometry.maxDistanceFromBarMidY ? item.windowID : nil
        })

        return (barMidY, parkedIDs)
    }

    /// Internal because the visible-boundary repair pass keys its circuit
    /// breaker on the same identity.
    struct PostRestrictionRepairItemID: Hashable {
        let uniqueIdentifier: String
        let ownerPID: pid_t
    }

    /// How long a Thaw press may take to flip the active display before a
    /// display switch counts as the user's.
    private static let selfInflictedDisplayChangeWindow: Duration = .seconds(6)

    /// Marks the active display as about to change because of a Thaw press.
    func noteSelfInflictedDisplayChange() {
        selfInflictedDisplayChangeUntil = ContinuousClock.now.advanced(
            by: Self.selfInflictedDisplayChangeWindow
        )
    }

    func postRestrictionRepairItemID(for item: MenuBarItem) -> PostRestrictionRepairItemID {
        PostRestrictionRepairItemID(
            uniqueIdentifier: item.uniqueIdentifier,
            ownerPID: item.ownerPID
        )
    }

    /// Records that the kit's restriction was torn down and rebuilt.
    /// The OS reflows the whole bar; defer saved-layout re-apply until geometry settles.
    func noteRestrictionChange() {
        layoutPublication.invalidate()
        lastRestrictionChangeTimestamp = .now
        schedulePostRestrictionRepair(cause: .restrictionChanged)
    }

    func schedulePostRestrictionRepair(cause: RepairOrchestrator.Cause) {
        // Hiding still invalidates geometry, but manual arrangement never
        // schedules corrective pulses, unparking, or boundary moves.
        guard !arrangementIsManual, !isInStartupSettling, !isNotificationCenterLayoutSuspended else {
            postRestrictionRepairTask?.cancel()
            postRestrictionRepairTask = nil
            postRestrictionRepairNeedsRerun = false
            repairs.withdraw(.postRestrictionRepair)
            return
        }
        repairs.request(.postRestrictionRepair, cause: cause)
        // A repair pass re-applies the restriction and lands back here.
        // Cancelling it would escalate its in-flight write to a racing drag,
        // so coalesce into one more pass instead.
        if isRunningPostRestrictionRepair {
            postRestrictionRepairNeedsRerun = true
            return
        }
        postRestrictionRepairTask?.cancel()
        postRestrictionRepairNeedsRerun = false
        postRestrictionRepairTask = Task { @MainActor [weak self] in
            // Nudging MenuBarAgent mid-reflow parks collateral items at y≈1413;
            // the wait also absorbs multi-hide bursts.
            do {
                try await Task.sleep(for: .milliseconds(1200))
            } catch {
                return
            }
            guard let self else { return }
            self.isRunningPostRestrictionRepair = true
            defer {
                self.isRunningPostRestrictionRepair = false
                self.postRestrictionRepairNeedsRerun = false
            }
            guard var stillParked = await self.repairVisibleLayoutInRepairLane() else { return }
            var poll = 0
            while poll < 4, stillParked || self.postRestrictionRepairNeedsRerun {
                self.postRestrictionRepairNeedsRerun = false
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let parked = await self.repairVisibleLayoutInRepairLane() else { return }
                stillParked = parked
                poll += 1
            }
        }
    }

    /// One repair pass inside the lane. The lane is given back between polls
    /// so the passes queued behind it are not held up by the wait.
    /// Nil when the task was superseded while it queued.
    private func repairVisibleLayoutInRepairLane() async -> Bool? {
        let read: () async -> PostRestrictionReading? = {
            // A pass that will return at once must not take a picture first.
            guard !self.arrangementIsManual, !self.isInStartupSettling, !self.isNotificationCenterLayoutSuspended,
                  self.appState?.menuBarManager.shouldDeferBarMutation != true
            else { return nil }
            let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID)
            return PostRestrictionReading(items: items, displayID: displayID, barCapture: capture)
        }
        return await RepairTurn.run(.postRestrictionRepair, on: repairs, read: read) { items, permit, writing in
            await self.repairVisibleLayoutAfterRestrictionChange(readBeforeTurn: items, permit: permit, writing: writing)
        }
    }

    /// Re-composites allowed menu bar items after assertion reflow collateral.
    /// On-band AX ghosts (tooltip works, icon missing) are fixed by pulsing the
    /// assertion; only truly parked items (y≈1400+) get a synthetic unpark.
    @discardableResult
    private func repairVisibleLayoutAfterRestrictionChange(
        readBeforeTurn: PostRestrictionReading? = nil,
        permit: consuming StoreWritePermit,
        writing: RepairTurn.Writing
    ) async -> Bool {
        guard !arrangementIsManual, !isInStartupSettling, !Task.isCancelled,
              !isNotificationCenterLayoutSuspended
        else { return false }
        if appState?.menuBarManager.shouldDeferBarMutation == true {
            MenuBarItemManager.diagLog.debug(
                "post-restriction repair: deferred; native menu bar unavailable/transitioning"
            )
            return true
        }

        guard let appState else {
            MenuBarItemManager.diagLog.debug("post-restriction repair: skipped, missing app state")
            return false
        }
        let controller = appState.menuBarManager.sectionController

        var liveItems = if let readBeforeTurn { readBeforeTurn.items } else { await MenuBarItem.getMenuBarItems(option: .activeSpace) }
        guard !arrangementIsManual, !Task.isCancelled else { return false }
        // Nothing is written yet. Step aside for the user; the next poll retries.
        guard !repairs.userWorkIsWaiting else { return true }

        // A pulse can re-blank hiding-unsupported apps, so pulse only when
        // supported visible items are parked or blank.
        let displayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        let liveItemIDs = Set(liveItems.map(postRestrictionRepairItemID(for:)))
        postRestrictionUnrepairableItemIDs.formIntersection(liveItemIDs)
        boundaryRepairBreaker.prune(keeping: liveItemIDs)

        // A strand given up on in an earlier launch starts this one suppressed,
        // instead of repeating the failed passes that rewrite its neighbours'
        // order. Seeded once per item; the cooldown still re-arms it.
        let carriedStrands = liveItems.filter { item in
            let id = postRestrictionRepairItemID(for: item)
            return !seededStrandedRepairItemIDs.contains(id) && failureLedger.strandedMarked(item)
        }
        for item in carriedStrands {
            let id = postRestrictionRepairItemID(for: item)
            seededStrandedRepairItemIDs.insert(id)
            boundaryRepairBreaker.suppress(id)
        }
        if !carriedStrands.isEmpty {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: carrying \(carriedStrands.count) stranded item(s) over from an earlier launch: " +
                    carriedStrands.map(\.logString).joined(separator: ", ")
            )
        }

        // A display change re-seats the bar, so suppressed strands re-arm.
        // Not when Thaw's own press activated another display: that would
        // re-ladder the band under an open menu.
        if let last = lastBoundaryRepairDisplayID, last != displayID {
            if let until = selfInflictedDisplayChangeUntil, ContinuousClock.now < until {
                MenuBarItemManager.diagLog.debug(
                    "post-restriction repair: display change came from Thaw's own press; not re-arming strands"
                )
                selfInflictedDisplayChangeUntil = nil
            } else {
                if boundaryRepairBreaker.suppressedCount > 0 {
                    MenuBarItemManager.diagLog.info(
                        "post-restriction repair: display changed; re-arming " +
                            "\(boundaryRepairBreaker.suppressedCount) suppressed boundary strand(s)"
                    )
                }
                boundaryRepairBreaker.rearmAll()
            }
        }
        lastBoundaryRepairDisplayID = displayID

        // An expired suppression re-arms: the strand may have been fighting a
        // transient writer that has since settled.
        let rearmed = boundaryRepairBreaker.rearmExpired(
            now: Date(), cooldown: MenuBarItemManager.boundaryRepairSuppressionCooldown
        )
        if rearmed > 0 {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: suppression cooldown elapsed; re-arming \(rearmed) boundary strand(s)"
            )
        }

        // Suppressed strands are excluded: a pulse cannot fix them and only
        // re-runs the expensive blank-detection captures.
        let pulseCandidates = liveItems.filter {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                !postRestrictionUnrepairableItemIDs.contains(postRestrictionRepairItemID(for: $0)) &&
                !boundaryRepairBreaker.isSuppressed(postRestrictionRepairItemID(for: $0)) &&
                !failureLedger.cannotCompleteMarked($0) &&
                controller.section(for: $0) == .visible
        }
        var liveParkedIDs = parkedSetAndBarMidY(in: liveItems).parkedIDs
        let prePulseParked = pulseCandidates.filter { liveParkedIDs.contains($0.windowID) }
        let prePulseOnBand = pulseCandidates.filter { !liveParkedIDs.contains($0.windowID) }
        // The picture came with the reading when there is one, so the lane does not wait on a capture.
        let prePulseBlank = if let readBeforeTurn, readBeforeTurn.covers(displayID) {
            readBeforeTurn.blankTags(among: prePulseOnBand)
        } else {
            await appState.imageCache.itemsRenderingBlank(among: prePulseOnBand, displayID: displayID)
        }
        guard !arrangementIsManual, !Task.isCancelled else { return false }
        // Without a reading the blank check took a capture and can be slow. Still nothing written.
        guard !writing.userWorkIsWaiting else { return true }
        let needsPulse = !prePulseParked.isEmpty || !prePulseBlank.isEmpty

        if needsPulse, !Task.isCancelled, controller.pulseRestrictionAfterReflow(liveItems: liveItems) {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: pulsed assertion for MenuBarAgent re-composite " +
                    "(prePulseParked=\(prePulseParked.count), prePulseBlank=\(prePulseBlank.count))"
            )
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return false
            }
            liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard !arrangementIsManual, !Task.isCancelled else { return false }
            liveParkedIDs = parkedSetAndBarMidY(in: liveItems).parkedIDs
        } else if !needsPulse {
            MenuBarItemManager.diagLog.debug(
                "post-restriction repair: pulse skipped, no non-hiding-unsupported items parked or blank"
            )
        }

        // Denylisted hiding-unsupported items are excluded from synthetic drag
        // and retry signals. Their glyphs may transiently blank on assertion
        // reflows, but repeatedly pulsing can make that worse.
        var failedUnparkIDs = Set<CGWindowID>()
        let parkedVisible = liveItems.filter {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                !postRestrictionUnrepairableItemIDs.contains(postRestrictionRepairItemID(for: $0)) &&
                !failureLedger.cannotCompleteMarked($0) &&
                controller.section(for: $0) == .visible &&
                liveParkedIDs.contains($0.windowID)
        }
        // x == -1 means macOS had no room to draw the item, which a move
        // cannot fix. The overflow budget conceals from the left until they fit.
        let droppedOffBar = parkedVisible.filter { $0.bounds.minX == MenuBarItemGeometry.transientSentinelX }
        if !droppedOffBar.isEmpty {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: \(droppedOffBar.count) visible item(s) have no room on the bar; " +
                    "leaving them to the overflow budget: " + droppedOffBar.map(\.logString).joined(separator: ", ")
            )
        }
        let unparkable = parkedVisible.filter { $0.bounds.minX != MenuBarItemGeometry.transientSentinelX }
        if !unparkable.isEmpty, let anchor = unparkAnchorAmong(liveItems: liveItems, controller: controller) {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: unparking \(unparkable.count) off-band item(s) " +
                    "using anchor \(anchor.logString)"
            )
            for item in MenuBarItem.sortByVisualCenter(unparkable) {
                guard !arrangementIsManual, !Task.isCancelled else { return false }
                // Each unpark is a move of its own, so the pass can stop between them.
                guard !writing.userWorkIsWaiting else {
                    MenuBarItemManager.diagLog.debug("post-restriction repair: stepping aside for user work between unparks")
                    return true
                }
                let freshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                guard !arrangementIsManual, !Task.isCancelled else { return false }
                guard let currentAnchor = unparkAnchorAmong(liveItems: freshItems, controller: controller) else {
                    break
                }
                do {
                    try await unparkVisibleItemAfterRestrictionReflow(
                        item: item,
                        anchor: currentAnchor,
                        anchorFallbacks: unparkAnchorFallbacks(for: currentAnchor, among: freshItems)
                    )
                } catch EventError.destinationAnchorLost {
                    guard !arrangementIsManual, !Task.isCancelled else { return false }
                    failedUnparkIDs.insert(item.windowID)
                    postRestrictionUnrepairableItemIDs.insert(postRestrictionRepairItemID(for: item))
                    // Every anchor vanished mid-drop, which says nothing about
                    // the item, so suppress for the session only.
                    MenuBarItemManager.diagLog.warning(
                        "post-restriction repair: anchors for \(item.logString) vanished mid-drop; skipping without a persisted verdict"
                    )
                } catch let EventError.itemNotMovable(_, refusal) {
                    guard !arrangementIsManual, !Task.isCancelled else { return false }
                    failedUnparkIDs.insert(item.windowID)
                    postRestrictionUnrepairableItemIDs.insert(postRestrictionRepairItemID(for: item))
                    // Persist the verdict across relaunch, except for a refusal
                    // the user can lift in Settings.
                    if refusal == .requiresExperimentalHiding {
                        MenuBarItemManager.diagLog.info(
                            "post-restriction repair: \(item.logString) refused pending the system-item-hiding gate; \"won't move\" verdict not persisted"
                        )
                    } else {
                        failureLedger.recordFailure(for: item, kind: .cannotComplete)
                        MenuBarItemManager.diagLog.warning(
                            "post-restriction repair: suppressing future repair pulses for unmovable \(item.logString)" +
                                " (reason: \(refusal.map(String.init(describing:)) ?? "none"))"
                        )
                    }
                } catch EventError.cannotComplete {
                    guard !arrangementIsManual, !Task.isCancelled else { return false }
                    failedUnparkIDs.insert(item.windowID)
                    postRestrictionUnrepairableItemIDs.insert(postRestrictionRepairItemID(for: item))
                    failureLedger.recordFailure(for: item, kind: .cannotComplete)
                    MenuBarItemManager.diagLog.warning(
                        "post-restriction repair: suppressing future repair pulses after move could not complete for \(item.logString)"
                    )
                } catch is CancellationError {
                    return false
                } catch {
                    guard !arrangementIsManual, !Task.isCancelled else { return false }
                    failedUnparkIDs.insert(item.windowID)
                    postRestrictionUnrepairableItemIDs.insert(postRestrictionRepairItemID(for: item))
                    // A one-off error is not a persisted verdict, it may not
                    // mean the item is unmovable.
                    failureLedger.recordFailure(for: item, kind: .other)
                    MenuBarItemManager.diagLog.warning(
                        "post-restriction repair: suppressing future repair pulses after move failed for \(item.logString): \(error)"
                    )
                }
            }
        } else if unparkable.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "post-restriction repair: no off-band parked items to pulse"
            )
        }

        // An item dragged out of a hidden section is still seated among the
        // hidden icons; the pane drag cannot move it while concealed, so this
        // pass places it.
        var strandNeedsRetry = false
        guard !writing.userWorkIsWaiting else {
            MenuBarItemManager.diagLog.debug("post-restriction repair: stepping aside for user work before the strand repair")
            return true
        }
        do {
            let controlItemWindowIDs = liveControlItemWindowIDs()
            let strand = await repairVisibleItemsSeatedAmongHidden(
                liveItems: liveItems,
                controller: controller,
                experimentalSystemItemHiding: appState.settings.advanced.enableExperimentalSystemItemHiding,
                hiddenControlItemWindowID: controlItemWindowIDs.hidden,
                alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden,
                whileRevealing: nil,
                permit: permit
            )
            guard !strand.aborted else { return false }
            liveItems = strand.items
            strandNeedsRetry = strand.strandsRemaining
            if strandNeedsRetry {
                MenuBarItemManager.diagLog.info(
                    "post-restriction repair: visible boundary strands remain; re-entering"
                )
            }
        }

        // Every write is done. What follows reads the result, so the next pass need not wait for it.
        writing.end(permit)

        await cacheItemsRegardless(skipRecentMoveCheck: true, skipSavedLayoutApply: true)
        guard !Task.isCancelled else { return false }
        await appState.imageCache.refreshAfterReorder()
        guard !Task.isCancelled else { return false }
        appState.hidEventManager.refreshMenuBarItemBoundsLookup()

        // No pulse, so nothing to confirm and no second read of the bar. A strand attempted
        // above keeps the loop alive, since the agent needs a beat to re-seat it.
        guard needsPulse else {
            return strandNeedsRetry
        }

        let afterItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard !Task.isCancelled else { return false }
        let (_, afterParkedIDs) = parkedSetAndBarMidY(in: afterItems)
        // Hiding-unsupported items are excluded: their transient blanks would
        // drive repeated pulses.
        let onBandVisibleItems = afterItems.filter {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                !boundaryRepairBreaker.isSuppressed(postRestrictionRepairItemID(for: $0)) &&
                controller.section(for: $0) == .visible &&
                !afterParkedIDs.contains($0.windowID)
        }

        // Confirm the pulse resolved the blanks; true re-enters the retry loop.
        let blankTags = await appState.imageCache.itemsRenderingBlank(
            among: onBandVisibleItems,
            displayID: displayID
        )
        if !blankTags.isEmpty {
            MenuBarItemManager.diagLog.info(
                "post-restriction repair: \(blankTags.count) on-band item(s) still blank after pulse, will retry"
            )
        }

        let stillParked = afterItems.contains {
            !$0.isControlItem &&
                !$0.tag.isHidingUnsupported &&
                !postRestrictionUnrepairableItemIDs.contains(postRestrictionRepairItemID(for: $0)) &&
                !boundaryRepairBreaker.isSuppressed(postRestrictionRepairItemID(for: $0)) &&
                !failureLedger.cannotCompleteMarked($0) &&
                !failedUnparkIDs.contains($0.windowID) &&
                controller.section(for: $0) == .visible &&
                afterParkedIDs.contains($0.windowID)
        }

        return stillParked || !blankTags.isEmpty || strandNeedsRetry
    }

    private func unparkAnchorAmong(
        liveItems: [MenuBarItem],
        controller: any MenuBarSectionControlling
    ) -> MenuBarItem? {
        if let control = liveItems.first(where: {
            $0.tag.matchesVisibleControlItem && !$0.isParkedOffMenuBarBand(among: liveItems)
        }) {
            return control
        }
        return liveItems
            .filter {
                !$0.isControlItem &&
                    controller.section(for: $0) == .visible &&
                    !$0.isParkedOffMenuBarBand(among: liveItems)
            }
            .max(by: { $0.bounds.midX < $1.bounds.midX })
    }

    /// The anchor's nearest orderable neighbours, taken from the same scan
    /// because a later scan may no longer be trustworthy.
    private func unparkAnchorFallbacks(
        for anchor: MenuBarItem,
        among liveItems: [MenuBarItem]
    ) -> [MoveDestination] {
        let experimentalSystemItemHiding = appState?.settings.advanced
            .enableExperimentalSystemItemHiding ?? false
        let ordered = MenuBarItem.sortByLeadingEdge(
            liveItems.filter {
                !$0.isSystemClone &&
                    !$0.isNativeOverflowControl &&
                    !$0.isControlItem &&
                    $0.bounds.width > 0 &&
                    !$0.isParkedOffMenuBarBand(among: liveItems)
            }
        )
        guard let anchorIndex = ordered.firstIndex(where: {
            $0.uniqueIdentifier == anchor.uniqueIdentifier
        }) else {
            return []
        }

        var chain = [MoveDestination]()
        if let left = ordered[..<anchorIndex].last(where: {
            $0.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding)
        }) {
            chain.append(.rightOfItem(left))
        }
        if anchorIndex + 1 < ordered.count,
           let right = ordered[(anchorIndex + 1)...].first(where: {
               $0.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding)
           })
        {
            chain.append(.leftOfItem(right))
        }
        return chain
    }

    private func unparkVisibleItemAfterRestrictionReflow(
        item: MenuBarItem,
        anchor: MenuBarItem,
        anchorFallbacks: [MoveDestination] = []
    ) async throws {
        MenuBarItemManager.diagLog.info(
            "post-restriction repair: recovering \(item.logString) to left of \(anchor.logString)"
        )
        try await move(
            item: item,
            to: .leftOfItem(anchor),
            skipInputPause: true,
            allowParkedOffMenuBarSource: true,
            anchorFallbacks: anchorFallbacks
        )
    }
}
