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
               let siblingSection = AppSiblingSections.sectionOfAppSiblings(
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
            let target = destination.targetItem
            if let appState,
               NewItemRoute(
                   section: effectiveNewItemsSection,
                   destinationIsDivider: target.isControlItem && target.tag != .visibleControlItem
               ) == .assign
            {
                MenuBarItemManager.diagLog.info(
                    "Assigning new item \(candidate.logString) to \(effectiveNewItemsSection.logString)"
                )
                if let refusal = appState.menuBarManager.setSection(effectiveNewItemsSection, items: [candidate]) {
                    Self.refusedArrivalRelocations[arrivalIdentity] = Date()
                    MenuBarItemManager.diagLog.info("Assignment of \(candidate.logString) was refused: \(refusal)")
                    return false
                }
                return true
            }

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

    enum StructuralControlOrderReason {
        case revealedLayoutRestore
        case explicitLayoutRepair
    }

    static func activeDisplayBounds() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
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

    func freshestRecordedVisibleOrder(
        controller: any MenuBarSectionControlling
    ) -> [String] {
        ControlOrderRules.freshestRecordedVisibleOrder(
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
            ControlOrderRules.trailingSiriIsMisplaced(in: items.filter { CGDisplayBounds(display).intersects($0.bounds) })
        } ?? false
        guard siriIsMisplaced || !ControlOrderRules.controlTrioInCanonicalOrder(
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
        scheduleStructuralNormalization(cause: .structuralDriftObserved)
    }

    func restoreStructuralControlOrder(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        diagnosticContext: String = "structural restore",
        permit: borrowing StoreWritePermit
    ) -> Bool {
        // Same stranded-control exemption from Manual as enforceControlItemOrder.
        // Startup settling still gates it: weight writes need a quiet bar.
        guard !arrangementIsManual || ControlOrderRules.visibleControlIsStranded(among: items),
              !isInStartupSettling else { return false }
        guard !ControlOrderRules.framesSpanSeveralBars(items) else {
            MenuBarItemManager.diagLog.debug("Skipping \(diagnosticContext): item frames span more than one bar")
            return false
        }
        guard !ControlOrderRules.dividerIsOffTheBar(controlItems, among: items) else {
            MenuBarItemManager.diagLog.debug("Skipping \(diagnosticContext): the Hidden divider is parked off the bar")
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
            scheduleStructuralNormalization(cause: .revealHideTransition)
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
        let visibleSegment = ControlOrderRules.structuralVisibleSegment(
            ordinaryVisibleItems: visibleItems,
            visibleControl: visible,
            savedOrder: recordedVisibleOrder
        )
        let desiredOrder = ControlOrderRules.structuralOrder(
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
            liveItems: items,
            permit: permit
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
        reason: StructuralControlOrderReason,
        permit: borrowing StoreWritePermit
    ) async -> Bool {
        // Manual owns the app order, but a stranded control item is still
        // reseated; the re-lay below moves only control items.
        guard !arrangementIsManual || ControlOrderRules.visibleControlIsStranded(among: items) else { return false }
        let hidden = controlItems.hidden
        var didRestoreOrder = false

        // macOS 27's runtime host owns the actual control-item order. This
        // must run independently of the legacy/assertion enforcement strategy:
        // collapsed dividers are structural anchors, not draggable items.
        if restoreStructuralControlOrder(
            controlItems: controlItems,
            items: items,
            diagnosticContext: "enforceControlItemOrder reason=\(reason)",
            permit: permit
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
            didRestoreOrder = true
        } catch {
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
