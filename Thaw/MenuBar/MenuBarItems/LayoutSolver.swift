//
//  LayoutSolver.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - LayoutSolver

/// Snapshot-pure planners that decide which menu bar item moves are
/// needed to reach a desired layout given the currently observed state.
///
/// LayoutSolver answers the question: "given what's here right now,
/// what is the next move?" Every function is pure over its inputs.
/// Nothing inside calls Bridging or NSScreen; the orchestrator pre-
/// computes the observed state (section classification, hidden divider
/// bounds, item widths, etc.) and passes it in.
///
/// Paired with PendingLedger, which owns the history-dependent state
/// for in-flight rehides (waitForRelaunch sentinels, return-destination
/// anchors stored across cycles). The boundary follows the council's
/// temporality split: LayoutSolver decides over the current snapshot,
/// PendingLedger decides over per-entry retry state.
enum LayoutSolver {
    // MARK: - Result types

    /// A decision emitted by the leftmost-item relocation planner.
    ///
    /// Only describes WHICH item should move and what kind of move it is.
    /// The orchestrator owns destination computation (which depends on
    /// instance state like newItemsPlacement) and state mutation
    /// (knownItemIdentifiers).
    enum LeftmostMove: Equatable {
        /// The Thaw visible-control icon is sitting left of the hidden
        /// divider; restore it to the visible section.
        case thawIcon(MenuBarItem)
        /// A non-hideable system item (screen recording / mic / camera
        /// indicator) is left of the hidden divider; restore it to
        /// visible.
        case systemItem(MenuBarItem)
        /// A genuinely new hideable item is left of the hidden divider;
        /// relocate it to the user's new-items section and persist its
        /// identifier so future cache cycles do not treat it as "new"
        /// again.
        case newHideableItem(MenuBarItem, identifierToMark: String)
        /// No relocation is warranted on this pass.
        case noop(reason: NoopReason)

        enum NoopReason: Equatable {
            /// No movable items currently sit left of the hidden divider.
            case noLeftmostItems
            /// One or more hideable candidates have unresolved sourcePID;
            /// defer until the next cache cycle resolves them.
            case unresolvedSourcePID
            /// No hideable candidate passes the newness test (either the
            /// item has a saved section, has been seen before, or appears
            /// to be an identifier migration of an existing window).
            case noNewCandidate
            /// The chosen candidate is already in the configured new-items
            /// section; moving would be a no-op.
            case alreadyInTarget
        }
    }

    /// The result of the notch-overflow planner.
    struct NotchOverflowResult: Equatable {
        /// UIDs of items that should overflow from visible to hidden.
        let overflowUIDs: [String]
        /// The desiredFiltered sequence after the overflow has been applied
        /// (overflowed items repositioned into the hidden section).
        let updatedDesiredFiltered: [String]
        /// Updated section assignments. Overflowed UIDs are remapped to
        /// "hidden". Keys are uniqueIdentifiers, values are persisted
        /// section keys ("visible"/"hidden"/"alwaysHidden").
        let updatedSectionMap: [String: String]
    }

    /// An abstract destination emitted by the LCS planner.
    ///
    /// References anchor items by UID rather than by MenuBarItem because
    /// the orchestrator re-fetches the live items between each move
    /// (positions shift mid-sequence) and resolves the UID back to a
    /// MenuBarItem at execution time.
    enum LCSPlannedDestination: Equatable {
        case leftOfUID(String)
        case rightOfUID(String)
        case sectionBoundary(MenuBarSection.Name)
    }

    /// A single planned move emitted by the LCS planner.
    struct LCSPlannedMove: Equatable {
        let uid: String
        let destination: LCSPlannedDestination
    }

    /// A placement decision for an unmanaged item during profile apply.
    ///
    /// Encodes intent (saved vs new-item-default vs new-item-anchored)
    /// without committing to a concrete MoveDestination. The
    /// orchestrator resolves anchor uids and section boundaries against
    /// the live items.
    enum UnmanagedPlacement: Equatable {
        /// Item was seen in a prior session and has a saved position.
        case saved(section: MenuBarSection.Name, index: Int)
        /// Item is new; place it at the default position within the
        /// user's configured new-items section.
        case newItemDefault(section: MenuBarSection.Name)
        /// Item is new and the user's anchor preference resolves
        /// against a currently-present item.
        case newItemAnchored(
            section: MenuBarSection.Name,
            anchorUID: String,
            relation: MenuBarItemManager.NewItemsPlacement.Relation
        )
    }

