//
//  MenuBarItemManager+ControlItemOrder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit
import ThawLayout

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Arrivals whose relocation the mover refused, keyed by the identity that survives
    /// a title rekey; nothing the refusal depended on changes between passes.
    private static var refusedArrivalRelocations = [String: Date]()

    /// The tag namespace plus the hosting PID: the part of an arriving item's
    /// identity that a live title cannot churn.
    private static func arrivalIdentity(for item: MenuBarItem) -> String {
        "\(item.tag.namespace):\(item.sourcePID ?? item.ownerPID)"
    }

    /// Whether Thaw's own visible control item is stranded, parked off the
    /// menu bar band or sitting at x=-1, among the given live items.
    ///
    /// A structural defect, so it is repaired even under Manual arrangement;
    /// otherwise the icon stays invisible until relaunch. The re-lay moves
    /// only control items, never apps.
    static nonisolated func visibleControlIsStranded(among items: [MenuBarItem]) -> Bool {
        guard let visible = items.first(where: { $0.tag.matchesVisibleControlItem }) else {
            return false
        }
        return RuntimeLayoutCoordinator.visibleControlIsStranded(visible, among: items)
    }

    /// Relocates any newly appearing items that macOS placed to the left
    /// of our control items back into the visible section.
    ///
    /// Returns true if a relocation was performed.
    func relocateNewLeftmostItems(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair
    ) async -> Bool {
        guard appState != nil else { return false }

        // Before any bookkeeping, which would mark a lock-screen arrival known
        // or refused for good; untouched, it is still new after the unlock.
        if refuseMenuBarMutationWhileScreenLocked("new item relocation") {
            return false
        }

        // A refusal is forgotten once the item leaves the bar or its owner
        // relaunches under a new PID, which keeps the table bounded by what is live.
        if !Self.refusedArrivalRelocations.isEmpty {
            let liveIdentities = Set(items.map(Self.arrivalIdentity))
            Self.refusedArrivalRelocations = Self.refusedArrivalRelocations.filter {
                liveIdentities.contains($0.key)
            }
        }

        // Items reconstructed from the agent's preference, not observed. Never
        // act on one: knownItemIdentifiers never shrinks, so a bad key stays forever.
        var recoveredTags = Set<MenuBarItemTag>()
        recoveredTags = PositionStoreItemSource.recoveredTags
        // Skip items with unresolved sourcePID so the placeholder
        // "com.apple.controlcenter" namespace never enters the persisted set.
        let seedableIdentifiers = {
            items
                .filter { !$0.isControlItem && $0.sourcePID != nil && !recoveredTags.contains($0.tag) }
                .map(\.uniqueIdentifier)
        }

        if suppressNextNewLeftmostItemRelocation {
            // Seed known identifiers so these baseline items won't be treated as "new"
            // on subsequent cache passes, then clear the suppression flag.
            knownItemIdentifiers.formUnion(seedableIdentifiers())
            persistKnownItemIdentifiers()
            suppressNextNewLeftmostItemRelocation = false
            return false
        }

        // During settling, tags can carry wrong namespaces before sourcePID
        // resolves; relocating on them would move every hidden item to visible.
        // Seed identifiers only and leave placement to the settling-end restore.
        if isInStartupSettling {
            knownItemIdentifiers.formUnion(seedableIdentifiers())
            persistKnownItemIdentifiers()
            return false
        }

        // Lets the planner skip items already placed in a hidden section.
        let hiddenTags = Set(itemCache[.hidden].map(\.tag))
        let alwaysHiddenTags = Set(itemCache[.alwaysHidden].map(\.tag))

        // Computed here so planLeftmostMove stays pure over its inputs.
        let hiddenBounds = bestBounds(for: controlItems.hidden)

        let decision = LayoutSolver.planLeftmostMove(
            items: items,
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds
            ),
            savedSectionOrder: savedSectionOrder,
            knownItemIdentifiers: knownItemIdentifiers,
            hiddenTags: hiddenTags,
            alwaysHiddenTags: alwaysHiddenTags,
            effectiveNewItemsSection: effectiveNewItemsSection,
            recoveredTags: recoveredTags,
            supportsLegacySectionHiding: false
        )

        switch decision {
        case let .thawIcon(thawIcon):
            MenuBarItemManager.diagLog.info("Relocating Thaw icon \(thawIcon.logString) to visible section")
            do {
                try await move(
                    item: thawIcon,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate Thaw icon \(thawIcon.logString): \(error)")
                return false
            }
            return true

        case let .systemItem(systemItem):
            MenuBarItemManager.diagLog.info("Relocating non-hideable system item \(systemItem.logString) to visible section")
            do {
                try await move(
                    item: systemItem,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate system item \(systemItem.logString): \(error)")
                return false
            }
            return true

        case let .newHideableItem(candidate, identifierToMark):
            // Track this item so future cache cycles don't treat it as new.
            knownItemIdentifiers.insert(identifierToMark)
            persistKnownItemIdentifiers()

            // Thaw's own spacers are placed by AppKit's autosave; relocating
            // them would fight it. Checked by window owner, since the tag can
            // still be "Item-0" right after creation.
            if MenuBarSpacerManager.isSpacerTag(candidate.tag)
                || appState?.spacerManager.ownsWindowID(candidate.windowID) == true
                || ThawBarOnlyProxies.isProxyTag(candidate.tag)
                || appState?.thawBarOnlyProxies.ownsWindowID(candidate.windowID) == true
                || appState?.groupFolders.ownsWindowID(candidate.windowID) == true
            {
                MenuBarItemManager.diagLog.info(
                    "Skipping new-item relocation for Thaw spacer or proxy \(candidate.logString)"
                )
                return true
            }

            // A later item of an app already on the bar joins its siblings:
            // macOS 27 hides an app as a whole, so placing it apart would hide
            // them all, or none of it.
            if let appState,
               let siblingSection = Self.sectionOfAppSiblings(
                   of: candidate,
                   among: items,
                   section: { appState.menuBarManager.sectionController.authoredSection(for: $0.uniqueIdentifier) }
               ),
               siblingSection != effectiveNewItemsSection
            {
                MenuBarItemManager.diagLog.info(
                    "New item \(candidate.logString) joins its app's other items in \(siblingSection.logString)"
                )
                _ = appState.menuBarManager.setSection(siblingSection, items: [candidate])
                return true
            }

            let arrivalIdentity = Self.arrivalIdentity(for: candidate)
            if let refusedAt = Self.refusedArrivalRelocations[arrivalIdentity] {
                MenuBarItemManager.diagLog.debug(
                    "Not planning relocation of \(candidate.logString); refused for \(arrivalIdentity) at \(refusedAt)"
                )
                return false
            }

            let destination = newItemsMoveDestination(for: controlItems, among: items)

            MenuBarItemManager.diagLog.info(
                "Relocating new item \(candidate.logString) to \(effectiveNewItemsSection.logString)"
            )

            // Skip items with no valid bounds (transient clone windows etc.).
            guard MenuBarBackendProvider.current.relocationBounds(
                itemBounds: candidate.bounds,
                windowServerBounds: nil
            ) != nil else {
                MenuBarItemManager.diagLog.warning("Skipping relocation for \(candidate.logString); no valid bounds, likely transient")
                return false
            }

            do {
                let moved = try await move(
                    item: candidate,
                    to: destination,
                    skipInputPause: true,
                    // An arrival the host parked has no frame to grab, so the
                    // weight write is the only way to seat it.
                    allowParkedOffMenuBarSource: candidate.isParkedOffMenuBarBand(among: items)
                )
                guard moved else {
                    Self.refusedArrivalRelocations[arrivalIdentity] = Date()
                    MenuBarItemManager.diagLog.info(
                        """
                        Relocation of \(candidate.logString) was refused; not planning it again for \
                        \(arrivalIdentity) until the item leaves the bar or its owner relaunches
                        """
                    )
                    return false
                }
            } catch {
                // A thrown move repeats on every cache tick otherwise.
                Self.refusedArrivalRelocations[arrivalIdentity] = Date()
                MenuBarItemManager.diagLog.error("Failed to relocate \(candidate.logString): \(error)")
                return false
            }
            return true

        case let .noop(reason):
            switch reason {
            case .unresolvedSourcePID:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: skipping, hideable items have unresolved sourcePIDs"
                )
            case .alreadyInTarget:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: candidate already in \(effectiveNewItemsSection.logString), skipping"
                )
            case .noNewCandidate, .noLeftmostItems:
                break
            }
            return false
        }
    }

    /// Returns the best-known bounds for a menu bar item.
    private func bestBounds(for item: MenuBarItem) -> CGRect {
        Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
    }

    /// An order-independent signature of the item set plus the divider's
    /// destination. Sorted because a failed drag still shuffles items, which
    /// would otherwise reset the thrash guard every pass.
    private static func dividerSignature(
        items: [MenuBarItem],
        destination: MoveDestination
    ) -> String {
        let ids = items
            .filter { !$0.isSystemClone && !$0.isNativeOverflowControl }
            .map { "\($0.tag.namespace):\($0.tag.title)" }
            .sorted()
            .joined(separator: "|")
        let target = destination.targetItem.tag
        return "\(ids)→\(target.namespace):\(target.title)"
    }

    enum StructuralControlOrderReason {
        case ambientCacheRefresh
        case revealedLayoutRestore
        case explicitLayoutRepair
    }

    static func shouldEnforceStructuralControlOrder(
        for reason: StructuralControlOrderReason
    ) -> Bool {
        switch reason {
        case .ambientCacheRefresh:
            false
        case .revealedLayoutRestore, .explicitLayoutRepair:
            true
        }
    }

    /// Visible-section structural sequence for macOS 27 preferred-position
    /// repair. Inserts the Visible Thaw control at its saved layout slot so
    /// enforcement cannot shove it to the far-right edge after a user ⌘-drag.
    ///
    /// When saved order omits the control, only its insertion point comes from
    /// live geometry; the caller's resolved order for other items is kept.
    static func structuralVisibleSegment(
        ordinaryVisibleItems: [MenuBarItem],
        visibleControl: MenuBarItem,
        savedOrder: [String]
    ) -> [MenuBarItem] {
        let canonicalOrder = MenuBarItemTag.canonicalPersistentIdentifiers(savedOrder)
        let visibleCanonical = MenuBarItemTag.canonicalPersistentIdentifier(
            visibleControl.uniqueIdentifier
        )
        let liveSegment = MenuBarItem.sortByVisualCenterThenIdentifier(
            ordinaryVisibleItems + [visibleControl]
        )
        guard !canonicalOrder.isEmpty,
              canonicalOrder.contains(visibleCanonical)
        else {
            return RuntimeSectionController.anchoredSystemItemsTrail(in: liveSegment)
        }
        let canonicalSet = Set(canonicalOrder)
        let newlyForcedVisible = liveSegment.filter {
            !canonicalSet.contains(
                MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier)
            )
        }
        let authoredVisible = MenuBarBackendProvider.current.overflowOrderedVisibleItems(
            liveSegment.filter {
                canonicalSet.contains(
                    MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier)
                )
            },
            using: savedOrder
        )
        // Forced-visible agent children have no authored slot; put them first
        // so the trailing item (normally Thaw) stays trailing. Replaying an
        // interleaved Siri slot would undo the anchor repair.
        return RuntimeSectionController.anchoredSystemItemsTrail(in: newlyForcedVisible + authoredVisible)
    }

    /// Whether item frames are stated against more than one display's bar.
    ///
    /// macOS 27 draws the item set on every bar, and an app's AX frame names whichever bar
    /// it last laid out on. Frames from different bars share no x axis, so an order read
    /// from them is meaningless. Parked and off-band frames are ignored.
    static func framesSpanSeveralBars(_ items: [MenuBarItem], displays: [CGRect] = activeDisplayBounds()) -> Bool {
        let bandHeight = MenuBarItemAXProvider.maxItemHeight(menuBarHeight: NSScreen.tallestCachedMenuBarHeight)
        var bars = Set<Int>()
        for item in items where item.isOnScreen && item.bounds.origin.x != -1 && !item.bounds.isEmpty {
            let center = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
            if let bar = displays.firstIndex(where: { $0.contains(center) && center.y - $0.minY <= bandHeight }) {
                bars.insert(bar)
            }
        }
        return bars.count > 1
    }

    static func activeDisplayBounds() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// Left-to-right structural sequence for the position store. The Always
    /// Hidden divider is optional: macOS 27 can omit it from AX.
    static func structuralOrder(
        alwaysHiddenItems: [MenuBarItem],
        alwaysHiddenControlItem: MenuBarItem?,
        hiddenItems: [MenuBarItem],
        hiddenControlItem: MenuBarItem,
        visibleSegment: [MenuBarItem]
    ) -> [MenuBarItem] {
        alwaysHiddenItems
            + (alwaysHiddenControlItem.map { [$0] } ?? [])
            + hiddenItems
            + [hiddenControlItem]
            + visibleSegment
    }

    /// Keys for visible items with no AX child. Unmanaged, but they hold a
    /// visible slot so no divider sorts to their right. Never stale keys.
    @MainActor
    private static func opaqueVisibleRuntimePositionKeys(in items: [MenuBarItem]) -> [String] {
        // Bounded by two control weights rather than a vendor list, which
        // misses keys inside the span and lets items land between unnamed
        // fixed points on every reveal.
        PositionStoreItemSource.opaqueVisibleKeys(in: items)
    }

    /// The freshest recorded Visible-section order.
    ///
    /// savedSectionOrder tracks live geometry and pane edits. The controller's
    /// copy misses Command-drags on the real bar, so restoring it would snap
    /// items back to an old order on every reveal.
    static func freshestRecordedVisibleOrder(
        mirroredOrder: [String]?,
        controllerOrder: [String]?
    ) -> [String] {
        mirroredOrder ?? controllerOrder ?? []
    }

    func freshestRecordedVisibleOrder(
        controller: any MenuBarSectionControlling
    ) -> [String] {
        Self.freshestRecordedVisibleOrder(
            mirroredOrder: savedSectionOrder[sectionKey(for: .visible)],
            controllerOrder: controller.sectionItemOrder[.visible]
        )
    }

    /// Detects control-trio inversions and a stranded Siri on an ambient pass
    /// and schedules the debounced normalization, which waits for a quiet bar
    /// and so avoids the oscillation an inline rewrite would cause.
    func scheduleStructuralNormalizationIfControlItemsOutOfOrder(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        displayID: CGDirectDisplayID?
    ) {
        // The visible control is not part of ControlItemPair; locate it the
        // same way restoreStructuralControlOrder does.
        guard let visible = items.first(where: { $0.tag.matchesVisibleControlItem }) else {
            return
        }
        let alwaysHidden = controlItems.alwaysHidden
        let hidden = controlItems.hidden
        let siriIsMisplaced = displayID.map { display in
            Self.trailingSiriIsMisplaced(in: items.filter { CGDisplayBounds(display).intersects($0.bounds) })
        } ?? false
        guard siriIsMisplaced || !Self.controlTrioInCanonicalOrder(
            alwaysHidden: alwaysHidden,
            hidden: hidden,
            visible: visible
        ) else {
            return
        }
        let ahX = alwaysHidden?.bounds.midX
        let hX = hidden.bounds.midX
        let vX = visible.bounds.midX
        MenuBarItemManager.diagLog.info(
            "structural controls out of order on ambient pass"
                + " (Siri misplaced=\(siriIsMisplaced), AH@\(ahX.map { String(describing: $0) } ?? "nil"), H@\(hX), V@\(vX));"
                + " scheduling structural normalization"
        )
        scheduleStructuralNormalization()
    }

    static nonisolated func trailingSiriIsMisplaced(in items: [MenuBarItem]) -> Bool {
        let onBar = items.filter {
            $0.isOnScreen && $0.bounds.width >= MenuBarItemGeometry.phantomFramePeerMinimumWidth &&
                !$0.bounds.isEmpty && !$0.bounds.isInfinite &&
                !$0.isParkedOffMenuBarBand(among: items)
        }
        guard let siri = onBar.first(where: { $0.tag == .siri }) else { return false }
        return onBar.contains {
            !$0.tag.isLayoutAnchoredSystemItem && $0.bounds.midX > siri.bounds.midX
        }
    }

    /// Whether the three structural controls stand in their canonical
    /// Always-Hidden | Hidden | Visible order. Mid-X compared, so the one-pixel
    /// tie a reflow leaves behind still reads as in order.
    static nonisolated func controlTrioInCanonicalOrder(
        alwaysHidden: MenuBarItem?,
        hidden: MenuBarItem,
        visible: MenuBarItem
    ) -> Bool {
        let hiddenX = hidden.bounds.midX
        let visibleX = visible.bounds.midX
        guard let alwaysHiddenX = alwaysHidden?.bounds.midX else {
            return hiddenX <= visibleX
        }
        return alwaysHiddenX <= hiddenX && hiddenX <= visibleX
    }

    func restoreStructuralControlOrder(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        diagnosticContext: String = "structural restore"
    ) -> Bool {
        // Same stranded-control exemption from Manual as enforceControlItemOrder.
        // Startup settling still gates it: weight writes need a quiet bar.
        guard !arrangementIsManual || Self.visibleControlIsStranded(among: items),
              !isInStartupSettling else { return false }
        guard !Self.framesSpanSeveralBars(items) else {
            MenuBarItemManager.diagLog.debug("Skipping \(diagnosticContext): item frames span more than one bar")
            return false
        }
        // A batch weight write cannot fall back per item; when the agent
        // ignores the store it only refreshes the stale dictionary. The
        // reveal path physically reconciles via achievable moves instead.
        guard !menuBarAgentIgnoresPreferredPositions,
              let visible = items.first(where: { $0.tag.matchesVisibleControlItem }),
              let controller = appState?.menuBarManager.sectionController
        else {
            return false
        }
        // A move in flight owns its weights; re-laying would fail it. Deferred,
        // since every move schedules a normalization on completion.
        guard pendingPreferredPositionMoves == 0,
              layoutPublication.canPublish(generation: layoutPublication.generation)
        else {
            MenuBarItemManager.diagLog.debug(
                "Skipping structural position rewrite during a layout mutation"
            )
            return false
        }
        // A reveal or hide re-lays the bar natively; re-permuting weights now
        // churns the store and flickers Thaw's icon. The settled normalization
        // restores order once the bar is quiet.
        if appState?.menuBarManager.isRevealHideTransitionActive == true {
            MenuBarItemManager.diagLog.debug(
                "Skipping structural position rewrite: reveal/hide transition in flight"
            )
            scheduleStructuralNormalization()
            return false
        }

        // Unnamed MenuBarAgent extras resolve to stale rows, and moving them
        // loops forever; the reconciler usually renames them before this pass.
        let ordinaryItems = items.filter { !$0.isControlItem && !$0.tag.isUnnamedMenuBarAgentExtra }
        let alwaysHiddenItems = controller.ordered(
            ordinaryItems.filter { controller.authoredSection(for: $0.uniqueIdentifier) == .alwaysHidden },
            in: .alwaysHidden
        )
        let hiddenItems = controller.ordered(
            ordinaryItems.filter { controller.authoredSection(for: $0.uniqueIdentifier) == .hidden },
            in: .hidden
        )
        let visibleItems = controller.ordered(
            ordinaryItems.filter { controller.authoredSection(for: $0.uniqueIdentifier) == .visible },
            in: .visible
        )
        // Both pre-reveal and settled restoration must honor the latest
        // observed order, including native Command-drags since launch.
        let recordedVisibleOrder = freshestRecordedVisibleOrder(controller: controller)
        let visibleSegment = Self.structuralVisibleSegment(
            ordinaryVisibleItems: visibleItems,
            visibleControl: visible,
            savedOrder: recordedVisibleOrder
        )
        let desiredOrder = Self.structuralOrder(
            alwaysHiddenItems: alwaysHiddenItems,
            alwaysHiddenControlItem: controlItems.alwaysHidden,
            hiddenItems: hiddenItems,
            hiddenControlItem: controlItems.hidden,
            visibleSegment: visibleSegment
        )
        // An unseen item's slot is never permuted, so it can end up among
        // hidden icons. Naming it parks it at the end of the visible run,
        // at the cost of its exact spot, so list only keys believed visible.
        let opaqueKeys = Self.opaqueVisibleRuntimePositionKeys(in: items)
        let trace = tracePositionWrite(
            context: "\(diagnosticContext); opaqueVisibleKeys=\(opaqueKeys)",
            items: items,
            desiredOrder: desiredOrder.map(\.uniqueIdentifier)
        )
        guard !refuseMenuBarMutationWhileScreenLocked("structural order restore") else { return false }
        let reordered = MenuBarPositionStoreProvider.current.applyControlItemOrder(
            desiredOrder: desiredOrder,
            opaqueVisibleKeys: opaqueKeys,
            liveItems: items
        )
        trace?.finish(result: String(describing: reordered))
        guard !reordered.isEmpty else { return false }

        layoutPublication.invalidate()
        commitPreferredPositionWrite(controller: controller)
        MenuBarItemManager.diagLog.info(
            "macOS 27: restored structural divider order for \(reordered.count) control item(s)"
        )
        return true
    }

    @discardableResult
    func enforceControlItemOrder(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        reason: StructuralControlOrderReason
    ) async -> Bool {
        // Manual owns the app order, but a stranded control item is still
        // reseated; the re-lay below moves only control items.
        guard !arrangementIsManual || Self.visibleControlIsStranded(among: items) else { return false }
        // Ambient passes only observe; rewriting the permutation moved Thaw's
        // control and made other icons oscillate. Explicit repair may rebuild.
        if !Self.shouldEnforceStructuralControlOrder(for: reason) {
            MenuBarItemManager.diagLog.debug(
                "enforceControlItemOrder: skipping ambient structural position rewrite"
            )
            return false
        }

        let hidden = controlItems.hidden
        var didRestoreOrder = false

        // macOS 27's runtime host owns the actual control-item order. This
        // must run independently of the legacy/assertion enforcement strategy:
        // collapsed dividers are structural anchors, not draggable items.
        if restoreStructuralControlOrder(
            controlItems: controlItems,
            items: items,
            diagnosticContext: "enforceControlItemOrder reason=\(reason)"
        ) {
            didRestoreOrder = true
        }

        let experimentalSystemItemHiding = appState?.settings.advanced
            .enableExperimentalSystemItemHiding ?? false
        guard hidden.isPhysicallyOrderable(
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) else {
            // Zero-width section dividers are not ⌘-draggable on macOS 27;
            // concealment is assignment-driven instead of divider-relative.
            lastFailedDividerSignature = nil
            return didRestoreOrder
        }

        let sectionAssignment = appState?.menuBarManager.sectionController
            .sectionAssignment ?? [:]
        guard let destination = MenuBarLayoutPlannerProvider.current.dividerMoveDestination(
            items: items,
            sectionAssignment: sectionAssignment,
            controlItems: controlItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) else {
            // Nothing to enforce: clear the thrash guard so a later divergence retries.
            lastFailedDividerSignature = nil
            return didRestoreOrder
        }

        // Divider-thrash guard: an unachievable move would re-fire the drag
        // every cycle, pulling the cursor and shuffling icons while idle. Skip
        // a failed move until the layout changes; forced callers bypass it.
        let signature = Self.dividerSignature(items: items, destination: destination)
        if case .ambientCacheRefresh = reason,
           signature == lastFailedDividerSignature
        {
            return didRestoreOrder
        }

        do {
            MenuBarItemManager.diagLog.info(
                "macOS 27: moving hidden divider left of the visible section"
            )
            try await move(
                item: hidden,
                to: destination,
                skipInputPause: true,
                allowSectionBoundaryTarget: true
            )
            lastFailedDividerSignature = nil
            didRestoreOrder = true
        } catch {
            lastFailedDividerSignature = signature
            MenuBarItemManager.diagLog.error(
                "Error enforcing macOS 27 hidden divider boundary: \(error)"
            )
        }

        // Enforce always-hidden divider left of hidden divider.
        // Skip synthetic items (off-screen); only enforce when both
        // dividers have real geometry so the relative check is meaningful.
        if let alwaysHidden = controlItems.alwaysHidden,
           hidden.isOnScreen, alwaysHidden.isOnScreen,
           hidden.bounds.maxX <= alwaysHidden.bounds.minX
        {
            do {
                MenuBarItemManager.diagLog.info(
                    "macOS 27: moving always-hidden divider left of hidden divider"
                )
                try await move(
                    item: alwaysHidden,
                    to: .leftOfItem(hidden),
                    skipInputPause: true
                )
                didRestoreOrder = true
            } catch {
                MenuBarItemManager.diagLog.error(
                    "Error enforcing macOS 27 always-hidden divider order: \(error)"
                )
            }
        }
        return didRestoreOrder
    }
}
