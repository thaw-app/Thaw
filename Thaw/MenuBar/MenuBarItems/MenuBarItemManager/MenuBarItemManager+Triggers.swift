//
//  MenuBarItemManager+Triggers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Trigger ownership of item placement.
///
/// While a conditional trigger holds an item, that item's live placement is
/// not the user's layout: it must neither be persisted as a user edit nor be
/// dragged back by the saved-layout reconciler. The identifier bookkeeping
/// here is instance-drift tolerant, because an item's `:N` suffix can change
/// while a trigger owns it.
extension MenuBarItemManager {

    /// Updates the set of items whose temporary placement is currently owned
    /// by conditional triggers.
    ///
    /// Removing an identifier intentionally schedules a later cache cycle:
    /// `move` has a five-second saved-layout cooldown, so waiting past it lets
    /// the normal reconciler restore the user's saved section and ordering
    /// without fighting an in-flight synthetic drag.
    func setTriggerControlledItemIdentifiers(_ identifiers: Set<String>) {
        guard triggerControlledItemIdentifiers != identifiers else { return }

        // Read `itemCache` directly. This extension is on `MenuBarItemManager`,
        // so `appState?.itemManager` only resolves back to `self` -- but
        // `appState` is weak, and a nil hop would empty both sets. Every
        // suffixed identifier would then fail to resolve to a base, degrading
        // release detection to exact matching and reporting a drifted but
        // still-controlled item as released.
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
            savedSectionOrder: savedSectionOrder,
            knownBaseIdentifiers: knownBaseIdentifiers
        )
        triggerControlledItemIdentifiers = identifiers
        // A condition can become active again before the delayed restore gets
        // a chance to run. In that case its old release must no longer force a
        // replay, but the still-active item remains persistence-protected.
        triggerLayoutRestorationItemIdentifiers.subtract(
            Self.releasedTriggerRestorationIdentifiersToClear(
                reactivatedIdentifiers: identifiers,
                pendingRestorationIdentifiers: triggerLayoutRestorationItemIdentifiers,
                knownBaseIdentifiers: knownBaseIdentifiers,
                knownLiveIdentifiers: knownLiveIdentifiers
            )
        )
        // An item with no saved position has no durable placement to restore.
        // Keeping it shielded would leave it at its trigger destination
        // indefinitely while another trigger remains active, and would stop
        // the next cache cycle from ever recording its first real baseline.
        // Let that item enter normal persistence immediately; only saved
        // targets need an anchor-restoration pass.
        triggerLayoutRestorationItemIdentifiers.formUnion(identifiersRequiringRestoration)
        MenuBarItemManager.diagLog.debug(
            "Updated trigger-controlled item set: active=\(identifiers.count), released=\(releasedIdentifiers.count), restorable=\(identifiersRequiringRestoration.count), pendingRestore=\(triggerLayoutRestorationItemIdentifiers.count)"
        )

        guard !releasedIdentifiers.isEmpty else { return }
        // Coalesce: a burst of releases should wait once, not stack one task
        // per release. Replacing the pending task also restarts the cooldown,
        // which is what the later releases need anyway.
        triggerReleaseRecacheTask?.cancel()
        triggerReleaseRecacheTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            await self.cacheItemsRegardless(skipRecentMoveCheck: true)
            // The handle is deliberately left in place: by the time this runs,
            // it may already have been replaced by a newer release's task, and
            // clearing it would drop that one's cancellation handle. A settled
            // handle is harmless -- cancelling a finished task is a no-op.
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
    /// order to recover. This is pure so the no-baseline behavior remains
    /// independently testable from the WindowServer move pipeline.
    static nonisolated func triggerReleaseIdentifiersRequiringRestoration(
        _ releasedIdentifiers: Set<String>,
        savedSectionOrder: [String: [String]],
        knownBaseIdentifiers: Set<String> = []
    ) -> Set<String> {
        Set(releasedIdentifiers.filter {
            // Upstream's `savedPositionByBaseID` does its own canonical
            // base matching and takes no `knownBaseIdentifiers`.
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
    /// Callers that classify items against the desired layout need this:
    /// a trigger-owned item is deliberately absent from the desired layout,
    /// so without excluding it explicitly it reads as an unmanaged arrival.
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

    /// Removes currently trigger-owned items from a desired saved order.
    /// Their temporary section belongs to the trigger until release, so a
    /// saved-layout apply must leave them untouched even when it is restoring
    /// unrelated items in the same pass.
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
    /// trigger. Instance suffixes may have drifted while the item relaunched,
    /// so this deliberately uses the same unambiguous protection matcher as
    /// layout persistence and restoration.
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

    /// Resolves a released trigger's fresh live identifier after a cache
    /// refresh. Exact matching wins; a suffix-drift fallback is accepted only
    /// when the live base identifier has one unambiguous candidate.
    static nonisolated func unambiguousLiveIdentifier(
        matching protectedIdentifier: String,
        in liveIdentifiers: [String],
        knownBaseIdentifiers: Set<String> = []
    ) -> String? {
        if liveIdentifiers.contains(protectedIdentifier) {
            return protectedIdentifier
        }
        guard let protectedBaseID = MenuBarItemTag.resolvedBaseIdentifier(
            for: protectedIdentifier,
            knownBaseIdentifiers: knownBaseIdentifiers
        ) else {
            return nil
        }
        let candidates = liveIdentifiers.filter { identifier in
            MenuBarItemTag.resolvedBaseIdentifier(
                for: identifier,
                knownBaseIdentifiers: knownBaseIdentifiers
            ) == protectedBaseID
        }
        return candidates.count == 1 ? candidates[0] : nil
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
    /// Used by the menu bar item triggers system to reveal or hide an
    /// individual item when its trigger condition changes. While a trigger
    /// owns an item, `MenuBarItemTriggersManager` excludes that temporary
    /// placement from `savedSectionOrder`; the reconciler restores the user's
    /// durable layout after the trigger releases it.
    ///
    /// - Returns: A ``TriggerMoveResult`` describing whether the move
    ///   happened, was unnecessary, should be retried later, or failed.
    @discardableResult
    func moveItem(
        withTagIdentifier tagIdentifier: String,
        toSection section: MenuBarSection.Name,
        requiredInputPause: Duration = .milliseconds(50),
        inputPauseTimeout: Duration? = nil,
        watchdogTimeout: Duration? = nil,
        maxMoveAttempts: Int = 8,
        hideCursorAcrossAttempts: Bool = true,
        shouldProceed: (@MainActor () -> Bool)? = nil
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
        guard shouldProceed?() ?? true else { return .deferred }

        // Upstream has no `getMenuBarItemsDroppingSystemClones` wrapper;
        // drop transient WindowServer duplicates inline instead.
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
        // Items destined for a hidden section must actually be hideable.
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

        // Skip when the item already resides in the effective target section.
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
            // The current `move` takes a single `skipInputPause` flag and a
            // `Duration` watchdog; the trigger branch's finer-grained pause
            // and cursor options have no upstream counterpart.
            try await move(
                item: target,
                to: destination,
                on: displayID,
                skipInputPause: requiredInputPause == .zero,
                requiredInputPause: requiredInputPause,
                inputPauseTimeout: inputPauseTimeout,
                watchdogTimeout: watchdogTimeout,
                maxMoveAttempts: maxMoveAttempts,
                hideCursorAcrossAttempts: hideCursorAcrossAttempts,
                shouldProceed: shouldProceed
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