    /// A position within the saved section order: a section and the
    /// zero-based index of the item within that section's saved array.
    struct SavedPosition: Equatable {
        let section: MenuBarSection.Name
        let index: Int
    }

    /// The live observation triple planLeftmostMove needs from the
    /// orchestrator. hiddenBounds is drawn from the hidden control
    /// item's frame and marks the right edge of the leftmost zone.
    /// sectionByWindowID is a per-cycle windowID to section lookup
    /// rebuilt from cache state. previousWindowIDs is the windowID
    /// snapshot from the prior cache cycle, used to distinguish a
    /// genuinely new item from one whose identifier migrated when
    /// sourcePID resolution succeeded.
    struct LeftmostObservation {
        let hiddenBounds: CGRect
        let sectionByWindowID: [CGWindowID: MenuBarSection.Name]
        let previousWindowIDs: [CGWindowID]
    }

    // MARK: - Unmanaged partition

    /// Returns the subset of currentFlat that should be routed through
    /// planUnmanagedPlacement: items present in the live menu bar that
    /// are neither in the desired sequence (savedSectionOrder for the
    /// .savedOrder path, profile spec for the .profile path) nor any
    /// of the three Thaw control items.
    ///
    /// Control items are uniformly excluded because saveSectionOrder
    /// omits them from savedSectionOrder by design (they're not
    /// user-positionable in the same way as third-party items). If any
    /// control item leaks through, planUnmanagedPlacement will route it
    /// through NewItemsPlacement and the LCS planner will emit moves
    /// that drag the Thaw icon to the user's configured anchor on every
    /// cache cycle. Visible-control-item exclusion was the omission
    /// that caused the field-reported "Thaw icon keeps moving" bug.
    ///
    /// Input order is preserved, since downstream consumers (LCS
    /// planner) treat the result as the iteration order for placement.
    /// Pure over its inputs.
    nonisolated static func partitionUnmanagedUIDs(
        currentFlat: [String],
        desiredUIDs: Set<String>,
        hiddenCtrlUID: String?,
        ahCtrlUID: String?,
        visibleCtrlUID: String?
    ) -> [String] {
        currentFlat.filter { uid in
            !desiredUIDs.contains(uid)
                && uid != hiddenCtrlUID
                && uid != ahCtrlUID
                && uid != visibleCtrlUID
        }
    }

    // MARK: - Leftmost relocation

    /// Computes the next leftmost-relocation decision.
    ///
    /// Walks the cascade implemented by relocateNewLeftmostItems:
    /// (1) Thaw visible-control icon recovery, (2) non-hideable system
    /// item recovery, (3) genuinely new hideable item placement under the
    /// user's new-items section. The fourth path is "no action" with a
    /// typed reason so tests can pin down which branch fired.
    ///
    /// Pure over its inputs. The orchestrator computes hiddenBounds,
    /// sectionByWindowID, and the cached hidden / always-hidden tag sets
    /// (all of which depend on live state) and passes them in. State
    /// mutation (knownItemIdentifiers, persistence) and execution
    /// (move()) stay with the orchestrator.
    nonisolated static func planLeftmostMove(
        items: [MenuBarItem],
        observation: LeftmostObservation,
        savedSectionOrder: [String: [String]],
        knownItemIdentifiers: Set<String>,
        hiddenTags: Set<MenuBarItemTag>,
        alwaysHiddenTags: Set<MenuBarItemTag>,
        effectiveNewItemsSection: MenuBarSection.Name
    ) -> LeftmostMove {
        // Items sitting left of the hidden divider. The Thaw icon is a
        // control item but must always be visible, so we admit it here.
        let leftmostItems = items
            .filter {
                $0.bounds.maxX <= observation.hiddenBounds.minX &&
                    $0.isMovable &&
                    (!$0.isControlItem || $0.tag == .visibleControlItem)
            }
            .sorted { $0.bounds.minX < $1.bounds.minX }

        guard !leftmostItems.isEmpty else {
            return .noop(reason: .noLeftmostItems)
        }

        // Path 1: Thaw icon.
        if let thawIcon = leftmostItems.first(where: { $0.tag == .visibleControlItem }) {
            return .thawIcon(thawIcon)
        }

        // Path 2: non-hideable system item (camera / mic / screen recording).
        // Excludes transient Control Center items (Live Activities,
        // iPhone Mirroring); those live deeply off-screen and cannot be
        // dragged successfully, so retrying every cache cycle would
        // burn the eventSemaphore for ~4 s per attempt.
        if let systemItem = leftmostItems.first(where: { !$0.canBeHidden && !$0.isTransientControlCenterItem }) {
            return .systemItem(systemItem)
        }

        // Path 3: hideable candidate selection.
        let hideableLeftmost = leftmostItems.filter(\.canBeHidden)
        let previousIDs = Set(observation.previousWindowIDs)

        // Unresolved sourcePID short-circuit. Without sourcePID
        // resolution, third-party items hosted by Control Center fall
        // back to namespace com.apple.controlcenter, which prevents
        // matching against savedSectionOrder (real bundle IDs). The
        // next cache pass with resolved sourcePIDs will handle
        // relocation safely.
        if hideableLeftmost.contains(where: { $0.sourcePID == nil }) {
            return .noop(reason: .unresolvedSourcePID)
        }

        // Build identifier → section lookup over savedSectionOrder.
        var savedSectionForIdentifier = [String: MenuBarSection.Name]()
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(forPersistedKey: sectionKeyString) else { continue }
            for identifier in identifiers {
                savedSectionForIdentifier[identifier] = section
            }
        }

