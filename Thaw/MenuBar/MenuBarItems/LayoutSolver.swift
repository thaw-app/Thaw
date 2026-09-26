//
//  LayoutSolver.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - LayoutSolver

/// Snapshot-pure planners that decide which menu bar item moves are
/// needed to reach a desired layout given the currently observed state.
///
/// Every function is pure; the orchestrator computes observed state and
/// passes it in. PendingLedger owns the state that spans cycles.
nonisolated enum LayoutSolver {
    // MARK: - Result types

    /// A decision emitted by the leftmost-item relocation planner.
    ///
    /// Only which item moves and how; the orchestrator owns destinations
    /// and state.
    enum LeftmostMove: Equatable {
        /// The Thaw icon is left of the hidden divider.
        case thawIcon(MenuBarItem)
        /// A non-hideable system indicator is left of the hidden divider.
        case systemItem(MenuBarItem)
        /// A new hideable item is left of the hidden divider. The identifier
        /// is persisted so it isn't treated as new again.
        case newHideableItem(MenuBarItem, identifierToMark: String)
        case noop(reason: NoopReason)

        enum NoopReason: Equatable {
            case noLeftmostItems
            /// Defer until sourcePIDs resolve.
            case unresolvedSourcePID
            /// Saved, seen before, or an identifier migration.
            case noNewCandidate
            case alreadyInTarget
        }
    }

    struct NotchOverflowResult: Equatable {
        let overflowUIDs: [String]
        let updatedDesiredFiltered: [String]
        /// Values are persisted section keys.
        let updatedSectionMap: [String: String]
    }

    /// An abstract destination emitted by the LCS planner.
    ///
    /// By UID, since live items are re-fetched between moves.
    enum LCSPlannedDestination: Equatable {
        case leftOfUID(String)
        case rightOfUID(String)
        case sectionBoundary(MenuBarSection.Name)
    }

    struct LCSPlannedMove: Equatable {
        let uid: String
        let destination: LCSPlannedDestination
    }

    /// A placement decision for an unmanaged item during profile apply.
    ///
    /// Intent only; the orchestrator resolves it against live items.
    enum UnmanagedPlacement: Equatable {
        case saved(section: MenuBarSection.Name, index: Int)
        case newItemDefault(section: MenuBarSection.Name)
        /// The anchor preference resolves to a present item.
        case newItemAnchored(
            section: MenuBarSection.Name,
            anchorUID: String,
            relation: MenuBarItemManager.NewItemsPlacement.Relation
        )
    }

    /// The nearest eligible neighbors on either side of an item, as
    /// indices into the item list the search ran over.
    struct ReturnAnchors: Equatable {
        /// Preferred.
        let successor: Int?
        let predecessor: Int?
    }

    struct SavedPosition: Equatable {
        let section: MenuBarSection.Name
        let index: Int
    }

    /// previousWindowIDs tells a new item from one whose identifier migrated
    /// when sourcePID resolved. recentWindowIDs widens that over several
    /// cycles so one degraded enumeration can't make an item look new.
    struct LeftmostObservation {
        let hiddenBounds: CGRect
        let sectionByWindowID: [CGWindowID: MenuBarSection.Name]
        let previousWindowIDs: [CGWindowID]
        let recentWindowIDs: Set<CGWindowID>

        init(
            hiddenBounds: CGRect,
            sectionByWindowID: [CGWindowID: MenuBarSection.Name],
            previousWindowIDs: [CGWindowID],
            recentWindowIDs: Set<CGWindowID> = []
        ) {
            self.hiddenBounds = hiddenBounds
            self.sectionByWindowID = sectionByWindowID
            self.previousWindowIDs = previousWindowIDs
            self.recentWindowIDs = recentWindowIDs
        }
    }

    // MARK: - Current flat construction

    /// Flattens the three current sections into the single ordered identifier
    /// sequence the profile-apply planner consumes, inserting the hidden and
    /// always-hidden control items at their section boundaries.
    ///
    /// The visible control item is already in the visible array.
    static nonisolated func flattenCurrentSections(
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

    // MARK: - Unmanaged partition

    /// Live items that are neither desired nor Thaw control items. Order is
    /// preserved.
    ///
    /// All control items must be excluded, or the Thaw icon gets dragged to
    /// the new-items anchor every cycle. Unresolved generic Control Center
    /// items are excluded too: they never match a profile entry and would be
    /// relocated every cycle (seen with Little Snitch).
    /// - Parameter triggerControlledUIDs: Items a trigger owns. Otherwise the
    ///   fallback placement moves them back and undoes the trigger.
    static nonisolated func partitionUnmanagedUIDs(
        currentFlat: [String],
        desiredUIDs: Set<String>,
        hiddenCtrlUID: String?,
        ahCtrlUID: String?,
        visibleCtrlUID: String?,
        provisionalIdentityUIDs: Set<String>,
        triggerControlledUIDs: Set<String> = []
    ) -> [String] {
        currentFlat.filter { uid in
            !desiredUIDs.contains(uid)
                && uid != hiddenCtrlUID
                && uid != ahCtrlUID
                && uid != visibleCtrlUID
                && !provisionalIdentityUIDs.contains(uid)
                && !triggerControlledUIDs.contains(uid)
        }
    }

    static nonisolated func provisionalIdentityUIDs(items: [MenuBarItem]) -> Set<String> {
        Set(items.filter(\.hasProvisionalIdentity).map(\.uniqueIdentifier))
    }

    // MARK: - Leftmost relocation

    /// Items sitting left of the hidden divider, ordered so `first` is a
    /// stable choice. The Thaw icon is a control item but must always be
    /// visible, so it is admitted here.
    private static nonisolated func leftmostItems(
        items: [MenuBarItem],
        hiddenBounds: CGRect
    ) -> [MenuBarItem] {
        let candidates = items
            .filter { item in
                // Not draggable, but the unresolved-sourcePID path needs them.
                let isUnresolvedControlCenterPlaceholder =
                    item.tag.isControlCenterGenericItem && item.sourcePID == nil

                return item.bounds.maxX <= hiddenBounds.minX &&
                    (item.isMovable || isUnresolvedControlCenterPlaceholder) &&
                    (!item.isControlItem || item.tag == .visibleControlItem)
            }
        // Tie-broken so a minX tie during reflow can't flip the choice.
        return MenuBarItem.sortByLeadingEdgeThenIdentifier(candidates)
    }

    /// The Thaw-icon relocation decision on its own, for callers that must
    /// act before the rest of ``planLeftmostMove``'s inputs are trustworthy.
    ///
    /// Needs only geometry and our own tag, which are right from the first
    /// pass; the other paths wait for source PIDs.
    static nonisolated func planThawIconMove(
        items: [MenuBarItem],
        hiddenBounds: CGRect
    ) -> MenuBarItem? {
        leftmostItems(items: items, hiddenBounds: hiddenBounds)
            .first { $0.tag == .visibleControlItem }
    }

    /// Picks the next leftmost relocation: the Thaw icon, then non-hideable
    /// system items, then new hideable items, else a typed no-op.
    static nonisolated func planLeftmostMove(
        items: [MenuBarItem],
        observation: LeftmostObservation,
        savedSectionOrder: [String: [String]],
        knownItemIdentifiers: Set<String>,
        hiddenTags: Set<MenuBarItemTag>,
        alwaysHiddenTags: Set<MenuBarItemTag>,
        effectiveNewItemsSection: MenuBarSection.Name
    ) -> LeftmostMove {
        let leftmostItems = leftmostItems(items: items, hiddenBounds: observation.hiddenBounds)

        guard !leftmostItems.isEmpty else {
            return .noop(reason: .noLeftmostItems)
        }

        // Path 1: Thaw icon.
        if let thawIcon = leftmostItems.first(where: { $0.tag == .visibleControlItem }) {
            return .thawIcon(thawIcon)
        }

        // Path 2: non-hideable system item. Transient Control Center items
        // live far offscreen and can't be dragged; retrying costs ~4 s each.
        if let systemItem = leftmostItems.first(where: { !$0.canBeHidden && !$0.isTransientControlCenterItem }) {
            return .systemItem(systemItem)
        }

        // Path 3: hideable candidate selection.
        let hideableLeftmost = leftmostItems.filter(\.canBeHidden)
        // Judged over several cycles, since one degraded enumeration can drop
        // a windowID and make the item look new (#849).
        let previousIDs = Set(observation.previousWindowIDs)
            .union(observation.recentWindowIDs)

        // Without sourcePIDs, Control Center-hosted items can't match
        // savedSectionOrder. Wait for the next pass.
        if hideableLeftmost.contains(where: { $0.sourcePID == nil }) {
            return .noop(reason: .unresolvedSourcePID)
        }

        var savedSectionForIdentifier = [String: MenuBarSection.Name]()
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(forPersistedKey: sectionKeyString) else { continue }
            for identifier in identifiers {
                savedSectionForIdentifier[identifier] = section
                // Also under the canonical form: items titled after a live
                // metric were saved under a stale value. Raw keys still match.
                let canonical = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
                if canonical != identifier {
                    savedSectionForIdentifier[canonical] = section
                }
            }
        }

        // Namespace fallback: an item is `<bundleID>:Item-0` while hosted as
        // a generic slot and renamed once sourcePID resolves, so one saved
        // form misses the other (#849). Only used with exactly one saved
        // entry and one live item, and it can only suppress relocations.
        let savedCountByNamespace = Dictionary(
            savedSectionOrder.lazy
                .filter { sectionName(forPersistedKey: $0.key) != nil }
                .flatMap(\.value)
                .map { (namespace(forIdentifier: $0), 1) },
            uniquingKeysWith: +
        )
        let liveCountByNamespace = Dictionary(
            items.lazy.map { ($0.tag.namespace.description, 1) },
            uniquingKeysWith: +
        )

        let candidate = hideableLeftmost.first { item in
            let identifier = "\(item.tag.namespace):\(item.tag.title)"

            // Saved items belong to restoreItemsToSavedSections.
            var hasSavedSection = savedSectionForIdentifier[identifier] != nil ||
                savedSectionForIdentifier[item.uniqueIdentifier] != nil ||
                savedSectionForIdentifier[
                    MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
                ] != nil
            if !hasSavedSection {
                let itemNamespace = item.tag.namespace.description
                hasSavedSection = item.tag.namespace.isString &&
                    item.tag.namespace != .controlCenter &&
                    savedCountByNamespace[itemNamespace] == 1 &&
                    liveCountByNamespace[itemNamespace] == 1
            }
            guard !hasSavedSection else { return false }

            let isNewIdentity = !knownItemIdentifiers.contains(identifier)
            let notPlacedHidden = !hiddenTags.contains(item.tag) && !alwaysHiddenTags.contains(item.tag)

            // A seen windowID with a new identity is a migration, not new.
            let isNewID = previousIDs.isEmpty ? isNewIdentity : !previousIDs.contains(item.windowID)
            if isNewIdentity, !isNewID {
                return false
            }
            return notPlacedHidden && (isNewIdentity || isNewID)
        }
        guard let candidate else {
            return .noop(reason: .noNewCandidate)
        }

        if observation.sectionByWindowID[candidate.windowID] == effectiveNewItemsSection {
            return .noop(reason: .alreadyInTarget)
        }

        let identifierToMark = "\(candidate.tag.namespace):\(candidate.tag.title)"
        return .newHideableItem(candidate, identifierToMark: identifierToMark)
    }

    // MARK: - Geometry readiness

    /// Whether the menu bar geometry is settled enough to run a layout pass on
    /// a notched display.
    ///
    /// `rightBoundary` is Control Center's left edge. At or left of the notch
    /// (or non-finite), Control Center is at a stale position, as during a
    /// display reconnect, and acting on it throws the Thaw icon far left.
    static nonisolated func isMenuBarGeometryReady(
        rightBoundary: CGFloat,
        notchMaxX: CGFloat
    ) -> Bool {
        rightBoundary.isFinite && rightBoundary > notchMaxX
    }

    /// Whether the notch-overflow rebalance should run for the current active
    /// menu bar display.
    ///
    /// Only on the main display. On a notched secondary that briefly holds
    /// focus, the narrow budget strands items in hidden.
    ///
    /// Fails closed when the active screen is unknown; guessing risks the
    /// same wrong budget.
    static nonisolated func shouldManageNotchOverflow(
        overflowEnabled: Bool,
        activeScreenKnown: Bool,
        activeHasNotch: Bool,
        activeIsMainDisplay: Bool
    ) -> Bool {
        overflowEnabled && activeScreenKnown && activeHasNotch && activeIsMainDisplay
    }

    /// Whether the given menu bar items currently occupy more than one display.
    ///
    /// Global CoreGraphics coordinates. macOS migrates status items between
    /// displays asynchronously; moving or saving mid-migration strands items,
    /// so callers defer.
    ///
    /// Pass only unparked items. Parked items can land on a display left of
    /// the main one, which reads as a spread forever and blocks every save.
    static nonisolated func itemsSpanMultipleDisplays(
        itemCenters: [CGPoint],
        screenFrames: [CGRect]
    ) -> Bool {
        guard screenFrames.count > 1 else { return false }
        var hitScreens = Set<Int>()
        for center in itemCenters {
            guard let index = screenFrames.firstIndex(where: { $0.contains(center) }) else {
                continue
            }
            hitScreens.insert(index)
            if hitScreens.count > 1 {
                return true
            }
        }
        return false
    }

    /// A parked item is a bad drag anchor: AppKit snaps it back on every
    /// retry (#881).
    ///
    /// Tests the leading edge, not the center: a collapsed divider is 5000pt
    /// wide, so its center can land on a display left of the origin (#958).
    static nonisolated func isOnScreen(bounds: CGRect, screenFrames: [CGRect]) -> Bool {
        let leadingEdge = CGPoint(x: bounds.minX, y: bounds.midY)
        return screenFrames.contains { $0.contains(leadingEdge) }
    }

    /// Whether an item lies entirely off every display.
    ///
    /// For stranded dividers, unlike ``isOnScreen``: a collapsed divider's
    /// leading edge is always far offscreen, so only a divider with no edge
    /// on any screen may be rebuilt (#978).
    static nonisolated func isFullyOffScreen(bounds: CGRect, screenFrames: [CGRect]) -> Bool {
        !screenFrames.contains { $0.intersects(bounds) }
    }

    // MARK: - Notch overflow

    /// Decides which visible items must overflow into hidden to fit the
    /// available width under the notch.
    ///
    /// Unmanaged items overflow first; profile items only if that isn't
    /// enough. Leftmost first within each tier.
    static nonisolated func planNotchOverflow(
        desiredFiltered: [String],
        unmanagedUIDs: [String],
        controlUIDs: ControlUIDs,
        sectionMap: [String: String],
        uidWidths: [String: CGFloat],
        availableWidth: CGFloat
    ) -> NotchOverflowResult {
        // During a display reconnect Control Center reports a stale edge and
        // the budget goes negative, which would dump every item into hidden.
        guard availableWidth > 0, availableWidth.isFinite else {
            return NotchOverflowResult(
                overflowUIDs: [],
                updatedDesiredFiltered: desiredFiltered,
                updatedSectionMap: sectionMap
            )
        }

        let visibleUIDs = Array(desiredFiltered.prefix(while: { $0 != controlUIDs.hidden }))
        let chevronWidth = controlUIDs.visible.flatMap { uidWidths[$0] } ?? 0

        let unmanagedSet = Set(unmanagedUIDs)
        let nonChevronUIDs = visibleUIDs.filter { $0 != controlUIDs.visible }
        let unmanagedNonChevron = nonChevronUIDs.filter { unmanagedSet.contains($0) }
        let profileNonChevron = nonChevronUIDs.filter { !unmanagedSet.contains($0) }

        var profileBaseline: CGFloat = chevronWidth
        for uid in profileNonChevron {
            profileBaseline += uidWidths[uid] ?? 0
        }

        var overflowUIDs: [String] = []

        if profileBaseline > availableWidth {
            // Profile alone exceeds the budget; fill from the CC end inward.
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
            // Profile fits; fit unmanaged items from the CC end.
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

        if overflowUIDs.isEmpty {
            return NotchOverflowResult(
                overflowUIDs: [],
                updatedDesiredFiltered: desiredFiltered,
                updatedSectionMap: sectionMap
            )
        }

        // Overflowed items append in visible order, so the leftmost lands
        // deepest in hidden.
        var controlSet: Set<String> = [controlUIDs.hidden]
        if let ahUID = controlUIDs.alwaysHidden {
            controlSet.insert(ahUID)
        }

        let hiddenIndex = desiredFiltered.firstIndex(of: controlUIDs.hidden)
        let alwaysHiddenIndex = controlUIDs.alwaysHidden
            .flatMap { desiredFiltered.firstIndex(of: $0) }

        let hiddenStart = hiddenIndex.map { $0 + 1 } ?? desiredFiltered.endIndex
        let hiddenEnd = alwaysHiddenIndex ?? desiredFiltered.endIndex

        // Control items can be out of order or missing during a reconnect,
        // which would trap the slice below.
        guard hiddenStart <= hiddenEnd else {
            return NotchOverflowResult(
                overflowUIDs: [],
                updatedDesiredFiltered: desiredFiltered,
                updatedSectionMap: sectionMap
            )
        }

        let existingHidden = desiredFiltered[hiddenStart ..< hiddenEnd]
            .filter { !controlSet.contains($0) }

        let ahStart = alwaysHiddenIndex.map { $0 + 1 } ?? desiredFiltered.endIndex
        let existingAH = desiredFiltered[ahStart...]
            .filter { !controlSet.contains($0) }

        let overflowSet = Set(overflowUIDs)
        // Filter rather than prepend the chevron, which would move the Thaw
        // icon leftmost on every overflow.
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
            updatedSectionMap: updatedSectionMap
        )
    }

    // MARK: - Hidden divider boundary

    /// Where the hidden divider belongs, expressed relative to a live
    /// anchor item so the orchestrator can resolve it against fresh
    /// items at move time.
    enum HiddenDividerAnchor: Equatable {
        /// Place the hidden divider directly right of this item.
        case rightOf(String)
        /// Place the hidden divider directly left of this item.
        case leftOf(String)
    }

    /// Counts the items sitting on the wrong side of the hidden divider.
    ///
    /// Phase 1 and the LCS pass both miss a drifted divider: Phase 1 sees
    /// empty sets and the LCS strips dividers (#879).
    static nonisolated func hiddenBoundaryMismatch(
        currentVisible: Set<String>,
        currentHidden: Set<String>,
        currentAlwaysHidden: Set<String>,
        desiredVisible: Set<String>,
        desiredHidden: Set<String>,
        desiredAlwaysHidden: Set<String>,
        overflowExemptUIDs: Set<String> = []
    ) -> Int {
        hiddenBoundaryOffenders(
            currentVisible: currentVisible,
            currentHidden: currentHidden,
            currentAlwaysHidden: currentAlwaysHidden,
            desiredVisible: desiredVisible,
            desiredHidden: desiredHidden,
            desiredAlwaysHidden: desiredAlwaysHidden,
            overflowExemptUIDs: overflowExemptUIDs
        ).count
    }

    /// The items counted by ``hiddenBoundaryMismatch(currentVisible:currentHidden:currentAlwaysHidden:desiredVisible:desiredHidden:desiredAlwaysHidden:)``,
    /// named and split by the direction they have to travel.
    ///
    /// Derived from the same rule as the tally, so the two can't disagree.
    struct HiddenBoundaryOffenders: Equatable {
        /// Visible, but wanted concealed.
        var wronglyVisible: Set<String>
        /// Concealed, but wanted visible.
        var wronglyConcealed: Set<String>

        var count: Int {
            wronglyVisible.count + wronglyConcealed.count
        }

        var isEmpty: Bool {
            wronglyVisible.isEmpty && wronglyConcealed.isEmpty
        }
    }

    /// Splits the boundary mismatch into the two directions of travel.
    ///
    /// `overflowExemptUIDs` are notch-overflow ejects, in hidden by design.
    /// Counting them oscillates between recall and eject. Only hidden is
    /// exempt; always-hidden is real drift.
    static nonisolated func hiddenBoundaryOffenders(
        currentVisible: Set<String>,
        currentHidden: Set<String>,
        currentAlwaysHidden: Set<String>,
        desiredVisible: Set<String>,
        desiredHidden: Set<String>,
        desiredAlwaysHidden: Set<String>,
        overflowExemptUIDs: Set<String> = []
    ) -> HiddenBoundaryOffenders {
        // Which concealed section is the always-hidden divider's problem.
        let desiredConcealed = desiredHidden.union(desiredAlwaysHidden)
        let currentConcealed = currentHidden.union(currentAlwaysHidden)

        return HiddenBoundaryOffenders(
            wronglyVisible: currentVisible.intersection(desiredConcealed),
            wronglyConcealed: currentConcealed.intersection(desiredVisible)
                .subtracting(overflowExemptUIDs.intersection(currentHidden))
        )
    }

    /// Whether a boundary mismatch should be repaired by dragging the
    /// hidden divider, or by moving the offending items to it.
    ///
    /// Dragging H_ctrl re-sections every item it crosses, so only drag it
    /// when a side has nothing live left, meaning the divider drifted:
    /// nothing concealed (#879) or nothing visible (#958). Otherwise move
    /// the items.
    ///
    /// Counts exclude control items; the chevron would keep the visible
    /// count above zero on a collapsed bar.
    static nonisolated func shouldMoveHiddenDivider(
        liveConcealedCount: Int,
        liveVisibleCount: Int
    ) -> Bool {
        liveConcealedCount == 0 || liveVisibleCount == 0
    }

    /// Plans where to drag the hidden divider so the visible/hidden split
    /// matches the profile.
    ///
    /// The divider belongs right of the rightmost hidden item, else left of
    /// the leftmost visible one, so emptying hidden still parks it past
    /// every visible item.
    ///
    /// An unanchorable candidate yields nil rather than searching on; the
    /// next candidate would be on the wrong side of the gap. In practice
    /// that's the chevron, and dragging H_ctrl to it swept a whole section
    /// into hidden (#958). Nil hands the work to the per-item LCS pass.
    static nonisolated func planHiddenDividerAnchor(
        desiredHidden: [String],
        desiredVisible: [String],
        liveMovableUIDs: Set<String>,
        unanchorableUIDs: Set<String> = []
    ) -> HiddenDividerAnchor? {
        // Shared with hiddenDividerAnchorCandidate so logs name the same
        // item.
        guard let candidate = hiddenDividerAnchorCandidate(
            desiredHidden: desiredHidden,
            desiredVisible: desiredVisible,
            liveMovableUIDs: liveMovableUIDs
        ) else {
            return nil
        }
        if unanchorableUIDs.contains(candidate) {
            return nil
        }
        // Hidden side first: rightOf it. Visible side only as fallback:
        // leftOf it.
        return desiredHidden.first(where: liveMovableUIDs.contains) == candidate
            ? .rightOf(candidate)
            : .leftOf(candidate)
    }

    /// The item ``planHiddenDividerAnchor(desiredHidden:desiredVisible:liveMovableUIDs:unanchorableUIDs:)``
    /// picks before the unanchorable test, so logs can tell "nothing live"
    /// from "refused anchor".
    static nonisolated func hiddenDividerAnchorCandidate(
        desiredHidden: [String],
        desiredVisible: [String],
        liveMovableUIDs: Set<String>
    ) -> String? {
        desiredHidden.first(where: liveMovableUIDs.contains)
            ?? desiredVisible.last(where: liveMovableUIDs.contains)
    }

    // MARK: - Cross-section fallback

    /// Which slot a cross-boundary fallback move lands its item in.
    ///
    /// Every move lands on the always-hidden divider and pushes earlier
    /// arrivals away from it.
    enum FallbackLandingSlot {
        case leftmostOfHidden
        case rightmostOfAlwaysHidden
    }

    /// The order in which items crossing the hidden to always-hidden
    /// boundary must be dragged so they come to rest in profile order.
    ///
    /// The item that ends furthest from the divider moves first. Getting it
    /// backwards reverses the section silently: membership is right, and
    /// relaxConcealedSectionOrder then accepts the reversal.
    ///
    /// Unknown identifiers go last, sorted for determinism.
    static nonisolated func crossSectionFallbackMoveOrder(
        profileOrder: [String],
        crossing: Set<String>,
        landingSlot: FallbackLandingSlot
    ) -> [String] {
        let positioned = switch landingSlot {
        case .leftmostOfHidden:
            profileOrder.reversed().filter(crossing.contains)
        case .rightmostOfAlwaysHidden:
            profileOrder.filter(crossing.contains)
        }
        return positioned + crossing.subtracting(profileOrder).sorted()
    }

    // MARK: - LCS reorder

    /// Rewrites the desired sequence so that, inside concealed sections,
    /// items keep the relative order they already have.
    ///
    /// A move hijacks the cursor, and reordering items parked offscreen buys
    /// nothing visible; the Thaw Bar renders from the cache.
    ///
    /// Membership is still enforced; only order within a section is
    /// surrendered. Items with no live counterpart sort last.
    static nonisolated func relaxConcealedSectionOrder(
        desiredNoControls: [String],
        currentNoControls: [String],
        sectionMap: [String: String],
        relaxedSectionKeys: Set<String> = ["hidden", "alwaysHidden"]
    ) -> [String] {
        guard !relaxedSectionKeys.isEmpty else { return desiredNoControls }

        var currentIndex = [String: Int]()
        for (index, uid) in currentNoControls.enumerated() {
            currentIndex[uid] = index
        }

        // (rank, desiredIndex) keeps the sort deterministic, since `sort`
        // isn't stable.
        var queues = [String: [String]]()
        for key in relaxedSectionKeys {
            let members = desiredNoControls.enumerated().filter { _, uid in
                (sectionMap[uid] ?? "visible") == key
            }
            queues[key] = members
                .sorted { lhs, rhs in
                    let lhsRank = currentIndex[lhs.element] ?? Int.max
                    let rhsRank = currentIndex[rhs.element] ?? Int.max
                    if lhsRank != rhsRank {
                        return lhsRank < rhsRank
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
        }

        var cursors = [String: Int]()
        return desiredNoControls.map { uid in
            let key = sectionMap[uid] ?? "visible"
            guard let queue = queues[key] else { return uid }
            let cursor = cursors[key] ?? 0
            guard cursor < queue.count else { return uid }
            cursors[key] = cursor + 1
            return queue[cursor]
        }
    }

    /// Plans moves for items outside the LCS. Each anchors forward, then
    /// backward, then on the section boundary; anchors are LCS items or
    /// ones already planned. Returns anchor UIDs, resolved between moves.
    static nonisolated func planLCSMoveSequence(
        currentNoControls: [String],
        desiredNoControls: [String],
        sectionMap: [String: String],
        unanchorableUIDs: Set<String> = [],
        preferredMoveUIDs: Set<String> = []
    ) -> [LCSPlannedMove] {
        let currentSetNow = Set(currentNoControls)
        let desiredSetNow = Set(desiredNoControls)
        let lcsCurrent = currentNoControls.filter { desiredSetNow.contains($0) }
        let lcsDesired = desiredNoControls.filter { currentSetNow.contains($0) }

        let lcsItems = longestCommonSubsequence(
            lcsCurrent,
            lcsDesired,
            preferredMoveUIDs: preferredMoveUIDs
        )
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

            // Scan forward for a stable anchor in the same section. Skip
            // Thaw's dividers: a failed move shoves them left each retry,
            // ending in a zero-width hidden section (#924, #927).
            for scanIdx in (desiredIdx + 1) ..< lcsDesired.count {
                let candidateUID = lcsDesired[scanIdx]
                let candidateKey = sectionMap[candidateUID] ?? "visible"
                guard candidateKey == targetKey else { break }
                if unanchorableUIDs.contains(candidateUID) {
                    continue
                }
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
                    if unanchorableUIDs.contains(candidateUID) {
                        continue
                    }
                    if lcsItems.contains(candidateUID) || movedItems.contains(candidateUID) {
                        destination = .rightOfUID(candidateUID)
                        break
                    }
                }
            }

            // Fallback to section boundary.
            if destination == nil {
                let targetSection: MenuBarSection.Name = switch targetKey {
                case "hidden": .hidden
                case "alwaysHidden": .alwaysHidden
                default: .visible
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

    // MARK: - Saved-position lookup

    /// Exact-match lookup.
    static nonisolated func savedPosition(
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
    /// Multi-instance apps can get a different :N suffix on relaunch.
    static nonisolated func savedPositionByBaseID(
        for uid: String,
        in savedSectionOrder: [String: [String]]
    ) -> SavedPosition? {
        if let exact = savedPosition(for: uid, in: savedSectionOrder) {
            return exact
        }

        // For volatile titles both the exact and base-ID matches miss, since
        // the title is the volatile part. Canonicalization keeps the
        // instance index.
        let canonicalUID = MenuBarItemTag.canonicalPersistentIdentifier(uid)
        if canonicalUID != uid {
            for (sectionKeyString, identifiers) in savedSectionOrder {
                guard let section = sectionName(forPersistedKey: sectionKeyString) else { continue }
                for (index, identifier) in identifiers.enumerated()
                    where MenuBarItemTag.canonicalPersistentIdentifier(identifier) == canonicalUID
                {
                    return SavedPosition(section: section, index: index)
                }
            }
        }

        let baseID = baseID(forIdentifier: uid)
        guard baseID.contains(":") else { return nil }
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(forPersistedKey: sectionKeyString) else { continue }
            for (index, identifier) in identifiers.enumerated() {
                let savedBaseID = Self.baseID(forIdentifier: identifier)
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
    static nonisolated func planUnmanagedPlacement(
        unmanagedUIDs: [String],
        savedSectionOrder: [String: [String]],
        newItemsPlacement: MenuBarItemManager.NewItemsPlacement,
        currentUIDs: Set<String>
    ) -> [String: UnmanagedPlacement] {
        var result = [String: UnmanagedPlacement]()
        let newItemsSection = sectionName(forPersistedKey: newItemsPlacement.sectionKey) ?? .hidden

        for uid in unmanagedUIDs {
            if let position = savedPositionByBaseID(for: uid, in: savedSectionOrder) {
                result[uid] = .saved(section: position.section, index: position.index)
                continue
            }

            // NewItemsPlacement anchor, resolved to the live UID.
            if newItemsPlacement.relation != .sectionDefault,
               let anchor = newItemsPlacement.anchorIdentifier,
               let liveAnchor = currentUIDs.first(where: {
                   newItemsAnchorMatches($0, anchor)
               })
            {
                result[uid] = .newItemAnchored(
                    section: newItemsSection,
                    anchorUID: liveAnchor,
                    relation: newItemsPlacement.relation
                )
                continue
            }

            result[uid] = .newItemDefault(section: newItemsSection)
        }
        return result
    }

    // MARK: - Anchor resolution

    /// Computes the abstract destination that positions an item at the
    /// given saved index within its section.
    ///
    /// Prefers the successor anchor, whose position is the more reliable
    /// signal, then the predecessor, then the section boundary.
    static nonisolated func anchorDestination(
        forSavedIndex savedIndex: Int,
        inSection section: MenuBarSection.Name,
        savedSequence: [String],
        currentUIDsInSection: Set<String>
    ) -> LCSPlannedDestination {
        if savedIndex + 1 < savedSequence.count {
            for i in (savedIndex + 1) ..< savedSequence.count {
                let candidate = savedSequence[i]
                if currentUIDsInSection.contains(candidate) {
                    return .leftOfUID(candidate)
                }
            }
        }
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
        return .sectionBoundary(section)
    }

    /// Finds the nearest eligible neighbors on either side of the item at
    /// `index`.
    ///
    /// Only same-section neighbors qualify, or the item returns into the
    /// wrong section. Successor first, as in
    /// ``anchorDestination(forSavedIndex:inSection:savedSequence:currentUIDsInSection:)``.
    static nonisolated func returnAnchors(
        forIndex index: Int,
        itemCount: Int,
        eligibleIndices: Set<Int>
    ) -> ReturnAnchors {
        guard index >= 0, index < itemCount else {
            return ReturnAnchors(successor: nil, predecessor: nil)
        }
        let successor = ((index + 1) ..< itemCount).first { eligibleIndices.contains($0) }
        let predecessor = index > 0
            ? stride(from: index - 1, through: 0, by: -1).first { eligibleIndices.contains($0) }
            : nil
        return ReturnAnchors(successor: successor, predecessor: predecessor)
    }

    // MARK: - Saved-section rebuild

    /// Computes the new saved-section identifiers array for one section,
    /// preserving closed-app positions relative to their old neighbors.
    ///
    /// Closed apps are spliced back beside their old neighbors (successor
    /// first, then predecessor, then the end) instead of appended.
    static nonisolated func planSectionOrder(
        currentInSection: [String],
        oldSavedForSection: [String],
        allCurrentIdentifiers: Set<String>,
        allCurrentBaseIdentifiers: Set<String>
    ) -> [String] {
        var identifiers = currentInSection

        for (oldIdx, savedUID) in oldSavedForSection.enumerated() {
            if identifiers.contains(savedUID) {
                continue
            }
            // The item moved to another section.
            if allCurrentIdentifiers.contains(savedUID) {
                continue
            }
            // Stale instance index: the app is back with a new :N suffix.
            // Not `baseID(forIdentifier:)`, which truncates titles that
            // contain a colon and re-inserts the stale entry every cycle.
            if MenuBarItemTag.resolvedBaseIdentifier(
                for: savedUID,
                knownBaseIdentifiers: allCurrentBaseIdentifiers
            ) != nil {
                continue
            }

            var insertAt: Int = identifiers.count

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

    /// Items in the LCS don't need to move.
    static nonisolated func longestCommonSubsequence(
        _ a: [String],
        _ b: [String],
        preferredMoveUIDs: Set<String> = []
    ) -> Set<String> {
        let m = a.count
        let n = b.count
        guard m > 0, n > 0 else { return [] }

        struct Score: Comparable {
            let establishedCount: Int
            let totalCount: Int

            static func < (lhs: Self, rhs: Self) -> Bool {
                if lhs.totalCount != rhs.totalCount {
                    return lhs.totalCount < rhs.totalCount
                }
                return lhs.establishedCount < rhs.establishedCount
            }

            func adding(isEstablished: Bool) -> Self {
                Score(
                    establishedCount: establishedCount + (isEstablished ? 1 : 0),
                    totalCount: totalCount + 1
                )
            }
        }

        // Prefer subsequences that preserve the most established items, then
        // the greatest total length. This makes an unmanaged arrival the mover
        // when keeping it would displace an existing item (#885).
        let zero = Score(establishedCount: 0, totalCount: 0)
        var dp = Array(repeating: Array(repeating: zero, count: n + 1), count: m + 1)
        for i in 1 ... m {
            for j in 1 ... n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1].adding(
                        isEstablished: !preferredMoveUIDs.contains(a[i - 1])
                    )
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

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

    /// The `namespace:title` prefix.
    static nonisolated func baseID(forIdentifier id: String) -> String {
        id.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
    }

    /// No namespace form contains a colon, so the first component is it.
    private static nonisolated func namespace(forIdentifier id: String) -> String {
        String(id.prefix { $0 != ":" })
    }

    // MARK: - Saved-order pruning

    /// Keeps any `:<digits>` instance index, so instances must match too.
    private static nonisolated func titlePortion(forIdentifier id: String) -> String {
        guard let separator = id.firstIndex(of: ":") else { return "" }
        return String(id[id.index(after: separator)...])
    }

    /// Rewrites a persisted identifier so its namespace matches what a live
    /// item now reports.
    ///
    /// ``MenuBarItemTag/Namespace/canonicalBundleID(_:)`` renames nested
    /// helpers, e.g. `at.obdev.littlesnitch.agent` to `at.obdev.littlesnitch`,
    /// so older entries would be pruned and lose their position. Only the
    /// namespace changes.
    static nonisolated func canonicalIdentifier(_ identifier: String) -> String {
        let namespaceValue = namespace(forIdentifier: identifier)
        let canonical = MenuBarItemTag.Namespace.canonicalBundleID(namespaceValue)
        guard canonical != namespaceValue else { return identifier }
        guard identifier.firstIndex(of: ":") != nil else { return canonical }
        return "\(canonical):\(titlePortion(forIdentifier: identifier))"
    }

    /// Allows for persisted-identifier canonicalization.
    static nonisolated func newItemsAnchorMatches(_ identifier: String, _ anchor: String) -> Bool {
        if identifier == anchor {
            return true
        }
        return canonicalIdentifier(identifier) == canonicalIdentifier(anchor)
    }

    /// Applies ``canonicalIdentifier(_:)`` across a saved section order.
    ///
    /// Runs before pruning at load. Order is preserved.
    static nonisolated func canonicalizedSectionOrder(
        _ savedSectionOrder: [String: [String]]
    ) -> [String: [String]] {
        savedSectionOrder.mapValues { identifiers in
            identifiers.map(canonicalIdentifier)
        }
    }

    /// Whether the namespace is a localized display name, minted when a
    /// bundle ID reads nil mid-launch (`Control Centre:Battery`, #949).
    /// Display names usually contain whitespace; `aliases` covers those that
    /// don't, such as Kontrollzentrum.
    private static nonisolated func isDisplayNameNamespace(
        identifier: String,
        aliases: Set<String>
    ) -> Bool {
        let namespace = namespace(forIdentifier: identifier)
        return namespace.contains(where: \.isWhitespace) || aliases.contains(namespace)
    }

    /// An unreadable title persists as `com.apple.controlcenter:` or
    /// `com.apple.controlcenter::1`.
    private static nonisolated func hasEmptyTitle(identifier: String) -> Bool {
        let title = titlePortion(forIdentifier: identifier)
        if title.isEmpty {
            return true
        }
        // Only an instance-index suffix is left.
        guard title.hasPrefix(":") else { return false }
        let index = title.dropFirst()
        return !index.isEmpty && index.allSatisfy(\.isNumber)
    }

    /// The title without any `:<digits>` instance index.
    private static nonisolated func titleWithoutInstanceIndex(_ title: String) -> String {
        guard
            let separator = title.lastIndex(of: ":"),
            Int(title[title.index(after: separator)...]) != nil
        else {
            return title
        }
        return String(title[..<separator])
    }

    /// Whether an identifier claims Thaw's own namespace while naming an item
    /// Thaw does not own.
    ///
    /// Only control items and spacers belong here; anything else came from
    /// source-PID resolution handing a foreign window our PID.
    private static nonisolated func isForeignEntryUnderOwnNamespace(identifier: String) -> Bool {
        guard namespace(forIdentifier: identifier) == MenuBarItemTag.Namespace.thaw.description else {
            return false
        }
        let title = titleWithoutInstanceIndex(titlePortion(forIdentifier: identifier))
        if title.contains(".Spacer.") {
            return false
        }
        return ControlItem.Identifier(rawValue: title) == nil
    }

    /// Whether an identifier's title is a copy of its own namespace.
    ///
    /// `kCGWindowName` sometimes reports every title as the owner's bundle
    /// ID, giving `com.steipete.codexbar:com.steipete.codexbar`. This clears
    /// entries earlier builds wrote.
    ///
    /// Both halves are canonicalized, since the namespace was already
    /// rewritten but the title wasn't.
    private static nonisolated func isSelfTitledEntry(identifier: String) -> Bool {
        let title = titleWithoutInstanceIndex(titlePortion(forIdentifier: identifier))
        guard !title.isEmpty else { return false }
        return MenuBarItemTag.Namespace.canonicalBundleID(title)
            == MenuBarItemTag.Namespace.canonicalBundleID(namespace(forIdentifier: identifier))
    }

    /// Whether an identifier names a WindowServer clone rather than a real
    /// item.
    ///
    /// Older layouts hold one entry per clone.
    private static nonisolated func isSystemCloneEntry(identifier: String) -> Bool {
        titleWithoutInstanceIndex(titlePortion(forIdentifier: identifier)) == "System Status Item Clone"
    }

    /// The smallest bar the proportional half of
    /// ``liveIdentitiesAreDegraded(_:)`` will judge.
    ///
    /// One genuinely self-titled app can be half of a bar of three, not four.
    private static let minimumDegradationSample = 4

    /// Whether a reading of the bar titled its items after their own owners
    /// rather than after themselves.
    ///
    /// `kCGWindowName` degrades bar-wide. Caching it makes every item look
    /// new, and each flip between spellings triggers a re-sort that moves
    /// the cursor (#881).
    ///
    /// Either signal is enough:
    ///
    /// - A control item titled with our bundle ID. Such a reading also
    ///   arrives with the dividers missing.
    /// - Half the bar is self-titled, subject to ``minimumDegradationSample``.
    ///
    /// Partial degradations are cleared by ``prunedSectionOrder(_:)``.
    ///
    /// - Parameter identities: Non-control items plus any window that should
    ///   have been a control item, with clones and ghosts already dropped.
    static nonisolated func liveIdentitiesAreDegraded(
        _ identities: [(namespace: String, title: String)]
    ) -> Bool {
        let own = MenuBarItemTag.Namespace.thaw.description
        let isSelfTitled = { (identity: (namespace: String, title: String)) in
            !identity.title.isEmpty
                && MenuBarItemTag.Namespace.canonicalBundleID(identity.title)
                == MenuBarItemTag.Namespace.canonicalBundleID(identity.namespace)
        }

        if identities.contains(where: { $0.namespace == own && isSelfTitled($0) }) {
            return true
        }

        guard identities.count >= minimumDegradationSample else { return false }
        return identities.count(where: isSelfTitled) * 2 >= identities.count
    }

    /// Unique identifiers of `items` sorted by `key`, stable for equal keys.
    /// Backs the "Sort A→Z" section action.
    static nonisolated func sortedSectionIdentifiers(
        _ items: [MenuBarItem],
        by key: (MenuBarItem) -> String
    ) -> [String] {
        // stableSort is unavailable on LinuxFoundation; indexed enumeration
        // preserves the input order for equal keys, matching a stable sort.
        let indexed = items.enumerated().map { offset, item in (offset, key(item), item.uniqueIdentifier) }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1.localizedCaseInsensitiveCompare(rhs.1) == .orderedAscending
            }
            return lhs.0 < rhs.0
        }
        return sorted.map(\.2)
    }

    /// Removes persisted entries that can no longer match a live item:
    ///
    /// - Control Center copies of items now saved under their real owner
    ///   (#788). Genuine Control Center items are never removed on their own.
    /// - Volatile-title samples (iStat Menus, LyricsX) that canonicalize to
    ///   one key (#815). Extra entries also disable the namespace fallback.
    /// - Foreign items under Thaw's namespace, system clones, and self-titled
    ///   entries (#881, #927).
    ///
    /// Entries are dropped, never rearranged (#885).
    static nonisolated func prunedSectionOrder(
        _ savedSectionOrder: [String: [String]],
        displayNameAliases: Set<String> = []
    ) -> [String: [String]] {
        let controlCenter = MenuBarItemTag.Namespace.controlCenter.description

        // Titles claimed by a real owner. Misattributed entries don't count,
        // or the genuine Control Center twin gets deleted (#927).
        var titlesWithRealOwner = Set<String>()
        var controlCenterTitles = Set<String>()
        for identifiers in savedSectionOrder.values {
            for identifier in identifiers {
                if namespace(forIdentifier: identifier) == controlCenter {
                    controlCenterTitles.insert(titlePortion(forIdentifier: identifier))
                    continue
                }
                guard
                    // A Control Center module title under a foreign
                    // namespace is a misattribution (#1027).
                    !isMisattributedControlCenterEntry(identifier: identifier),
                    !isForeignEntryUnderOwnNamespace(identifier: identifier),
                    !isSelfTitledEntry(identifier: identifier),
                    // Nor is a localized display name (#949).
                    !isDisplayNameNamespace(identifier: identifier, aliases: displayNameAliases)
                else {
                    continue
                }
                titlesWithRealOwner.insert(titlePortion(forIdentifier: identifier))
            }
        }

        // Dedupe across all sections, or one key can live in two sections
        // and resolve nondeterministically. The most visible section wins.
        var seenCanonical = Set<String>()
        var keptPerSection = [String: Set<String>]()
        for sectionKey in ["visible", "hidden", "alwaysHidden"] where savedSectionOrder[sectionKey] != nil {
            var keptHere = Set<String>()
            for identifier in savedSectionOrder[sectionKey] ?? [] {
                let canonical = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
                if seenCanonical.insert(canonical).inserted {
                    keptHere.insert(identifier)
                }
            }
            keptPerSection[sectionKey] = keptHere
        }
        // Unknown sections keep their entries.
        for (sectionKey, identifiers) in savedSectionOrder where keptPerSection[sectionKey] == nil {
            keptPerSection[sectionKey] = Set(identifiers)
        }

        return savedSectionOrder.reduce(into: [String: [String]]()) { result, entry in
            let (sectionKey, identifiers) = entry
            let kept = keptPerSection[sectionKey] ?? []
            var emitted = Set<String>()
            result[sectionKey] = identifiers.filter { identifier in
                // The module title alone proves the misattribution, e.g.
                // `com.techsmith.snagit.capturehelper:Battery` (#1027).
                // Generic `Item-N` titles are ambiguous and not covered.
                if isMisattributedControlCenterEntry(identifier: identifier) {
                    return false
                }
                let isControlCenterHosted = namespace(forIdentifier: identifier) == controlCenter
                let isProvisionalDuplicate = isControlCenterHosted
                    && titlesWithRealOwner.contains(titlePortion(forIdentifier: identifier))
                if isProvisionalDuplicate {
                    return false
                }
                // Pruned only when a canonical twin exists. With no twin it
                // may be a bundle-ID-less app's only identity (#949).
                if isDisplayNameNamespace(identifier: identifier, aliases: displayNameAliases) {
                    let namespace = namespace(forIdentifier: identifier)
                    // A Control Center alias is redundant once the canonical
                    // namespace is saved anywhere, Item-N ghosts included.
                    if displayNameAliases.contains(namespace),
                       !controlCenterTitles.isEmpty
                    {
                        return false
                    }
                    let title = titlePortion(forIdentifier: identifier)
                    if controlCenterTitles.contains(title) {
                        return false
                    }
                    if title.hasPrefix("Thaw.ControlItem.") || title.contains(".Spacer.") {
                        return false
                    }
                    let baseTitle = title.replacing(/:\d+$/, with: "")
                    if !MarkerPairResolver.isGenericControlCenterTitle(baseTitle),
                       titlesWithRealOwner.contains(title)
                    {
                        return false
                    }
                }
                // Untitled Control Center entries identify nothing. Real
                // owners keep theirs for the namespace fallback.
                if isControlCenterHosted, hasEmptyTitle(identifier: identifier) {
                    return false
                }
                // Nothing live will carry these names again.
                if isForeignEntryUnderOwnNamespace(identifier: identifier) {
                    return false
                }
                if isSystemCloneEntry(identifier: identifier) {
                    return false
                }
                if isSelfTitledEntry(identifier: identifier) {
                    return false
                }
                // Guards against a duplicate within one section.
                guard kept.contains(identifier) else { return false }
                return emitted.insert(identifier).inserted
            }
        }
    }

    /// Whether an identifier names a Control Center module under a namespace
    /// other than Control Center's own.
    ///
    /// Multi-display coordinate skew can hand source-PID resolution the
    /// neighboring process (#1027). The PID resolved, so only the title
    /// shows it.
    private static nonisolated func isMisattributedControlCenterEntry(identifier: String) -> Bool {
        MenuBarItemTag.canonicalControlCenterModuleIdentifier(identifier) != identifier
    }

    private static nonisolated func sectionName(forPersistedKey key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }

    // MARK: - State flag gates

    /// Persist only when no in-flight orchestrator owns the menu bar.
    ///
    /// `hasPendingDivergence`: a divergence awaits a second cycle's
    /// confirmation, and the cache may hold a transient macOS rebuild.
    ///
    /// `hasUnfinishedMoveBatch`: the last apply gave up partway. Saving that
    /// makes the bar drift further each pass instead of converging.
    ///
    /// Extend this and its tests for any new in-flight signal.
    static nonisolated func shouldPersistSavedOrder(_ gate: SavedOrderGate) -> Bool {
        !gate.isRestoringItemOrder &&
            !gate.isResettingLayout &&
            !gate.isInStartupSettling &&
            !gate.isApplyingProfileLayout &&
            gate.temporarilyShownItemContextsIsEmpty &&
            gate.alwaysHiddenSectionResolved &&
            gate.hiddenSectionHasRoom &&
            !gate.hasPendingDivergence &&
            !gate.hasUnfinishedMoveBatch &&
            !gate.isWithinMoveCooldown &&
            !gate.menuBarDisplayChanged
    }

    /// The signals ``shouldPersistSavedOrder(_:)`` reads.
    ///
    /// Defaults are the permissive state, so call sites name only the
    /// signals that deviate.
    struct SavedOrderGate {
        var isRestoringItemOrder = false
        var isResettingLayout = false
        var isInStartupSettling = false
        var isApplyingProfileLayout = false
        var temporarilyShownItemContextsIsEmpty = true
        var alwaysHiddenSectionResolved = true
        var hiddenSectionHasRoom = true
        var hasPendingDivergence = false
        var hasUnfinishedMoveBatch = false

        /// Whether a move landed recently enough that `applySavedLayout`
        /// would decline to run.
        ///
        /// Must match `applySavedLayout`'s cooldown, or a cycle skips the
        /// restore but takes the save and persists an unsettled bar (#958).
        var isWithinMoveCooldown = false

        /// Whether the menu bar is on a different display than it was on
        /// the cycle that produced the current cache.
        ///
        /// macOS migrates items one at a time. `itemsSpanMultipleDisplays`
        /// only sees items still classified visible, which thin out as they
        /// are misread; this comes from the displays themselves (#958).
        var menuBarDisplayChanged = false
    }

    /// Whether the always-hidden section is resolved well enough for the
    /// current cache snapshot to be an order of record.
    ///
    /// Without the always-hidden divider every always-hidden item reads as
    /// hidden, and saving that loses the section (#849). A nil divider is
    /// fine when the section is disabled.
    static nonisolated func isAlwaysHiddenSectionResolved(
        hasAlwaysHiddenControlItem: Bool,
        isAlwaysHiddenSectionEnabled: Bool
    ) -> Bool {
        hasAlwaysHiddenControlItem || !isAlwaysHiddenSectionEnabled
    }

    /// Whether the hidden section has physical room between the two
    /// dividers for the items the saved layout puts there.
    ///
    /// When the span between the dividers closes to zero, every hidden item
    /// classifies as visible, and saving that is permanent. Seen on a docked
    /// notched secondary at negative X (#795).
    ///
    /// Passes with no always-hidden divider, or when nothing is saved as
    /// hidden.
    ///
    /// The saved count alone deadlocks: emptying hidden by hand leaves stale
    /// saved entries this gate then never lets be overwritten (#924). An
    /// empty live section is trusted only when no visible item is parked
    /// off-screen, which is what a collapse looks like (#868).
    ///
    /// - Parameters:
    ///   - hiddenControlItemMinX: Leading edge of the hidden divider.
    ///   - alwaysHiddenControlItemMaxX: Trailing edge of the always-hidden
    ///     divider, or `nil` when the section has no divider.
    ///   - savedHiddenItemCount: Items the saved layout puts in hidden.
    ///   - liveHiddenItemCount: Items the current reading puts in hidden.
    ///   - hasVisibleItemParkedOffBar: See
    ///     ``hasVisibleItemParkedOffBar(visibleItemBounds:screenFrames:)``.
    static nonisolated func hiddenSectionHasRoom(
        hiddenControlItemMinX: CGFloat,
        alwaysHiddenControlItemMaxX: CGFloat?,
        savedHiddenItemCount: Int,
        liveHiddenItemCount: Int,
        hasVisibleItemParkedOffBar: Bool
    ) -> Bool {
        guard let alwaysHiddenControlItemMaxX else {
            return true
        }
        if liveHiddenItemCount == 0, !hasVisibleItemParkedOffBar {
            return true
        }
        guard savedHiddenItemCount > 0 else {
            return true
        }
        return hiddenControlItemMinX - alwaysHiddenControlItemMaxX > 0
    }

    /// Whether the section dividers sit in the order the sections they
    /// define require.
    ///
    /// Misordered dividers mean the classifier describes a bar that doesn't
    /// exist, so the planner must not trust it (#1027).
    ///
    /// Geometric rather than ``CacheContext/findSection(for:)``, which puts
    /// each divider one section right of its own. A `nil` divider passes;
    /// blocking on absence would refuse to ever apply.
    ///
    /// - Parameters:
    ///   - visibleControlItemBounds: The chevron's bounds, or `nil` when
    ///     absent.
    ///   - hiddenControlItemBounds: The hidden divider's bounds.
    ///   - alwaysHiddenControlItemBounds: `nil` when the section has no
    ///     divider.
    static nonisolated func controlItemsAreInCanonicalOrder(
        visibleControlItemBounds: CGRect?,
        hiddenControlItemBounds: CGRect,
        alwaysHiddenControlItemBounds: CGRect?
    ) -> Bool {
        if let visibleControlItemBounds,
           visibleControlItemBounds.maxX <= hiddenControlItemBounds.minX
        {
            return false
        }
        if let alwaysHiddenControlItemBounds,
           hiddenControlItemBounds.maxX <= alwaysHiddenControlItemBounds.minX
        {
            return false
        }
        return true
    }

    /// Whether any item the current reading calls visible is parked off every
    /// display.
    ///
    /// Tells a collapsed hidden section from an emptied one. With no screen
    /// frames, answers `true` and leaves it to the saved count.
    ///
    /// Geometric because the apply path has no cache. Only items at or right
    /// of the hidden divider count. Uses ``isOnScreen(bounds:screenFrames:)``.
    static nonisolated func hasVisibleItemParkedOffBar(
        itemBounds: [CGRect],
        hiddenControlItemMinX: CGFloat,
        screenFrames: [CGRect]
    ) -> Bool {
        guard !screenFrames.isEmpty else {
            return true
        }
        return itemBounds.contains { bounds in
            bounds.minX >= hiddenControlItemMinX
                && !isOnScreen(bounds: bounds, screenFrames: screenFrames)
        }
    }

    /// How many items the given bar places strictly between the two dividers.
    ///
    /// For callers with a bar but no cache.
    static nonisolated func liveHiddenItemCount(
        itemBounds: [CGRect],
        hiddenControlItemMinX: CGFloat,
        alwaysHiddenControlItemMaxX: CGFloat?
    ) -> Int {
        guard let alwaysHiddenControlItemMaxX else {
            return itemBounds.count { $0.maxX <= hiddenControlItemMinX }
        }
        return itemBounds.count {
            $0.minX >= alwaysHiddenControlItemMaxX && $0.maxX <= hiddenControlItemMinX
        }
    }

    // MARK: - Pending rehide identifiers

    /// Items whose temporary-show rehide hasn't completed: those in
    /// `pendingReturnDestinations`, and `pendingRelocations` carrying the
    /// `waitForRelaunch:` sentinel.
    ///
    /// saveSectionOrder excludes them so their original section is kept.
    static nonisolated func pendingRehideTagIdentifiers(
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
}
