//
//  LayoutSolver.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

// MARK: - LayoutSolver

/// Snapshot-pure planners that decide which menu bar item moves are
/// needed to reach a desired layout given the currently observed state.
///
/// LayoutSolver answers the question: "given what's here right now,
/// what is the next move?" Every function is pure over its inputs.
/// Nothing inside calls Bridging or NSScreen; the orchestrator pre-
/// computes the observed state (section classification, hidden divider
/// bounds, item widths, etc.) and passes it in.
public nonisolated enum LayoutSolver {
    // MARK: - Result types

    /// A decision emitted by the leftmost-item relocation planner.
    ///
    /// Only describes which item should move and what kind of move it is.
    /// The orchestrator owns destination computation (which depends on
    /// instance state like newItemsPlacement) and state mutation
    /// (knownItemIdentifiers).
    public enum LeftmostMove: Equatable {
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

        public enum NoopReason: Equatable {
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
    public struct NotchOverflowResult: Equatable {
        /// UIDs of items that should overflow from visible to hidden.
        public let overflowUIDs: [String]
        /// The desiredFiltered sequence after the overflow has been applied
        /// (overflowed items repositioned into the hidden section).
        public let updatedDesiredFiltered: [String]
        /// Updated section assignments. Overflowed UIDs are remapped to
        /// "hidden". Keys are uniqueIdentifiers, values are persisted
        /// section keys ("visible"/"hidden"/"alwaysHidden").
        public let updatedSectionMap: [String: String]

        // MARK: Diagnostics

        // The planner is pure and nonisolated, and that purity is load-bearing
        // for its tests, so it reports facts instead of logging them. Callers log.

        /// Groups moved to hidden as one unit.
        public let groupsOverflowedWhole: [[String]]
        /// Groups wider than the entire budget, which can never fit. These
        /// overflow whole without cascading the rest of the section after them.
        public let oversizedGroups: [[String]]
        /// UIDs with no entry in uidWidths. They coerce to zero width, which
        /// silently deflates the budget, worth surfacing rather than guessing.
        public let missingWidthUIDs: [String]

        public init(
            overflowUIDs: [String],
            updatedDesiredFiltered: [String],
            updatedSectionMap: [String: String],
            groupsOverflowedWhole: [[String]] = [],
            oversizedGroups: [[String]] = [],
            missingWidthUIDs: [String] = []
        ) {
            self.overflowUIDs = overflowUIDs
            self.updatedDesiredFiltered = updatedDesiredFiltered
            self.updatedSectionMap = updatedSectionMap
            self.groupsOverflowedWhole = groupsOverflowedWhole
            self.oversizedGroups = oversizedGroups
            self.missingWidthUIDs = missingWidthUIDs
        }
    }

    /// One indivisible candidate in the visible lane: a single ungrouped item,
    /// or a whole group that must move together.
    private struct OverflowUnit {
        /// Members in visible (left-to-right) order.
        let members: [String]
        /// Summed member width.
        let width: CGFloat
        /// True when any member is unmanaged. A group is one user-visible
        /// object, so requiring all members would let a mostly-saved group
        /// pin the profile tier and never overflow.
        let isUnmanaged: Bool

        var isGroup: Bool {
            members.count > 1
        }
    }

    /// The observation planLeftmostMove needs: hiddenBounds is the leftmost
    /// zone's right edge.
    public struct LeftmostObservation {
        public let hiddenBounds: CGRect

        public init(hiddenBounds: CGRect) {
            self.hiddenBounds = hiddenBounds
        }
    }

    // MARK: - Current flat construction

    /// Flattens the three current sections into the single ordered identifier
    /// sequence the profile-apply planner consumes, inserting the hidden and
    /// always-hidden control items at their section boundaries.
    ///
    /// Order is: visible items, hidden control item, hidden items, always-
    /// hidden control item (when present), always-hidden items. The visible
    /// control item is already part of the visible array (it is not filtered
    /// out upstream the way the hidden and always-hidden control items are), so
    /// it is not reinserted here.
    ///
    /// Pure over its inputs. Shared by applyProfileLayout and the log-replay
    /// harness so both build currentFlat identically.
    public static nonisolated func flattenCurrentSections(
        visible: [String],
        hidden: [String],
        alwaysHidden: [String],
        hiddenCtrlUID: String,
        ahCtrlUID: String?
    ) -> [String] {
        var result = visible
        result.append(hiddenCtrlUID)
        result.append(contentsOf: hidden)
        if let ahCtrlUID {
            result.append(ahCtrlUID)
        }
        result.append(contentsOf: alwaysHidden)
        return result
    }

    // MARK: - Desired split

    /// The per-section ordered identifier arrays the weight-model runtime
    /// consumes.
    ///
    /// RuntimePositionStore.applyOrder(desiredOrder:) and
    /// RuntimeSectionController.setSectionOrder(_:for:) both take one
    /// ordered [String] per section, the section's left-to-right
    /// sequence. This type is that triplet: the deterministic inverse of
    /// the flat desiredFiltered form the notch-overflow and
    /// unmanaged-placement planners emit.
    ///
    /// Order lives in the array values, since a Swift Dictionary iterates in
    /// no documented order; sections are only addressed by name.
    ///
    /// The visible (chevron) control item stays in visible, matching
    /// flattenCurrentSections(visible:hidden:alwaysHidden:hiddenCtrlUID:ahCtrlUID:)
    /// and RuntimeSectionController's rule that "the movable visible Thaw
    /// control remains part of visible order". The hidden and
    /// always-hidden control items are delimiters, not members, so they
    /// never appear in any array here.
    public struct DesiredSectionOrder: Equatable {
        public var visible: [String] = []
        public var hidden: [String] = []
        public var alwaysHidden: [String] = []

        public init(visible: [String] = [], hidden: [String] = [], alwaysHidden: [String] = []) {
            self.visible = visible
            self.hidden = hidden
            self.alwaysHidden = alwaysHidden
        }

        /// Per-section access by name. Returns an empty array for a section
        /// that has no members, which is the same treatment
        /// flattenCurrentSections gives an always-hidden section when
        /// ahCtrlUID is nil.
        public subscript(section: MenuBarSectionName) -> [String] {
            get {
                switch section {
                case .visible: return visible
                case .hidden: return hidden
                case .alwaysHidden: return alwaysHidden
                }
            }
            set {
                switch section {
                case .visible: visible = newValue
                case .hidden: hidden = newValue
                case .alwaysHidden: alwaysHidden = newValue
                }
            }
        }

        /// The persisted string-keyed dictionary shape that
        /// saveSectionOrder, planSectionOrder, and the legacy
        /// savedSectionOrder: [String: [String]] planner inputs expect.
        public var asPersistedDict: [String: [String]] {
            [
                "visible": visible,
                "hidden": hidden,
                "alwaysHidden": alwaysHidden,
            ]
        }
    }

    /// Splits the flat desiredFiltered sequence into the per-section
    /// ordered arrays the weight-model runtime consumes.
    ///
    /// This is the deterministic inverse of
    /// flattenCurrentSections(visible:hidden:alwaysHidden:hiddenCtrlUID:ahCtrlUID:):
    /// the flat form carries the hidden and (when present) always-hidden
    /// control UIDs as delimiters between sections, so bracketing by
    /// those delimiters recovers each section's left-to-right order
    /// without them. The result feeds
    /// RuntimeSectionController.setSectionOrder(_:for:) and
    /// RuntimePositionStore.applyOrder(desiredOrder:), which set the
    /// weights and let macOS 27 sort. No move sequence is planned here.
    ///
    /// The flat sequence's bracketing is the source of truth for both
    /// section assignment and within-section order, so this deliberately
    /// does not consult a sectionMap: a stale map entry would reintroduce the
    /// assignment/order drift the flat composer exists to suppress. If the two
    /// ever disagree, the bracketing wins and the map should be repaired
    /// upstream.
    ///
    /// When controlUIDs.alwaysHidden is nil (always-hidden section
    /// disabled), every identifier after the hidden control item is
    /// assigned to .hidden, matching flattenCurrentSections.
    ///
    /// Pure over its inputs.
    public static nonisolated func splitDesiredFiltered(
        _ desiredFiltered: [String],
        controlUIDs: ControlUIDs
    ) -> DesiredSectionOrder {
        var order = DesiredSectionOrder()

        let hiddenIdx = desiredFiltered.firstIndex(of: controlUIDs.hidden)
        let ahIdx = controlUIDs.alwaysHidden
            .flatMap { desiredFiltered.firstIndex(of: $0) }

        // Visible: everything before the hidden control item. The visible
        // (chevron) control item, when present, stays in this prefix: the
        // runtime holds it at a fixed boundary, but it remains part of the
        // visible order.
        let visibleEnd = hiddenIdx ?? desiredFiltered.endIndex
        if visibleEnd > 0 {
            order.visible = Array(desiredFiltered[..<visibleEnd])
        }

        guard let hiddenIdx else {
            // No hidden control item in the sequence: nothing is bracketed
            // as hidden, so everything present is visible.
            return order
        }

        let hiddenStart = hiddenIdx + 1
        let hiddenEnd = ahIdx ?? desiredFiltered.endIndex
        if hiddenStart < hiddenEnd {
            order.hidden = Array(desiredFiltered[hiddenStart ..< hiddenEnd])
        }

        if let ahIdx, ahIdx + 1 < desiredFiltered.endIndex {
            order.alwaysHidden = Array(desiredFiltered[(ahIdx + 1)...])
        }

        return order
    }

    // MARK: - Unmanaged partition

    // MARK: - Leftmost relocation

    /// Computes the next leftmost-relocation decision.
    ///
    /// Walks the cascade implemented by relocateNewLeftmostItems:
    /// (1) Thaw visible-control icon recovery, (2) non-hideable system
    /// item recovery, (3) genuinely new hideable item placement under the
    /// user's new-items section. The fourth path is "no action" with a
    /// typed reason so tests can pin down which branch fired.
    ///
    /// Pure over its inputs. The orchestrator computes hiddenBounds, the
    /// cached hidden / always-hidden tag sets, and the set of position-store
    /// recoveries (all of which depend on live state) and passes them in. State
    /// mutation (knownItemIdentifiers, persistence) and execution (move()) stay
    /// with the orchestrator.
    public static nonisolated func planLeftmostMove(
        items: [MenuBarItem],
        observation: LeftmostObservation,
        savedSectionOrder: [String: [String]],
        knownItemIdentifiers: Set<String>,
        hiddenTags: Set<MenuBarItemTag>,
        alwaysHiddenTags: Set<MenuBarItemTag>,
        effectiveNewItemsSection: MenuBarSectionName,
        recoveredTags: Set<MenuBarItemTag> = [],
        supportsLegacySectionHiding: Bool = true
    ) -> LeftmostMove {
        // Items sitting left of the hidden divider. This is a legacy reflow
        // planner, so use legacy movability rather than macOS 27's broader
        // layout-anchor policy. The Thaw icon is a control item but must always
        // be visible, so we admit it here.
        //
        // Position-store recoveries are excluded outright. They are reconstructed
        // from MenuBarAgent's layout preference rather than observed, so their
        // frame is inferred and their windowID is synthetic: there is nothing to
        // drag. Left in, every recovery reads as a brand new arrival and is
        // relocated into the new-items section, where the move silently fails
        // but the assignment persists, filling the hidden section with items
        // that were never on the bar.
        let leftmostItems = MenuBarItem.sortByLeadingEdge(
            items.filter {
                $0.bounds.maxX <= observation.hiddenBounds.minX &&
                    $0.tag.isMovableInLegacySectionLayout &&
                    (!$0.isControlItem || $0.tag.matchesVisibleControlItem) &&
                    !recoveredTags.contains($0.tag)
            }
        )

        guard !leftmostItems.isEmpty else {
            return .noop(reason: .noLeftmostItems)
        }

        // The two repairs under this gate recover protected items that fell
        // left of a real legacy section divider. macOS 27 uses
        // assignment-backed sections and its divider may be
        // zero-width/synthetic, so physical position relative to that marker
        // says nothing about visibility. Retrying these moves there creates a
        // recache loop and prevents fresh order publication.
        if supportsLegacySectionHiding {
            if let thawIcon = leftmostItems.first(where: { $0.tag.matchesVisibleControlItem }) {
                return .thawIcon(thawIcon)
            }

            // Non-hideable system items are camera / mic / screen recording.
            // Excludes transient Control Center items (Live Activities,
            // iPhone Mirroring); those live deeply off-screen and cannot be
            // dragged successfully, so retrying every cache cycle would
            // burn the eventSemaphore for ~4 s per attempt.
            if let systemItem = leftmostItems.first(where: {
                !$0.canBeHiddenInLegacySectionLayout && !$0.isTransientControlCenterItem
            }) {
                return .systemItem(systemItem)
            }
        }

        let hideableLeftmost = leftmostItems.filter(\.canBeHiddenInLegacySectionLayout)

        // Unresolved sourcePID short-circuit. Without sourcePID
        // resolution, third-party items hosted by Control Center fall
        // back to namespace com.apple.controlcenter, which prevents
        // matching against savedSectionOrder (real bundle IDs). The
        // next cache pass with resolved sourcePIDs will handle
        // relocation safely.
        if hideableLeftmost.contains(where: { $0.sourcePID == nil }) {
            return .noop(reason: .unresolvedSourcePID)
        }

        var savedSectionForIdentifier = [String: MenuBarSectionName]()
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(forPersistedKey: sectionKeyString) else { continue }
            for identifier in identifiers {
                savedSectionForIdentifier[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] = section
            }
        }

        let candidate = hideableLeftmost.first { item in
            let identifier = item.uniqueIdentifier

            // Items with a saved section belong to restoreItemsToSavedSections,
            // not to the new-item relocation path.
            let hasSavedSection = savedSectionForIdentifier[identifier] != nil
            guard !hasSavedSection else { return false }

            // Newness is identity-based: macOS 27 mints synthetic window IDs that
            // churn and get recycled, so a windowID match says nothing about seating.
            let isNewIdentity = !knownItemIdentifiers.contains(identifier)
            let notPlacedHidden = !hiddenTags.contains(item.tag) && !alwaysHiddenTags.contains(item.tag)
            return notPlacedHidden && isNewIdentity
        }
        guard let candidate else {
            return .noop(reason: .noNewCandidate)
        }

        // "Already in target" check. Every live item classifies as visible at
        // the only call site, so a visible new-items section means the
        // candidate is already there.
        if effectiveNewItemsSection == .visible {
            return .noop(reason: .alreadyInTarget)
        }

        let identifierToMark = candidate.uniqueIdentifier
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
    /// and supply per-uid widths derived from live item bounds, which keeps
    /// the planner pure for testing.
    ///
    /// - Parameter groups: groups whose members must overflow together.
    ///   Defaults to none, which must leave the result unchanged.
    public static nonisolated func planNotchOverflow(
        desiredFiltered: [String],
        unmanagedUIDs: [String],
        controlUIDs: ControlUIDs,
        sectionMap: [String: String],
        uidWidths: [String: CGFloat],
        availableWidth: CGFloat,
        groups: MenuBarItemGroupPolicy.GroupSet = .empty
    ) -> NotchOverflowResult {
        // A non-positive or non-finite budget means the layout could not be
        // measured: during a display reconnect Control Center transiently
        // reports a stale off-screen left edge, driving availableWidth negative.
        // The eject logic would then dump the whole visible section into
        // hidden and persist it, so return no overflow until geometry settles.
        guard availableWidth > 0, availableWidth.isFinite else {
            return NotchOverflowResult(
                overflowUIDs: [],
                updatedDesiredFiltered: desiredFiltered,
                updatedSectionMap: sectionMap
            )
        }

        // Visible-section UIDs in profile order (left-to-right).
        let visibleUIDs = Array(desiredFiltered.prefix(while: { $0 != controlUIDs.hidden }))
        let chevronWidth = controlUIDs.visible.flatMap { uidWidths[$0] } ?? 0

        let unmanagedSet = Set(unmanagedUIDs)
        let nonChevronUIDs = visibleUIDs.filter { $0 != controlUIDs.visible }
        let missingWidthUIDs = nonChevronUIDs.filter { uidWidths[$0] == nil }

        // Fit units, not identifiers: a group is one indivisible object, so
        // it must overflow whole or not at all. Without this the budget could
        // conceal one member of a bundle and leave its sibling visible.
        let units = overflowUnits(
            in: nonChevronUIDs,
            groups: groups,
            unmanagedSet: unmanagedSet,
            uidWidths: uidWidths
        )
        let unmanagedUnits = units.filter(\.isUnmanaged)
        let profileUnits = units.filter { !$0.isUnmanaged }

        // Profile baseline: chevron + all profile-saved visible units.
        let profileBaseline = profileUnits.reduce(chevronWidth) { $0 + $1.width }

        var overflowUnits = [OverflowUnit]()
        var oversized = [OverflowUnit]()

        if profileBaseline > availableWidth {
            // Profile alone exceeds budget. All unmanaged overflow plus enough
            // profile units (leftmost first) to fit.
            overflowUnits.append(contentsOf: unmanagedUnits)
            let fitted = fitFromTrailingEdge(
                profileUnits,
                startingWidth: chevronWidth,
                availableWidth: availableWidth,
                oversized: &oversized
            )
            overflowUnits.append(contentsOf: profileUnits.filter { !fitted.contains($0.members) })
        } else {
            // Profile fits. Try to fit unmanaged units from the CC end;
            // whatever doesn't fit overflows. Profile units stay put.
            let fitted = fitFromTrailingEdge(
                unmanagedUnits,
                startingWidth: profileBaseline,
                availableWidth: availableWidth,
                oversized: &oversized
            )
            overflowUnits.append(contentsOf: unmanagedUnits.filter { !fitted.contains($0.members) })
        }

        let overflowMembers = Set(overflowUnits.flatMap(\.members))
        // Back to identifiers in the original visible order, so the existing
        // "leftmost-from-visible lands deepest in hidden" contract holds.
        let overflowUIDs = nonChevronUIDs.filter { overflowMembers.contains($0) }

        // No overflow → return inputs unchanged.
        if overflowUIDs.isEmpty {
            return NotchOverflowResult(
                overflowUIDs: [],
                updatedDesiredFiltered: desiredFiltered,
                updatedSectionMap: sectionMap,
                missingWidthUIDs: missingWidthUIDs
            )
        }

        // Rebuild desiredFiltered: chevron + remaining visible items +
        // hiddenCtrl + existingHidden + overflowUIDs + ahCtrl +
        // existingAH. Overflowed items append in their original visible
        // order so leftmost-from-visible lands at the deepest end of
        // hidden.
        var controlSet: Set<String> = [controlUIDs.hidden]
        if let ahUID = controlUIDs.alwaysHidden {
            controlSet.insert(ahUID)
        }

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
        // Keep the visible items in their saved order and drop only the
        // overflowed ones. The visible control item is never in overflowSet, so
        // filtering preserves its saved position; prepending it would move the
        // Thaw icon to the leftmost slot on every overflow.
        let remainingVisible = visibleUIDs.filter { !overflowSet.contains($0) }

        var rebuilt = [String]()
        rebuilt.append(contentsOf: remainingVisible)
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
            updatedSectionMap: updatedSectionMap,
            groupsOverflowedWhole: overflowUnits.filter(\.isGroup).map(\.members),
            oversizedGroups: oversized.map(\.members),
            missingWidthUIDs: missingWidthUIDs
        )
    }

    /// Collapses uids into indivisible units: each group becomes one unit at
    /// its leftmost member's position, everything else stays a singleton.
    ///
    /// Members need not be adjacent: a group scattered across the lane is still
    /// one unit, so the budget can never split it.
    private static nonisolated func overflowUnits(
        in uids: [String],
        groups: MenuBarItemGroupPolicy.GroupSet,
        unmanagedSet: Set<String>,
        uidWidths: [String: CGFloat]
    ) -> [OverflowUnit] {
        var units = [OverflowUnit]()
        var emittedGroups = Set<Int>()

        for uid in uids {
            guard let group = groups.groupIndex(of: uid) else {
                units.append(
                    OverflowUnit(
                        members: [uid],
                        width: uidWidths[uid] ?? 0,
                        isUnmanaged: unmanagedSet.contains(uid)
                    )
                )
                continue
            }
            guard emittedGroups.insert(group).inserted else {
                continue // already emitted at this group's leftmost member
            }
            let members = uids.filter { groups.groupIndex(of: $0) == group }
            units.append(
                OverflowUnit(
                    members: members,
                    width: members.reduce(0) { $0 + (uidWidths[$1] ?? 0) },
                    isUnmanaged: members.contains { unmanagedSet.contains($0) }
                )
            )
        }
        return units
    }

    /// Fills the budget from the Control Center end inward, returning the units
    /// that fit.
    ///
    /// Stops at the first unit that does not fit, so the survivors are always a
    /// trailing run with no holes, the contract the caller's "leftmost
    /// overflows first" rebuild depends on.
    ///
    /// The one exception is a group that could not fit even in an empty bar.
    /// Breaking on it would cascade every unit to its left into hidden and empty
    /// the visible section over one oversized cluster, so it overflows whole and
    /// the scan continues past it.
    private static nonisolated func fitFromTrailingEdge(
        _ units: [OverflowUnit],
        startingWidth: CGFloat,
        availableWidth: CGFloat,
        oversized: inout [OverflowUnit]
    ) -> Set<[String]> {
        var fitted = Set<[String]>()
        var usedWidth = startingWidth

        for unit in units.reversed() {
            if usedWidth + unit.width <= availableWidth {
                usedWidth += unit.width
                fitted.insert(unit.members)
                continue
            }
            if unit.isGroup, startingWidth + unit.width > availableWidth {
                oversized.append(unit)
                continue
            }
            break
        }
        return fitted
    }

    // MARK: - Saved-position lookup

    // MARK: - Unmanaged placement

    // MARK: - Anchor resolution

    // MARK: - Saved-section rebuild

    /// Computes the new saved-section identifiers array for one section,
    /// preserving closed-app positions relative to their old neighbors.
    ///
    /// Appending closed apps to the end would destroy positional intent every
    /// time the user quits an app. Instead this starts from the items currently
    /// in the section (cache order), then walks the old saved order and splices
    /// each entry that is no longer present (a closed app) and is not a stale
    /// instance index in next to its old neighbours that are still present:
    /// before the closest present successor, else after the closest present
    /// predecessor, else at the end.
    ///
    /// Pure over its inputs.
    public static nonisolated func planSectionOrder(
        currentInSection: [String],
        oldSavedForSection: [String],
        allCurrentIdentifiers: Set<String>,
        allCurrentBaseIdentifiers: Set<String>,
        allCurrentNamespaces: Set<String> = []
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
            // Stale title-variant of a still-running app: the namespace is in
            // the cache but this exact identifier is not. Items that vary their
            // title (countdowns, live metrics) mint a fresh identifier on every
            // change; preserving each as a "closed app" grows oldSavedForSection
            // without bound and makes this O(n²) merge pathologically slow. The
            // live item is already in currentInSection, so drop the variant.
            // The namespace is the prefix up to the first ':' (a bundle id or
            // reserved keyword never contains one).
            if !allCurrentNamespaces.isEmpty {
                let namespace = savedUID.prefix { $0 != ":" }
                if !namespace.isEmpty, allCurrentNamespaces.contains(String(namespace)) {
                    continue
                }
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

    // MARK: - Identifier and key parsing

    /// Maps a persisted section key string to its enum value. The persisted key
    /// is the enum's raw value, so this is MenuBarSectionName's own
    /// init?(rawValue:).
    private static nonisolated func sectionName(forPersistedKey key: String) -> MenuBarSectionName? {
        MenuBarSectionName(rawValue: key)
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
    public static nonisolated func shouldPersistSavedOrder(
        isRestoringItemOrder: Bool,
        isResettingLayout: Bool,
        isInStartupSettling: Bool,
        isApplyingProfileLayout: Bool
    ) -> Bool {
        !isRestoringItemOrder &&
            !isResettingLayout &&
            !isInStartupSettling &&
            !isApplyingProfileLayout
    }
}