        let candidate = hideableLeftmost.first { item in
            let identifier = "\(item.tag.namespace):\(item.tag.title)"

            // Items with a saved section belong to restoreItemsToSaved-
            // Sections, not to the new-item relocation path.
            let hasSavedSection = savedSectionForIdentifier[identifier] != nil ||
                savedSectionForIdentifier[item.uniqueIdentifier] != nil
            guard !hasSavedSection else { return false }

            let isNewIdentity = !knownItemIdentifiers.contains(identifier)
            let notPlacedHidden = !hiddenTags.contains(item.tag) && !alwaysHiddenTags.contains(item.tag)

            // When isNewIdentity is true but the windowID has been seen
            // before, the item's identifier migrated (e.g. sourcePID
            // resolution succeeded). Treat that as not-new.
            let isNewID = previousIDs.isEmpty ? isNewIdentity : !previousIDs.contains(item.windowID)
            if isNewIdentity, !isNewID {
                return false
            }
            return notPlacedHidden && (isNewIdentity || isNewID)
        }
        guard let candidate else {
            return .noop(reason: .noNewCandidate)
        }

        // "Already in target" check.
        if observation.sectionByWindowID[candidate.windowID] == effectiveNewItemsSection {
            return .noop(reason: .alreadyInTarget)
        }

