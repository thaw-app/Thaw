//
//  MenuBarItemManager+Triggers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Trigger ownership of item placement.
///
/// A trigger-held item's placement must not be persisted or dragged back by
/// the reconciler. Matching tolerates `:N` suffix drift while it's held.
extension MenuBarItemManager {
    /// Updates the set of items whose temporary placement is currently owned
    /// by conditional triggers.
    ///
    /// Removing an identifier schedules a cache cycle past `move`'s
    /// five-second cooldown, so the reconciler restores the saved layout
    /// without fighting an in-flight drag.
    func setTriggerControlledItemIdentifiers(_ identifiers: Set<String>) {
        guard triggerControlledItemIdentifiers != identifiers else { return }

        // Not via the weak `appState`: a nil hop would empty both sets and
        // report drifted, still-controlled items as released.
        let managedItems = itemCache.managedItems
        let knownBaseIdentifiers = Set(managedItems.map(\.tag.stableIdentifierBase))
        let knownLiveIdentifiers = Set(managedItems.map(\.uniqueIdentifier))
        let releasedIdentifiers = Self.releasedTriggerIdentifiers(
            previousIdentifiers: triggerControlledItemIdentifiers,
            currentIdentifiers: identifiers,
            knownBaseIdentifiers: knownBaseIdentifiers,
            knownLiveIdentifiers: knownLiveIdentifiers
        )
        let identifiersRequiringRestoration = Self.triggerReleaseIdentifiersRequiringRestoration(
            releasedIdentifiers,
            savedSectionOrder: savedSectionOrder
        )
        triggerControlledItemIdentifiers = identifiers
        // A reactivated condition cancels its pending restore; the item stays
        // persistence-protected.
        triggerLayoutRestorationItemIdentifiers.subtract(
            Self.releasedTriggerRestorationIdentifiersToClear(
                reactivatedIdentifiers: identifiers,
                pendingRestorationIdentifiers: triggerLayoutRestorationItemIdentifiers,
                knownBaseIdentifiers: knownBaseIdentifiers,
                knownLiveIdentifiers: knownLiveIdentifiers
            )
        )
        // Items with no saved position have nothing to restore; shielding
        // them would stop their first baseline from ever being recorded.
        triggerLayoutRestorationItemIdentifiers.formUnion(identifiersRequiringRestoration)
        MenuBarItemManager.diagLog.debug(
            "Updated trigger-controlled item set: active=\(identifiers.count), released=\(releasedIdentifiers.count), restorable=\(identifiersRequiringRestoration.count), pendingRestore=\(triggerLayoutRestorationItemIdentifiers.count)"
        )

        guard !releasedIdentifiers.isEmpty else { return }
        // Coalesce a burst of releases; replacing the task restarts the wait.
        triggerReleaseRecacheTask?.cancel()
        triggerReleaseRecacheTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            await self.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
            // Don't clear the handle: it may belong to a newer release's task.
        }
    }

    /// Returns trigger targets that were genuinely released. An active item
    /// whose stable instance index changed remains continuously trigger-owned;
    /// it must not be placed on the delayed saved-layout restoration path.
    static nonisolated func releasedTriggerIdentifiers(
        previousIdentifiers: Set<String>,
        currentIdentifiers: Set<String>,
        knownBaseIdentifiers: Set<String>,
        knownLiveIdentifiers: Set<String> = []
    ) -> Set<String> {
        let rawReleasedIdentifiers = previousIdentifiers.subtracting(currentIdentifiers)
        let continuouslyControlledIdentifiers = currentIdentifiers.reduce(into: Set<String>()) { result, identifier in
            result.formUnion(
                triggerProtectionIdentifiers(
                    matching: identifier,
                    in: rawReleasedIdentifiers,
                    knownBaseIdentifiers: knownBaseIdentifiers,
                    knownLiveIdentifiers: knownLiveIdentifiers
                )
            )
        }
        return rawReleasedIdentifiers.subtracting(continuouslyControlledIdentifiers)
    }

    /// Returns only released trigger targets that have a persisted section and
    /// order to recover.
    static nonisolated func triggerReleaseIdentifiersRequiringRestoration(
        _ releasedIdentifiers: Set<String>,
        savedSectionOrder: [String: [String]],
        knownBaseIdentifiers _: Set<String> = []
    ) -> Set<String> {
        Set(releasedIdentifiers.filter {
            LayoutSolver.savedPositionByBaseID(
                for: $0,
                in: savedSectionOrder
            ) != nil
        })
    }

    /// Returns the protected identifiers that represent a live trigger
    /// target. Exact identifiers win. A suffix-drift fallback is safe only
    /// when exactly one protected target shares the namespace/title base;
    /// otherwise two same-title instances cannot be distinguished.
    static nonisolated func triggerProtectionIdentifiers(
        matching liveIdentifier: String,
        in protectedIdentifiers: Set<String>,
        knownBaseIdentifiers: Set<String> = [],
        knownLiveIdentifiers: Set<String> = []
    ) -> Set<String> {
        if protectedIdentifiers.contains(liveIdentifier) {
            return [liveIdentifier]
        }
        guard let liveBaseID = MenuBarItemTag.resolvedBaseIdentifier(
            for: liveIdentifier,
            knownBaseIdentifiers: knownBaseIdentifiers
        ) else {
            return []
        }
        let baseMatches = protectedIdentifiers.filter { identifier in
            MenuBarItemTag.resolvedBaseIdentifier(
                for: identifier,
                knownBaseIdentifiers: knownBaseIdentifiers
            ) == liveBaseID
        }
        if !knownLiveIdentifiers.isEmpty {
            let liveCandidates = knownLiveIdentifiers.filter { identifier in
                MenuBarItemTag.resolvedBaseIdentifier(
                    for: identifier,
                    knownBaseIdentifiers: knownBaseIdentifiers
                ) == liveBaseID
            }
            guard liveCandidates.count == 1 else { return [] }
        }
        return baseMatches.count == 1 ? Set(baseMatches) : []
    }

    /// The live UIDs in `uids` that a trigger currently owns or is still
    /// restoring, resolved drift-tolerantly against `items`.
    ///
    /// Trigger-owned items are absent from the desired layout, so without
    /// this they read as unmanaged arrivals.
    func triggerProtectedUIDs(among uids: [String], items: [MenuBarItem]) -> Set<String> {
        let protectedIdentifiers = triggerControlledItemIdentifiers
            .union(triggerLayoutRestorationItemIdentifiers)
        guard !protectedIdentifiers.isEmpty else { return [] }
        let knownBaseIdentifiers = Set(items.map(\.tag.stableIdentifierBase))
        let knownLiveIdentifiers = Set(items.map(\.uniqueIdentifier))
        return Set(
            uids.filter {
                Self.isTriggerProtected(
                    $0,
                    by: protectedIdentifiers,
                    knownBaseIdentifiers: knownBaseIdentifiers,
                    knownLiveIdentifiers: knownLiveIdentifiers
                )
            }
        )
    }

    static nonisolated func isTriggerProtected(
        _ liveIdentifier: String,
        by protectedIdentifiers: Set<String>,
        knownBaseIdentifiers: Set<String> = [],
        knownLiveIdentifiers: Set<String> = []
    ) -> Bool {
        !triggerProtectionIdentifiers(
            matching: liveIdentifier,
            in: protectedIdentifiers,
            knownBaseIdentifiers: knownBaseIdentifiers,
            knownLiveIdentifiers: knownLiveIdentifiers
        ).isEmpty
    }

    /// Removes currently trigger-owned items from a desired saved order, so
    /// a saved-layout apply leaves them alone until release.
    static nonisolated func savedOrderExcludingTriggerControlledIdentifiers(
        _ savedOrder: [String: [String]],
        controlledIdentifiers: Set<String>,
        knownBaseIdentifiers: Set<String>,
        knownLiveIdentifiers: Set<String>
    ) -> [String: [String]] {
        guard !controlledIdentifiers.isEmpty else { return savedOrder }
        return savedOrder.mapValues { identifiers in
            identifiers.filter {
                !isTriggerProtected(
                    $0,
                    by: controlledIdentifiers,
                    knownBaseIdentifiers: knownBaseIdentifiers,
                    knownLiveIdentifiers: knownLiveIdentifiers
                )
            }
        }
    }

    /// Identifies pending release shields superseded by a newly active
    /// trigger, using the same drift-tolerant matcher as persistence.
    static nonisolated func releasedTriggerRestorationIdentifiersToClear(
        reactivatedIdentifiers: Set<String>,
        pendingRestorationIdentifiers: Set<String>,
        knownBaseIdentifiers: Set<String> = [],
        knownLiveIdentifiers: Set<String> = []
    ) -> Set<String> {
        reactivatedIdentifiers.reduce(into: Set<String>()) { result, identifier in
            result.formUnion(
                triggerProtectionIdentifiers(
                    matching: identifier,
                    in: pendingRestorationIdentifiers,
                    knownBaseIdentifiers: knownBaseIdentifiers,
                    knownLiveIdentifiers: knownLiveIdentifiers
                )
            )
        }
    }

    enum TriggerMoveResult {
        /// A synthetic move was performed and verified.
        case moved
        /// The item was already in the requested section.
        case alreadyInSection
        /// The item or its controls are unavailable right now.
        case unavailable
        /// A bulk layout operation is in flight; retry after it settles.
        case deferred
        /// The move was attempted but did not complete.
        case failed
    }

    /// Moves the menu bar item identified by the given stable tag identifier
    /// into the given section, if the item is present and not already there.
    ///
    /// - Returns: A ``TriggerMoveResult`` describing whether the move
    ///   happened, was unnecessary, should be retried later, or failed.
    @discardableResult
    func moveItem(
        withTagIdentifier tagIdentifier: String,
        toSection section: MenuBarSection.Name,
        options: MoveOptions = .init(requiredInputPause: .milliseconds(50))
    ) async -> TriggerMoveResult {
        guard let appState else { return .unavailable }
        guard !isResettingLayout,
              !isRestoringItemOrder,
              !isApplyingProfileLayout,
              !isBulkApplyInProgress
        else {
            MenuBarItemManager.diagLog.debug(
                "moveItem(trigger): deferring \(tagIdentifier) while a bulk layout operation is active"
            )
            return .deferred
        }
        guard options.shouldProceed?() ?? true else { return .deferred }

        // Drop transient WindowServer duplicates.
        var items = await MenuBarItem
            .getMenuBarItems(on: nil, option: .activeSpace)
            .filter { !$0.isSystemClone }

        // Resolve the target before ControlItemPair consumes the control
        // items from the list. Control items are never trigger targets.
        guard let target = items.first(where: { $0.tag.tagIdentifier == tagIdentifier }) else {
            let availableItems = items
                .filter { !$0.isControlItem }
                .prefix(12)
                .map(\.logString)
            MenuBarItemManager.diagLog.debug(
                "moveItem(trigger): no item matches identifier \(tagIdentifier). Available non-control items: \(availableItems)"
            )
            return .unavailable
        }
        guard target.isMovable else {
            MenuBarItemManager.diagLog.debug("moveItem(trigger): \(target.logString) is not movable")
            return .unavailable
        }
        if section != .visible, !target.canBeHidden {
            MenuBarItemManager.diagLog.debug("moveItem(trigger): \(target.logString) cannot be hidden")
            return .unavailable
        }

        let hiddenControlItemWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenControlItemWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
        ) else {
            MenuBarItemManager.diagLog.warning("moveItem(trigger): missing control items; cannot move \(target.logString)")
            return .deferred
        }

        // Fall back to the hidden section when always-hidden is requested
        // but unavailable (section disabled or no control item present).
        var resolvedSection = section
        if resolvedSection == .alwaysHidden,
           controlItems.alwaysHidden == nil || appState.settings.advanced.enableAlwaysHiddenSection == false
        {
            resolvedSection = .hidden
        }

        let displayID = Bridging.getActiveMenuBarDisplayID()
        var context = CacheContext(controlItems: controlItems, displayID: displayID)
        let currentSection = context.findSection(for: target)
        if currentSection == resolvedSection {
            MenuBarItemManager.diagLog.info(
                "moveItem(trigger): already in \(resolvedSection.logString), skipping \(target.logString)"
            )
            return .alreadyInSection
        }

        let destination = LayoutReconciler.boundaryDestination(for: resolvedSection, controlItems: controlItems)
        MenuBarItemManager.diagLog.info(
            """
            moveItem(trigger): planning move tagIdentifier=\(tagIdentifier) \
            currentSection=\(currentSection?.logString ?? "nil") requestedSection=\(section.logString) \
            resolvedSection=\(resolvedSection.logString) destination=\(destination.logString) \
            target=\(target.logString)
            """
        )
        do {
            try await move(
                item: target,
                to: destination,
                on: displayID,
                skipInputPause: options.requiredInputPause == .zero,
                options: options
            )
            MenuBarItemManager.diagLog.info("moveItem(trigger): moved \(target.logString) to \(resolvedSection.logString)")
            return .moved
        } catch EventError.inputPauseTimedOut, EventError.moveSuperseded {
            MenuBarItemManager.diagLog.debug(
                "moveItem(trigger): deferred stale or input-busy move for \(target.logString)"
            )
            return .deferred
        } catch {
            MenuBarItemManager.diagLog.error(
                "moveItem(trigger): failed to move to \(resolvedSection.logString) via \(destination.logString): \(target.logString); error=\(error)"
            )
            return .failed
        }
    }
}