        let identifierToMark = "\(candidate.tag.namespace):\(candidate.tag.title)"
        return .newHideableItem(candidate, identifierToMark: identifierToMark)
    }

    // MARK: - Notch overflow

    /// Decides which visible items must overflow into hidden to fit the
    /// available width under the notch.
    ///
    /// Implements the tiered priority algorithm: unmanaged items
    /// (newly-detected, not in any profile section) are the first
    /// candidates to overflow because the profile has no saved position
    /// for them. Profile-saved items only overflow if even removing all
    /// unmanaged items still leaves the layout exceeding the budget.
    /// Within each tier, leftmost items overflow first.
    ///
    /// The planner does not call Bridging or NSScreen. Callers compute
    /// availableWidth from notch geometry and Control Center position,
    /// and supply per-uid widths derived from live item bounds. This
    /// keeps the planner pure for testing and pins down the algorithm
    /// for regression-locking.
    nonisolated static func planNotchOverflow(
        desiredFiltered: [String],
        unmanagedUIDs: [String],
        controlUIDs: ControlUIDs,
        sectionMap: [String: String],
        uidWidths: [String: CGFloat],
        availableWidth: CGFloat
    ) -> NotchOverflowResult {
        // Visible-section UIDs in profile order (left-to-right).
        let visibleUIDs = Array(desiredFiltered.prefix(while: { $0 != controlUIDs.hidden }))
        let chevronWidth = controlUIDs.visible.flatMap { uidWidths[$0] } ?? 0

        let unmanagedSet = Set(unmanagedUIDs)
        let nonChevronUIDs = visibleUIDs.filter { $0 != controlUIDs.visible }
        let unmanagedNonChevron = nonChevronUIDs.filter { unmanagedSet.contains($0) }
        let profileNonChevron = nonChevronUIDs.filter { !unmanagedSet.contains($0) }

        // Profile baseline: chevron + all profile-saved visible items.
        var profileBaseline: CGFloat = chevronWidth
        for uid in profileNonChevron {
            profileBaseline += uidWidths[uid] ?? 0
        }

        var overflowUIDs: [String] = []

        if profileBaseline > availableWidth {
            // Profile alone exceeds budget. All unmanaged overflow plus
            // enough profile items (leftmost first) to fit. Iterate
            // profile items from the CC end inward; whatever doesn't fit
            // overflows.
            overflowUIDs.append(contentsOf: unmanagedNonChevron)
            var profileFitting = [String]()
            var usedWidth = chevronWidth
            for uid in profileNonChevron.reversed() {
                let width = uidWidths[uid] ?? 0
                if usedWidth + width <= availableWidth {
                    usedWidth += width
                    profileFitting.insert(uid, at: 0)
                } else {
                    break
                }
            }
            let profileOverflow = Array(
                profileNonChevron.prefix(profileNonChevron.count - profileFitting.count)
            )
            overflowUIDs.append(contentsOf: profileOverflow)
        } else {
            // Profile fits. Try to fit unmanaged items from the CC end;
            // whatever doesn't fit overflows. Profile items stay put.
            var usedWidth = profileBaseline
            var unmanagedFitting = [String]()
            for uid in unmanagedNonChevron.reversed() {
                let width = uidWidths[uid] ?? 0
                if usedWidth + width <= availableWidth {
                    usedWidth += width
                    unmanagedFitting.insert(uid, at: 0)
                } else {
                    break
                }
            }
            overflowUIDs = Array(
                unmanagedNonChevron.prefix(unmanagedNonChevron.count - unmanagedFitting.count)
            )
        }

        // No overflow → return inputs unchanged.
        if overflowUIDs.isEmpty {
            return NotchOverflowResult(
                overflowUIDs: [],
                updatedDesiredFiltered: desiredFiltered,
                updatedSectionMap: sectionMap
            )
        }

        // Rebuild desiredFiltered: chevron + remaining visible items +
        // hiddenCtrl + existingHidden + overflowUIDs + ahCtrl +
        // existingAH. Overflowed items append in their original visible
        // order so leftmost-from-visible lands at the deepest end of
        // hidden.
        var controlSet: Set<String> = [controlUIDs.hidden]
        if let ahUID = controlUIDs.alwaysHidden { controlSet.insert(ahUID) }

        let hiddenStart = desiredFiltered.firstIndex(of: controlUIDs.hidden)
            .map { $0 + 1 } ?? desiredFiltered.endIndex
        let hiddenEnd = controlUIDs.alwaysHidden.flatMap { desiredFiltered.firstIndex(of: $0) }
            ?? desiredFiltered.endIndex
        let existingHidden = desiredFiltered[hiddenStart ..< hiddenEnd]
            .filter { !controlSet.contains($0) }

        let ahStart = controlUIDs.alwaysHidden.flatMap { desiredFiltered.firstIndex(of: $0) }
            .map { $0 + 1 } ?? desiredFiltered.endIndex
        let existingAH = desiredFiltered[ahStart...]
            .filter { !controlSet.contains($0) }

        let overflowSet = Set(overflowUIDs)
        let remainingNonChevron = nonChevronUIDs.filter { !overflowSet.contains($0) }

        var rebuilt = [String]()
        if let chevron = controlUIDs.visible {
            rebuilt.append(chevron)
        }
        rebuilt.append(contentsOf: remainingNonChevron)
        rebuilt.append(controlUIDs.hidden)
        rebuilt.append(contentsOf: existingHidden)
        rebuilt.append(contentsOf: overflowUIDs)
        if let ahUID = controlUIDs.alwaysHidden {
            rebuilt.append(ahUID)
            rebuilt.append(contentsOf: existingAH)
        }

        var updatedSectionMap = sectionMap
        for uid in overflowUIDs {
            updatedSectionMap[uid] = "hidden"
        }

        return NotchOverflowResult(
            overflowUIDs: overflowUIDs,
            updatedDesiredFiltered: rebuilt,
            updatedSectionMap: updatedSectionMap
        )
    }

    // MARK: - LCS reorder

    /// Plans the LCS-anchored move sequence for items that need to move
    /// to reach the desired order.
    ///
    /// Computes LCS over current and desired (filtered to overlap), then
    /// for each item that must move scans forward for a stable anchor in
    /// the same section, falls back to a backward scan, falls back to a
    /// section boundary. "Stable anchors" are LCS items plus items
    /// already planned by the sequence; so the destination of move N+1
    /// can reference an anchor that move N just established.
    ///
    /// Pure over its inputs. Returns destinations as anchor UIDs so the
    /// orchestrator can resolve them against fresh items between moves.
    nonisolated static func planLCSMoveSequence(
        currentNoControls: [String],
        desiredNoControls: [String],
        sectionMap: [String: String]
    ) -> [LCSPlannedMove] {
        let currentSetNow = Set(currentNoControls)
        let desiredSetNow = Set(desiredNoControls)
        let lcsCurrent = currentNoControls.filter { desiredSetNow.contains($0) }
        let lcsDesired = desiredNoControls.filter { currentSetNow.contains($0) }

        let lcsItems = longestCommonSubsequence(lcsCurrent, lcsDesired)
        let itemsToMove = lcsDesired.filter { !lcsItems.contains($0) }

        if itemsToMove.isEmpty {
            return []
        }

        var movedItems = Set<String>()
        var result = [LCSPlannedMove]()

        for uid in itemsToMove {
            guard let desiredIdx = lcsDesired.firstIndex(of: uid) else {
                continue
            }
            let targetKey = sectionMap[uid] ?? "visible"

            var destination: LCSPlannedDestination?

            // Scan forward for a stable anchor in the same section.
            for scanIdx in (desiredIdx + 1) ..< lcsDesired.count {
                let candidateUID = lcsDesired[scanIdx]
                let candidateKey = sectionMap[candidateUID] ?? "visible"
                guard candidateKey == targetKey else { break }
                if lcsItems.contains(candidateUID) || movedItems.contains(candidateUID) {
                    destination = .leftOfUID(candidateUID)
                    break
                }
            }

            // Scan backward for a stable anchor.
            if destination == nil, desiredIdx > 0 {
                for scanIdx in stride(from: desiredIdx - 1, through: 0, by: -1) {
                    let candidateUID = lcsDesired[scanIdx]
                    let candidateKey = sectionMap[candidateUID] ?? "visible"
                    guard candidateKey == targetKey else { break }
                    if lcsItems.contains(candidateUID) || movedItems.contains(candidateUID) {
                        destination = .rightOfUID(candidateUID)
                        break
                    }
                }
            }

            // Fallback to section boundary.
            if destination == nil {
                let targetSection: MenuBarSection.Name
                switch targetKey {
                case "hidden": targetSection = .hidden
                case "alwaysHidden": targetSection = .alwaysHidden
                default: targetSection = .visible
                }
                destination = .sectionBoundary(targetSection)
            }

            if let destination {
                result.append(LCSPlannedMove(uid: uid, destination: destination))
                movedItems.insert(uid)
            }
        }
        return result
    }

    // MARK: - Full-sort sequence

    /// Plans the full-sort sequence used on notched displays.
    ///
    /// Each item in the returned sequence is placed left of the
    /// Control Center item by the orchestrator; subsequent insertions push earlier items
    /// further left. Result is:
    ///   [alwaysHidden items] [AH ctrl] [hidden items] [hidden ctrl] [visible items]
    /// in left-to-right order.
    ///
    /// Returns an empty array when the current order already matches the
    /// desired order (no moves needed) or when desired is empty.
    ///
    /// Pure over its inputs. The orchestrator handles per-item live
    /// fetching, the move() loop, and control-item state restoration.
    nonisolated static func planFullSortSequence(
        currentFlat: [String],
        desiredFiltered: [String],
        sectionMap: [String: String],
        hiddenCtrlUID: String,
        ahCtrlUID: String?
    ) -> [String] {
        // Skip if current order already matches the desired order.
        let desiredSet = Set(desiredFiltered)
        let currentFiltered = currentFlat.filter { desiredSet.contains($0) }
        if currentFiltered == desiredFiltered {
            return []
        }

        var controlSet: Set<String> = [hiddenCtrlUID]
        if let ahUID = ahCtrlUID { controlSet.insert(ahUID) }

        let ahUIDs = desiredFiltered.filter {
            !controlSet.contains($0) && (sectionMap[$0] ?? "visible") == "alwaysHidden"
        }
        let hiddenUIDs = desiredFiltered.filter {
            !controlSet.contains($0) && (sectionMap[$0] ?? "visible") == "hidden"
        }
        let visibleUIDs = desiredFiltered.filter {
            !controlSet.contains($0) && (sectionMap[$0] ?? "visible") == "visible"
        }

        var fullSequence = [String]()
        fullSequence.append(contentsOf: ahUIDs)
        if let ahCtrlUID { fullSequence.append(ahCtrlUID) }
        fullSequence.append(contentsOf: hiddenUIDs)
        fullSequence.append(hiddenCtrlUID)
        fullSequence.append(contentsOf: visibleUIDs)
        return fullSequence
    }

    // MARK: - Saved-position lookup

    /// Looks up the saved position for the given identifier by exact match.
    ///
    /// Returns the section and index in that section's saved array if the
    /// identifier matches an entry. Returns nil if not found.
    nonisolated static func savedPosition(
        for uid: String,
        in savedSectionOrder: [String: [String]]
    ) -> SavedPosition? {
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(forPersistedKey: sectionKeyString) else { continue }
            if let index = identifiers.firstIndex(of: uid) {
                return SavedPosition(section: section, index: index)
            }
        }
        return nil
    }

    /// Looks up the saved position for the given identifier, falling back
    /// to baseID matching when the exact instanceIndex differs.
    ///
    /// Multi-instance apps may receive a different :N suffix on relaunch
    /// (instance indices are reassigned by windowID sort order after each
    /// assignStableInstanceIndices pass). This variant first tries an
    /// exact-identifier match, then a baseID-prefix match against any
    /// instance saved for the same namespace:title. Returns the first
    /// baseID match found.
    nonisolated static func savedPositionByBaseID(
        for uid: String,
        in savedSectionOrder: [String: [String]]
    ) -> SavedPosition? {
        if let exact = savedPosition(for: uid, in: savedSectionOrder) {
            return exact
        }
        let baseID = uid.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
        guard baseID.contains(":") else { return nil }
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(forPersistedKey: sectionKeyString) else { continue }
            for (index, identifier) in identifiers.enumerated() {
                let savedBaseID = identifier.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
                if savedBaseID == baseID {
                    return SavedPosition(section: section, index: index)
                }
            }
        }
        return nil
    }

    // MARK: - Unmanaged placement

    /// Decides where each unmanaged item should land during a profile
    /// apply, consulting saved positions first and falling back to the
    /// user's NewItemsPlacement preference.
    ///
    /// Unmanaged items are items present in the live menu bar but not
    /// covered by the profile spec. Today's behavior parks them all at
    /// visible-leftmost; this planner replaces that hardcoded choice
    /// with the user's actual layout history.
    ///
    /// Pure over its inputs.
    nonisolated static func planUnmanagedPlacement(
        unmanagedUIDs: [String],
        savedSectionOrder: [String: [String]],
        newItemsPlacement: MenuBarItemManager.NewItemsPlacement,
        currentUIDs: Set<String>
    ) -> [String: UnmanagedPlacement] {
        var result = [String: UnmanagedPlacement]()
        let newItemsSection = sectionName(forPersistedKey: newItemsPlacement.sectionKey) ?? .hidden

        for uid in unmanagedUIDs {
            // 1. Saved-position lookup (exact then baseID).
            if let position = savedPositionByBaseID(for: uid, in: savedSectionOrder) {
                result[uid] = .saved(section: position.section, index: position.index)
                continue
            }

            // 2. NewItemsPlacement anchor (if configured and present in
            //    the current menu bar).
            if newItemsPlacement.relation != .sectionDefault,
               let anchor = newItemsPlacement.anchorIdentifier,
               currentUIDs.contains(anchor)
            {
                result[uid] = .newItemAnchored(
                    section: newItemsSection,
                    anchorUID: anchor,
                    relation: newItemsPlacement.relation
                )
                continue
            }

            // 3. Fallback: place at the new-items section's default
            //    boundary.
            result[uid] = .newItemDefault(section: newItemsSection)
        }
        return result
    }

    // MARK: - Anchor resolution

    /// Computes the abstract destination that positions an item at the
    /// given saved index within its section.
    ///
    /// Used by the profile-route unmanaged placement path
    /// (applyProfileLayout's unmanaged-items block via
    /// planUnmanagedPlacement) and by the reconciler when it lifts a
    /// saved position into a concrete destination. Forward-first scan
    /// finds a successor
    /// anchor (the next uid in saved order that is currently in the
    /// section); backward scan finds a predecessor anchor. Falls back
    /// to the section boundary when no anchors are present.
    ///
    /// Forward-first matches user intent: when restoring an item at
    /// saved index N, prefer to anchor against the item that follows
    /// it in saved order rather than the one before, because the
    /// follower's current position is the more reliable signal of
    /// "this is where the section ends".
    ///
    /// Pure over its inputs.
    nonisolated static func anchorDestination(
        forSavedIndex savedIndex: Int,
        inSection section: MenuBarSection.Name,
        savedSequence: [String],
        currentUIDsInSection: Set<String>
    ) -> LCSPlannedDestination {
        // Forward scan: closest successor anchor.
        if savedIndex + 1 < savedSequence.count {
            for i in (savedIndex + 1) ..< savedSequence.count {
                let candidate = savedSequence[i]
                if currentUIDsInSection.contains(candidate) {
                    return .leftOfUID(candidate)
                }
            }
        }
        // Backward scan: closest predecessor anchor.
        if savedIndex > 0 {
            let start = min(savedIndex - 1, savedSequence.count - 1)
            if start >= 0 {
                for i in stride(from: start, through: 0, by: -1) {
                    let candidate = savedSequence[i]
                    if currentUIDsInSection.contains(candidate) {
                        return .rightOfUID(candidate)
                    }
                }
            }
        }
        // No anchors → section boundary.
        return .sectionBoundary(section)
    }

    // MARK: - Saved-section rebuild

    /// Computes the new saved-section identifiers array for one section,
    /// preserving closed-app positions relative to their old neighbors.
    ///
    /// Replaces the buggy "append closed apps to the end" logic that
    /// destroyed positional intent every time the user quit an app.
    /// The new algorithm:
    ///
    /// 1. Start with the items currently in the section (cache order).
    /// 2. Walk the old saved order. For each entry that is no longer
    ///    present in the cache (closed app) and is not a stale instance
    ///    index, splice it into the new list at a position anchored
    ///    against its old neighbors that are still present. Forward-
    ///    first scan (insert before the closest still-present successor)
    ///    then backward (after the closest still-present predecessor)
    ///    then append as last resort.
    ///
    /// Pure over its inputs.
    nonisolated static func planSectionOrder(
        currentInSection: [String],
        oldSavedForSection: [String],
        allCurrentIdentifiers: Set<String>,
        allCurrentBaseIdentifiers: Set<String>
    ) -> [String] {
        var identifiers = currentInSection

        for (oldIdx, savedUID) in oldSavedForSection.enumerated() {
            // Already in the new list (currently present) or already
            // inserted by an earlier iteration: skip.
            if identifiers.contains(savedUID) {
                continue
            }
            // Present somewhere in the cache (other section): drop the
            // saved entry; the item moved, do not re-preserve it here.
            if allCurrentIdentifiers.contains(savedUID) {
                continue
            }
            // Stale instance index: the app is back with a different
            // :N suffix. The cache already has it under its new uid;
            // drop the stale saved entry.
            let base = savedUID.split(separator: ":", maxSplits: 2)
                .prefix(2).joined(separator: ":")
            if allCurrentBaseIdentifiers.contains(base) {
                continue
            }

            // Find an anchor in oldSavedForSection that's also in the
            // new identifiers list. Forward-first (closest successor),
            // then backward (closest predecessor), then append.
            var insertAt: Int = identifiers.count

            // Forward scan from oldIdx+1.
            var foundForward = false
            if oldIdx + 1 < oldSavedForSection.count {
                for i in (oldIdx + 1) ..< oldSavedForSection.count {
                    let candidate = oldSavedForSection[i]
                    if let anchorIdx = identifiers.firstIndex(of: candidate) {
                        insertAt = anchorIdx
                        foundForward = true
                        break
                    }
                }
            }

            // Backward scan from oldIdx-1 (only if forward didn't find one).
            if !foundForward, oldIdx > 0 {
                for i in stride(from: oldIdx - 1, through: 0, by: -1) {
                    let candidate = oldSavedForSection[i]
                    if let anchorIdx = identifiers.firstIndex(of: candidate) {
                        insertAt = anchorIdx + 1
                        break
                    }
                }
            }

            identifiers.insert(savedUID, at: insertAt)
        }

        return identifiers
    }

    // MARK: - Internal helpers

    /// Computes the Longest Common Subsequence of two string arrays.
    /// Returns the set of items that appear in both arrays in the same
    /// relative order: these items don't need to be moved.
    nonisolated static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> Set<String> {
        let m = a.count
        let n = b.count
        guard m > 0, n > 0 else { return [] }

        // DP table.
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1 ... m {
            for j in 1 ... n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find the LCS items.
        var result = Set<String>()
        var i = m
        var j = n
        while i > 0, j > 0 {
            if a[i - 1] == b[j - 1] {
                result.insert(a[i - 1])
                i -= 1; j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result
    }

    /// Extracts the baseID (namespace:title) prefix from a uniqueIdentifier.
    nonisolated private static func baseID(forIdentifier id: String) -> String {
        id.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
    }

    /// Maps a persisted section key string to its enum value.
    nonisolated private static func sectionName(forPersistedKey key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }

    /// Maps a section to its persisted key string.
    nonisolated private static func sectionKeyFor(_ section: MenuBarSection.Name) -> String {
        switch section {
        case .visible: return "visible"
        case .hidden: return "hidden"
        case .alwaysHidden: return "alwaysHidden"
        }
    }

    // MARK: - State flag gates

    /// Truth table for the saveSectionOrder gate: only persist when no
    /// in-flight orchestrator owns the menu bar state. Each input maps
    /// to a class-level flag whose individual semantics are documented
    /// in MenuBarItemManager's coordination block.
    ///
    /// Pure over its inputs so the gate can be characterized without
    /// instantiating MenuBarItemManager. Any future addition to the
    /// gate (new in-flight signal) should extend both this function
    /// and its tests.
    nonisolated static func shouldPersistSavedOrder(
        isRestoringItemOrder: Bool,
        isResettingLayout: Bool,
        isInStartupSettling: Bool,
        isApplyingProfileLayout: Bool,
        temporarilyShownItemContextsIsEmpty: Bool
    ) -> Bool {
        !isRestoringItemOrder &&
            !isResettingLayout &&
            !isInStartupSettling &&
            !isApplyingProfileLayout &&
            temporarilyShownItemContextsIsEmpty
    }

    // MARK: - Pending rehide identifiers

    /// Returns the set of `tag.tagIdentifier` values whose item is
    /// known to belong to a section other than its current cache
    /// position because of a temporarily-shown rehide that has not yet
    /// completed.
    ///
    /// Two sources contribute:
    /// 1. Active `pendingReturnDestinations` entries: the in-flight
    ///    context has been dropped (rehide gave up or the user
    ///    abandoned return) but the return-destination metadata
    ///    survives until the app relaunches and relocatePendingItems
    ///    moves the item back.
    /// 2. `pendingRelocations` entries whose value carries the
    ///    `waitForRelaunch:` sentinel: the rehide hit the per-session
    ///    retry cap and was suspended, waiting for the app to
    ///    relaunch with a fresh windowID.
    ///
    /// saveSectionOrder uses the union to exclude these items from
    /// the cache snapshot, so planSectionOrder treats them as closed
    /// apps and preserves their original-section saved entry rather
    /// than overwriting it with the live visible position.
    nonisolated static func pendingRehideTagIdentifiers(
        pendingReturnDestinations: [String: [String: String]],
        pendingRelocations: [String: String],
        waitForRelaunchPrefix: String
    ) -> Set<String> {
        Set(pendingReturnDestinations.keys).union(
            pendingRelocations.compactMap { tagID, value in
                value.hasPrefix(waitForRelaunchPrefix) ? tagID : nil
            }
        )
    }

    // MARK: - Batch PID scan window selection

    /// Returns the first window in the batch whose windowID is not
    /// already cached, or nil when every window is cached.
    ///
    /// Drives `SourcePIDCache.pidsBody`'s decision about which window
    /// to hand to `pidBody` for the AX scan. `pidBody` returns
    /// immediately on a cache hit at its entry, so passing a cached
    /// window means the scan body (including the marker-pair
    /// fallback) never runs. Selecting an unresolved window forces
    /// the scan path to execute and resolves every other unresolved
    /// window in the same batch by populating the cache during the
    /// AX traversal.
    nonisolated static func selectWindowForBatchScan<W>(
        windows: [W],
        windowID: (W) -> CGWindowID,
        cachedPIDs: [CGWindowID: pid_t]
    ) -> W? {
        windows.first(where: { window in
            cachedPIDs[windowID(window)] == nil
        })
    }
}
