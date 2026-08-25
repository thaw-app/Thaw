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
nonisolated enum LayoutSolver {
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

    /// The nearest eligible neighbors on either side of an item, as
    /// indices into the item list the search ran over.
    struct ReturnAnchors: Equatable {
        /// The neighbor to the right, preferred as the anchor.
        let successor: Int?
        /// The neighbor to the left, used when there is no successor.
        let predecessor: Int?
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
    /// sourcePID resolution succeeded. recentWindowIDs widens that
    /// same test over the last several cycles so one degraded
    /// enumeration cannot make an established item look new.
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
    /// Order is: visible items, hidden control item, hidden items, always-
    /// hidden control item (when present), always-hidden items. The visible
    /// control item is already part of the visible array (it is not filtered
    /// out upstream the way the hidden and always-hidden control items are), so
    /// it is not reinserted here.
    ///
    /// Pure over its inputs. Shared by applyProfileLayout and the log-replay
    /// harness so both build currentFlat identically.
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
    /// Unresolved generic Control Center items (uniqueIdentifiers passed in
    /// unresolvedGenericCCUIDs) are also excluded. These are widgets macOS
    /// hosts under Control Center that Thaw cannot yet attribute to their
    /// owning app (e.g. Little Snitch's agent before its marker window
    /// appears): they fall back to the com.apple.controlcenter namespace,
    /// never match a profile entry, and would otherwise be relocated as
    /// unmanaged arrivals on every cycle. Leaving them in place until they
    /// resolve was the fix for the field-reported "Little Snitch keeps moving"
    /// bug. The caller computes the set from items whose tag is a Control
    /// Center generic item and whose sourcePID is nil.
    ///
    /// Input order is preserved, since downstream consumers (LCS
    /// planner) treat the result as the iteration order for placement.
    /// Pure over its inputs.
    static nonisolated func partitionUnmanagedUIDs(
        currentFlat: [String],
        desiredUIDs: Set<String>,
        hiddenCtrlUID: String?,
        ahCtrlUID: String?,
        visibleCtrlUID: String?,
        provisionalIdentityUIDs: Set<String>
    ) -> [String] {
        currentFlat.filter { uid in
            !desiredUIDs.contains(uid)
                && uid != hiddenCtrlUID
                && uid != ahCtrlUID
                && uid != visibleCtrlUID
                && !provisionalIdentityUIDs.contains(uid)
        }
    }

    static nonisolated func provisionalIdentityUIDs(items: [MenuBarItem]) -> Set<String> {
        Set(items.filter(\.hasProvisionalIdentity).map(\.uniqueIdentifier))
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
    /// Items sitting left of the hidden divider, ordered so `first` is a
    /// stable choice. The Thaw icon is a control item but must always be
    /// visible, so it is admitted here.
    private static nonisolated func leftmostItems(
        items: [MenuBarItem],
        hiddenBounds: CGRect
    ) -> [MenuBarItem] {
        let candidates = items
            .filter { item in
                // Generic Control Center placeholders are not draggable, but
                // the planner must still see them so the unresolved-sourcePID
                // safety path can defer relocation without acting on an
                // unstable identifier.
                let isUnresolvedControlCenterPlaceholder =
                    item.tag.isControlCenterGenericItem && item.sourcePID == nil

                return item.bounds.maxX <= hiddenBounds.minX &&
                    (item.isMovable || isUnresolvedControlCenterPlaceholder) &&
                    (!item.isControlItem || item.tag == .visibleControlItem)
            }
        // Tie-broken: `first` on this list picks the item to relocate, so a
        // minX tie during reflow must not hand the decision to a different
        // item on an otherwise identical pass.
        return MenuBarItem.sortByLeadingEdgeThenIdentifier(candidates)
    }

    /// The Thaw-icon relocation decision on its own, for callers that must
    /// act before the rest of ``planLeftmostMove``'s inputs are trustworthy.
    ///
    /// This decision reads only geometry and our own control item's tag,
    /// both of which are correct from the first cache pass. The other paths
    /// classify third-party items by namespace, which is why they have to
    /// wait for source PIDs to resolve.
    static nonisolated func planThawIconMove(
        items: [MenuBarItem],
        hiddenBounds: CGRect
    ) -> MenuBarItem? {
        leftmostItems(items: items, hiddenBounds: hiddenBounds)
            .first { $0.tag == .visibleControlItem }
    }

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
        // Continuity is judged over several cycles, not just the previous one.
        // A single degraded enumeration — a Space switch, a partially
        // published window list — drops an item's windowID from the previous
        // cycle, and the item then reads as brand new on the cycle after
        // (#849). `recentWindowIDs` carries the windowIDs seen across the last
        // several cycles so those gaps can't manufacture a new item.
        let previousIDs = Set(observation.previousWindowIDs)
            .union(observation.recentWindowIDs)

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
                // Also file the saved entry under its canonical form. Owners
                // that title their items after a live metric were persisted
                // under whatever value was on screen at save time, which no
                // longer matches the item today; without this the item looks
                // like it has no saved section and gets relocated as new.
                // Additive, so identifiers persisted before canonicalization
                // existed keep matching under their raw key too.
                let canonical = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
                if canonical != identifier {
                    savedSectionForIdentifier[canonical] = section
                }
            }
        }

        // Namespace-level fallback for owners whose item title is not stable.
        // The same physical status item is tagged `<bundleID>:Item-0` while
        // macOS still hosts it as a generic Control Center slot, and
        // `<bundleID>:<the owner's own window title>` once sourcePID
        // resolution renames it. A saved entry filed under one form misses
        // the other, so the item looks like it has no saved section and gets
        // relocated as new — which is how an item the user put in Always
        // Hidden gets dragged back out (#849).
        //
        // Only consulted where it cannot be ambiguous: the owner must have
        // exactly one saved entry and exactly one live item, so there is only
        // one item the saved entry could refer to. Like the canonical-form
        // lookup above, this can only ever conclude that an item *does* have
        // a saved section, so it suppresses relocations and never causes one.
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

            // Items with a saved section belong to restoreItemsToSaved-
            // Sections, not to the new-item relocation path.
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

    // MARK: - Geometry readiness

    /// Whether the menu bar geometry is settled enough to run a layout pass on
    /// a notched display.
    ///
    /// `rightBoundary` is Control Center's left edge (or the screen's right edge
    /// when Control Center is absent), the same value the notch-overflow budget
    /// is derived from. A finite value to the right of the notch's right edge is
    /// a valid layout anchor. A value at or left of the notch (or non-finite)
    /// means Control Center was reported at a stale off-screen position, which
    /// happens transiently during a display reconnect or Control Center widget
    /// churn. Running the placement and move logic against that geometry
    /// mis-positions the control items (the Thaw visible icon jumps to the far
    /// left), so the pass must be deferred until the geometry settles.
    static nonisolated func isMenuBarGeometryReady(
        rightBoundary: CGFloat,
        notchMaxX: CGFloat
    ) -> Bool {
        rightBoundary.isFinite && rightBoundary > notchMaxX
    }

    /// Whether the notch-overflow rebalance should run for the current active
    /// menu bar display.
    ///
    /// Overflow ejection is only meaningful on the display the user's persistent
    /// layout is anchored to — the *main* menu bar display. When a notched
    /// display is merely a secondary (e.g. a MacBook whose built-in screen sits
    /// next to a non-notched external that is the main display), macOS relocates
    /// the status items onto the built-in's menu bar only while it transiently
    /// holds focus. Computing the narrow beside-notch budget there ejects
    /// profile items that fit fine on the main display, and they stay stranded
    /// in hidden once focus returns to the main screen. So overflow runs only
    /// when the active notched display is also the main display; on a notched
    /// secondary the saved layout is honoured verbatim.
    ///
    /// `activeScreenKnown` is whether `NSScreen.screenWithActiveMenuBar`
    /// actually resolved a screen. When it is `false` (e.g. mid
    /// display-reconfiguration) the gate fails closed: guessing a screen —
    /// such as falling back to `NSScreen.main` — risks computing the budget
    /// against a display the layout is not anchored to, which is the same
    /// mis-budget failure this gate exists to prevent.
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
    /// Each center is matched to the screen frame that contains it. Frames and
    /// centers are expected in the global CoreGraphics coordinate space
    /// (top-left origin), so a secondary display above the main one has a
    /// negative y origin. When the centers resolve to more than one distinct
    /// screen the active menu bar is relocating between displays: macOS
    /// migrates the status item windows asynchronously, so for a window of time
    /// some items sit on the old screen and some on the new one. A bulk apply
    /// dispatched then resolves each move against a different display and
    /// cannot converge, leaving items stranded where they read as un-hidden; a
    /// section order persisted then bakes that transition artifact into the
    /// saved layout. Every caller defers until the items collapse back onto a
    /// single display.
    ///
    /// Callers must pass only unparked items. Parked hidden and always-hidden
    /// items are shoved left of the menu bar and land at arbitrary negative x,
    /// which is a real display's coordinate space whenever the user has a
    /// screen positioned to the left of the main one. Feeding those centers in
    /// makes the predicate report a spread on a perfectly settled layout, and
    /// it never recovers: the persist gate then blocks every write to
    /// savedSectionOrder for as long as that arrangement is connected. Centers
    /// that land on no screen are still ignored, but that is a fallback, not
    /// the filter; do not rely on it to exclude parked items.
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

    /// Whether the given item bounds currently fall on any of the provided
    /// screen frames. An item parked off-screen by the control item's
    /// collapse — shoved thousands of points left of the display — does
    /// not, and using it as a drag anchor makes the move fail every retry:
    /// AppKit snaps the item back to its autosave position on mouse-up,
    /// so the divider flickers on-screen then springs back once per attempt
    /// for the full retry budget (#881: cursor seizure and icon storm).
    ///
    /// Measured at the leading edge, not the center. A collapsed hidden
    /// divider is 5000 points wide — that width is how the section conceals
    /// the items to its left — so its center sits 2500 points right of the
    /// divider itself. In #958 the divider was parked at minX -3871 with a
    /// center at -1371, which on a three-display arrangement with a display
    /// left of the origin lands squarely on a screen. The guard that was
    /// meant to refuse a drag from a parked divider read that center, saw a
    /// screen, and let the drag through. Every ordinary item is narrow
    /// enough that the two measurements agree.
    ///
    /// Pure over its inputs.
    static nonisolated func isOnScreen(bounds: CGRect, screenFrames: [CGRect]) -> Bool {
        let leadingEdge = CGPoint(x: bounds.minX, y: bounds.midY)
        return screenFrames.contains { $0.contains(leadingEdge) }
    }

    /// Whether an item lies entirely off every display.
    ///
    /// ``isOnScreen`` tests only the leading edge, which is the right test
    /// for drag anchors but the wrong one for deciding that a *divider* is
    /// stranded (#978). Hiding a section expands its control item into a
    /// spacer (`Lengths.expanded`) whose frame reaches far offscreen to the
    /// left while its trailing edge stays anchored beside the visible
    /// section, so every healthy collapsed bar fails the leading-edge test.
    /// Only a divider displaced past all of its items — no edge on any
    /// screen — is one the parked-divider recovery may rebuild.
    static nonisolated func isFullyOffScreen(bounds: CGRect, screenFrames: [CGRect]) -> Bool {
        !screenFrames.contains { $0.intersects(bounds) }
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
    static nonisolated func planNotchOverflow(
        desiredFiltered: [String],
        unmanagedUIDs: [String],
        controlUIDs: ControlUIDs,
        sectionMap: [String: String],
        uidWidths: [String: CGFloat],
        availableWidth: CGFloat
    ) -> NotchOverflowResult {
        // Guard against invalid / not-yet-settled geometry. A non-positive or
        // non-finite budget means the menu bar layout could not be measured:
        // during a display disconnect/reconnect Control Center transiently
        // reports a stale off-screen left edge, which drives rightBoundary and
        // therefore availableWidth negative. On such a budget the eject logic
        // below would treat every visible item as overflow and dump the whole
        // section into hidden, corrupting the layout (and the persisted saved
        // order). Never act on a budget we cannot trust: return no overflow and
        // leave the layout untouched until the geometry settles.
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
        if let ahUID = controlUIDs.alwaysHidden {
            controlSet.insert(ahUID)
        }

        let hiddenIndex = desiredFiltered.firstIndex(of: controlUIDs.hidden)
        let alwaysHiddenIndex = controlUIDs.alwaysHidden
            .flatMap { desiredFiltered.firstIndex(of: $0) }

        let hiddenStart = hiddenIndex.map { $0 + 1 } ?? desiredFiltered.endIndex
        let hiddenEnd = alwaysHiddenIndex ?? desiredFiltered.endIndex

        // The control items can transiently appear out of order (see
        // MenuBarItemManager.enforceControlItemOrder), and the hidden control
        // can be missing entirely during a display reconnect. Either case makes
        // the hidden-section slice below an invalid range, which would trap.
        // A layout we cannot describe is one we must not rewrite: leave the
        // inputs untouched until the ordering settles.
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
        // Keep the visible items in their saved order and drop only the
        // overflowed ones. The visible control item is never in overflowSet, so
        // filtering preserves its saved position instead of forcing it to the
        // front of the visible section. Prepending the chevron relocated the
        // always-visible Thaw icon to the leftmost slot on every overflow even
        // though it was never the item that overflowed.
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
    /// Phase 1's hidden↔always-hidden arithmetic cannot see these: both of
    /// its tallies intersect against the currently-occupied hidden and
    /// always-hidden sets, so a bar whose divider has drifted past every
    /// managed item (leaving both sets empty) reports zero mismatch. The
    /// LCS pass cannot see them either — it receives sequences with the
    /// dividers stripped, so a divergence that is purely a divider
    /// position leaves current equal to desired and plans no moves (#879).
    ///
    /// A non-zero count means one divider move fixes every listed item at
    /// once, which is why this is measured separately from the per-item
    /// reorder the LCS plans.
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
    /// The tally decides that a repair is needed; this decides what the
    /// repair moves. Deriving one from the other keeps a caller that fixes
    /// the boundary item-by-item from disagreeing with the count that sent
    /// it there.
    struct HiddenBoundaryOffenders: Equatable {
        /// Currently visible, wanted in hidden or always-hidden. These
        /// travel to the divider's concealed side.
        var wronglyVisible: Set<String>
        /// Currently concealed, wanted in visible. These travel to its
        /// visible side.
        var wronglyConcealed: Set<String>

        var count: Int { wronglyVisible.count + wronglyConcealed.count }

        var isEmpty: Bool {
            wronglyVisible.isEmpty && wronglyConcealed.isEmpty
        }
    }

    /// Splits the boundary mismatch into the two directions of travel.
    ///
    /// `overflowExemptUIDs` carries the notch-overflow eject set
    /// (`notchOverflowEjectedUIDs`). An ejected item sits in hidden while
    /// the profile still lists it visible — that divergence is by design,
    /// the same rule `currentLayoutDivergesFromSaved` applies through its
    /// own overflow exemption. Counting it here makes Phase 1 recall the
    /// item to visible every apply and the next cycle's overflow plan
    /// eject it again: a two-drag oscillation for as long as the bar stays
    /// over budget (#958's 20 August log, nk-tedo-001). The exemption only
    /// covers an item actually sitting in hidden; one that drifted into
    /// always-hidden is genuine drift and keeps counting.
    ///
    /// Pure over its inputs.
    static nonisolated func hiddenBoundaryOffenders(
        currentVisible: Set<String>,
        currentHidden: Set<String>,
        currentAlwaysHidden: Set<String>,
        desiredVisible: Set<String>,
        desiredHidden: Set<String>,
        desiredAlwaysHidden: Set<String>,
        overflowExemptUIDs: Set<String> = []
    ) -> HiddenBoundaryOffenders {
        // Everything the profile places left of the hidden divider, in
        // either of the two concealed sections. Which of the two an item
        // lands in is the always-hidden divider's problem, handled by the
        // AH_ctrl planning that follows this check.
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
    /// Dragging H_ctrl re-sections every item it crosses. The cost is the
    /// whole bar and the benefit is one drag, so the trade is only worth
    /// taking when the divider itself is what drifted rather than the
    /// items. That shows up as a side with nothing live left on it:
    ///
    /// - Nothing concealed is #879, where the divider had drifted past
    ///   every managed item and eighteen of eighteen read visible. Moving
    ///   them one at a time would mean eighteen drags across a boundary
    ///   that is in the wrong place anyway.
    /// - Nothing visible is the collapse in #958, where the whole bar has
    ///   ended up behind the divider. The drag is the recovery.
    ///
    /// Anything in between means the divider is roughly where it belongs
    /// and some items have wandered across it. #958's 21 August log is the
    /// case that settles the trade: one item on the wrong side, nine still
    /// correctly concealed, and the drag planned to reach that one item
    /// would have carried H_ctrl from minX -3871 to 1648, across the
    /// entire visible section.
    ///
    /// Counts exclude the control items. The chevron is always on the
    /// visible side of H_ctrl, so counting it would keep `liveVisibleCount`
    /// above zero on precisely the collapsed bar the second case exists to
    /// rescue.
    ///
    /// Pure over its inputs.
    static nonisolated func shouldMoveHiddenDivider(
        liveConcealedCount: Int,
        liveVisibleCount: Int
    ) -> Bool {
        liveConcealedCount == 0 || liveVisibleCount == 0
    }

    /// Plans where to drag the hidden divider so the visible/hidden split
    /// matches the profile.
    ///
    /// Section order runs right-to-left: index 0 of each ordered section
    /// is its rightmost item, and items live to one side of their own
    /// divider (visible right of the hidden divider, hidden left of it).
    /// The divider therefore belongs immediately right of the rightmost
    /// item the profile assigns to hidden, which is the same gap as
    /// immediately left of the leftmost item it assigns to visible.
    ///
    /// Anchors to the hidden side first because that side is what the
    /// profile is trying to repopulate; falls back to the visible side
    /// when the profile's hidden section has no live members, so a
    /// profile that empties the hidden section still parks the divider
    /// past every visible item instead of leaving it mid-bar.
    ///
    /// An anchor in `unanchorableUIDs` yields nil rather than a search
    /// that continues past it. The anchor names the gap the divider
    /// belongs in, so the next candidate along is an item the profile
    /// wants on the *other* side of that gap; anchoring there would drag
    /// the divider past an item instead of up to it.
    ///
    /// Thaw's own control items are what reaches that test. The caller's
    /// candidate set is already filtered to items that are movable and on
    /// screen, and the chevron satisfies both whatever the rest of the bar
    /// is doing — which makes it the anchor of last resort in exactly the
    /// passes where every real item on its side has been dragged off the
    /// bar and filtered out. #958's reporter restored a known-good plist
    /// with Thaw quit and watched the first apply after relaunch collapse
    /// it again: eleven items the profile assigns to visible were sitting
    /// parked on the hidden side, nothing else visible was live, and the
    /// fallback returned the chevron. Dragging H_ctrl up to it swept the
    /// rest of the section across with it.
    ///
    /// Returning nil leaves the boundary where it is and hands the work to
    /// the per-item LCS pass, which moves the items back to the divider.
    /// That is the direction that restores the profile; this move is the
    /// direction that destroys it.
    ///
    /// Pure over its inputs. Returns nil when neither section has a live
    /// movable member to anchor against.
    static nonisolated func planHiddenDividerAnchor(
        desiredHidden: [String],
        desiredVisible: [String],
        liveMovableUIDs: Set<String>,
        unanchorableUIDs: Set<String> = []
    ) -> HiddenDividerAnchor? {
        // One selection rule, shared with hiddenDividerAnchorCandidate so a
        // caller logging the refused candidate can never name an item other
        // than the one this planner considered.
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
    /// picks before the unanchorable test, so the caller's log line can say
    /// which item was refused instead of reporting a bar with nothing live
    /// as the same event.
    ///
    /// The two nil cases need telling apart in the field: one says the
    /// profile's items are not on the bar right now, the other says they
    /// are on the wrong side of it and the divider must not chase them.
    ///
    /// Pure over its inputs.
    static nonisolated func hiddenDividerAnchorCandidate(
        desiredHidden: [String],
        desiredVisible: [String],
        liveMovableUIDs: Set<String>
    ) -> String? {
        desiredHidden.first(where: liveMovableUIDs.contains)
            ?? desiredVisible.last(where: liveMovableUIDs.contains)
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
    /// Rewrites the desired sequence so that, inside concealed sections,
    /// items keep the relative order they already have.
    ///
    /// A move costs the same whether or not anyone can see its result: the
    /// cursor is hijacked, the drag is synthesised, the landing is polled.
    /// Spending that on the order of two items parked thousands of points
    /// off-screen buys nothing a user can perceive — the hidden and
    /// always-hidden sections are revealed through the Thaw Bar, which
    /// renders from the cache rather than from where the windows sit.
    ///
    /// Membership is still enforced. Only the ordering *within* a relaxed
    /// section is surrendered: an item that must cross into hidden is
    /// absent from hidden's current run, so it still plans a move; an item
    /// already in hidden but "out of order" no longer does. Feeding the
    /// result to ``planLCSMoveSequence(currentNoControls:desiredNoControls:sectionMap:)``
    /// is what drops those moves — the LCS now finds those items already
    /// in place.
    ///
    /// Positions are preserved, contents are permuted: the rewrite emits a
    /// relaxed item wherever the desired sequence had one, so a caller that
    /// interleaves sections still gets a well-formed sequence back. Items
    /// with no live counterpart sort last within their section (stably, in
    /// desired order), because an item that is not in the current run has
    /// to be moved regardless of what this relaxation says.
    ///
    /// Pure over its inputs.
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

        // Per relaxed section, the desired members re-sorted into the order
        // they currently sit in. Sorting on (rank, desiredIndex) keeps the
        // comparison total, so the sort is deterministic without relying on
        // Swift's `sort` being stable.
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

            // Scan forward for a stable anchor in the same section.
            //
            // Skips anchors the caller marked unanchorable — Thaw's own
            // section dividers. They stay in the sequence because their
            // position is part of the layout, but a move that anchors on one
            // and fails pushes it: the bar lays out right to left, so an
            // insertion on the wrong side shoves the anchor further left, and
            // the next attempt shoves it again. Walking a divider that way is
            // what ends in a zero-width hidden section (#924, #927). A
            // neighbouring app item is an equally good insertion point and
            // costs nothing when it goes wrong.
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

    /// Looks up the saved position for the given identifier by exact match.
    ///
    /// Returns the section and index in that section's saved array if the
    /// identifier matches an entry. Returns nil if not found.
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
    /// Multi-instance apps may receive a different :N suffix on relaunch
    /// (instance indices are reassigned by windowID sort order after each
    /// assignStableInstanceIndices pass). This variant first tries an
    /// exact-identifier match, then a baseID-prefix match against any
    /// instance saved for the same namespace:title. Returns the first
    /// baseID match found.
    static nonisolated func savedPositionByBaseID(
        for uid: String,
        in savedSectionOrder: [String: [String]]
    ) -> SavedPosition? {
        if let exact = savedPosition(for: uid, in: savedSectionOrder) {
            return exact
        }

        // Canonical match, before the base-ID fallback below.
        //
        // A volatile-title owner is saved under whatever its title was at the
        // time and carries a different one now, so the exact match above
        // always misses. The base-ID fallback misses too: for these owners the
        // title *is* the volatile part, so `namespace:title` differs between
        // the saved entry and the live item just as the full identifier does.
        // Without this the item reaches planUnmanagedPlacement with no saved
        // position and is placed by newItemDefault instead of where the user
        // put it (#815).
        //
        // Instance index is preserved by canonicalization, so two items from
        // the same opaque owner still resolve to their own saved entries.
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
    /// Unmanaged items are items present in the live menu bar but not
    /// covered by the profile spec. Today's behavior parks them all at
    /// visible-leftmost; this planner replaces that hardcoded choice
    /// with the user's actual layout history.
    ///
    /// Pure over its inputs.
    static nonisolated func planUnmanagedPlacement(
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
    static nonisolated func anchorDestination(
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

    /// Finds the nearest eligible neighbors on either side of the item at
    /// `index`.
    ///
    /// Used to anchor a temporarily shown item when it is returned to its
    /// section. Callers decide eligibility; only neighbors that share the
    /// item's section qualify, because anchoring against an item from
    /// another section returns the item into *that* section instead.
    ///
    /// Forward-first for the same reason as
    /// ``anchorDestination(forSavedIndex:inSection:savedSequence:currentUIDsInSection:)``:
    /// the successor's position is the more reliable signal of where the
    /// item belongs.
    ///
    /// Pure over its inputs.
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
    static nonisolated func planSectionOrder(
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
            let base = baseID(forIdentifier: savedUID)
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
    static nonisolated func baseID(forIdentifier id: String) -> String {
        id.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
    }

    /// Extracts the namespace prefix from a uniqueIdentifier.
    ///
    /// Every namespace form renders without a colon — a bundle ID, a UUID
    /// string, or the literal `null` — so the first component is the whole
    /// namespace.
    private static nonisolated func namespace(forIdentifier id: String) -> String {
        String(id.prefix { $0 != ":" })
    }

    // MARK: - Saved-order pruning

    /// The title portion of a `namespace:title` identifier, with any trailing
    /// `:<digits>` instance index left attached — two entries only count as
    /// the same item if their instance indexes match too.
    private static nonisolated func titlePortion(forIdentifier id: String) -> String {
        guard let separator = id.firstIndex(of: ":") else { return "" }
        return String(id[id.index(after: separator)...])
    }

    /// Rewrites a persisted identifier so its namespace matches what a live
    /// item now reports.
    ///
    /// ``MenuBarItemTag/Namespace/canonicalBundleID(_:)`` renames items
    /// hosted by a nested helper after the app the user installed. That
    /// changes `uniqueIdentifier`, so an entry persisted before the rename
    /// — `at.obdev.littlesnitch.agent:Item-0` — can no longer match the
    /// live item, which now reports `at.obdev.littlesnitch:Item-0`. Left
    /// alone it is pruned as unmatchable and the item loses its saved
    /// position; worse, Little Snitch is precisely the item whose saved
    /// position users already struggle to keep (#372, #575, #643, #651,
    /// #709), so silently orphaning it would land on the least forgiving
    /// case in the tracker.
    ///
    /// Only the namespace is touched. The title and any instance index are
    /// carried through verbatim, so this cannot merge two distinct items
    /// or reorder anything.
    ///
    /// Pure over its inputs, and the identity function for the
    /// overwhelming majority of identifiers.
    static nonisolated func canonicalIdentifier(_ identifier: String) -> String {
        let namespaceValue = namespace(forIdentifier: identifier)
        let canonical = MenuBarItemTag.Namespace.canonicalBundleID(namespaceValue)
        guard canonical != namespaceValue else { return identifier }
        guard identifier.firstIndex(of: ":") != nil else { return canonical }
        return "\(canonical):\(titlePortion(forIdentifier: identifier))"
    }

    /// Applies ``canonicalIdentifier(_:)`` across a saved section order.
    ///
    /// Runs before pruning at load, so an entry that only looks unmatchable
    /// because of the rename is migrated rather than discarded. Order is
    /// preserved — entries are rewritten in place, never rearranged.
    ///
    /// Pure over its inputs.
    static nonisolated func canonicalizedSectionOrder(
        _ savedSectionOrder: [String: [String]]
    ) -> [String: [String]] {
        savedSectionOrder.mapValues { identifiers in
            identifiers.map(canonicalIdentifier)
        }
    }

    /// Whether an identifier carries no title at all.
    ///
    /// ``MenuBarItem/uniqueIdentifier`` is `namespace:title` — or
    /// `namespace:title:index` past the first instance — and it does not omit
    /// an empty title the way ``MenuBarItemTag/description`` does. An item
    /// whose title could not be read therefore persists as
    /// `com.apple.controlcenter:` or `com.apple.controlcenter::1`.
    /// Whether the identifier's namespace is a localized display name
    /// rather than a stable identifier.
    ///
    /// The namespace fallback mints one when an owning app's bundle ID
    /// reads nil mid-launch: the window's owner name is the process
    /// display name, which macOS localizes for system processes — an
    /// en-GB machine writes `Control Centre:Battery` next to the
    /// canonical `com.apple.controlcenter:Battery` (#949). Bundle IDs and
    /// executable names never contain whitespace; display names usually
    /// do, and `aliases` carries the ones that do not — the caller passes
    /// Control Center's current localized name (Kontrollzentrum), which
    /// no heuristic can recognize locale-independently.
    private static nonisolated func isDisplayNameNamespace(
        identifier: String,
        aliases: Set<String>
    ) -> Bool {
        let namespace = namespace(forIdentifier: identifier)
        return namespace.contains(where: \.isWhitespace) || aliases.contains(namespace)
    }

    private static nonisolated func hasEmptyTitle(identifier: String) -> Bool {
        let title = titlePortion(forIdentifier: identifier)
        if title.isEmpty {
            return true
        }
        // All that is left is the instance-index suffix, so the title
        // between the two colons was empty.
        guard title.hasPrefix(":") else { return false }
        let index = title.dropFirst()
        return !index.isEmpty && index.allSatisfy(\.isNumber)
    }

    /// The title portion with any trailing `:<digits>` instance index
    /// removed, for the checks that compare against a fixed title.
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
    /// The only items legitimately persisted under this namespace are the
    /// control items and the spacers, which is the same pair
    /// ``MenuBarItemTag/isControlItem`` recognizes. Anything else is a
    /// misattribution written when source-PID resolution handed a foreign
    /// window our own PID, and it can never match a live item again.
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
    /// `kCGWindowName` occasionally reports an item's title as its owner's
    /// bundle identifier — for the whole bar at once, Thaw's own control
    /// items included. The tag built from that reading is
    /// `com.steipete.codexbar:com.steipete.codexbar`, which carries no more
    /// identity than the namespace alone and does not match the same item's
    /// normal reading (`com.steipete.codexbar:codexbar-claude`). #881's
    /// reporter carried 21 of these and #927's 23, on unrelated machines.
    ///
    /// ``liveIdentitiesAreDegraded(namespaces:titles:)`` keeps new ones out
    /// of the saved order; this clears what earlier builds already wrote.
    ///
    /// Both sides are canonicalized because pruning runs after
    /// ``canonicalizedSectionOrder(_:)``, which rewrites the namespace of a
    /// nested-helper item but carries its title through verbatim — leaving
    /// `at.obdev.littlesnitch:at.obdev.littlesnitch.agent`, whose halves are
    /// no longer literally equal.
    private static nonisolated func isSelfTitledEntry(identifier: String) -> Bool {
        let title = titleWithoutInstanceIndex(titlePortion(forIdentifier: identifier))
        guard !title.isEmpty else { return false }
        return MenuBarItemTag.Namespace.canonicalBundleID(title)
            == MenuBarItemTag.Namespace.canonicalBundleID(namespace(forIdentifier: identifier))
    }

    /// Whether an identifier names a WindowServer clone rather than a real
    /// item.
    ///
    /// ``MenuBarItemTag/isSystemClone`` keeps these out of the cache, but
    /// layouts captured before that gate existed hold one entry per clone —
    /// #927's reporter carried six under a single owner.
    private static nonisolated func isSystemCloneEntry(identifier: String) -> Bool {
        titleWithoutInstanceIndex(titlePortion(forIdentifier: identifier)) == "System Status Item Clone"
    }

    /// The smallest bar the proportional half of
    /// ``liveIdentitiesAreDegraded(_:)`` will judge.
    ///
    /// One app whose window really is named after its own bundle identifier
    /// reaches half of a two- or three-item bar on its own. It cannot reach
    /// half of four.
    private static let minimumDegradationSample = 4

    /// Whether a reading of the bar titled its items after their own owners
    /// rather than after themselves.
    ///
    /// `kCGWindowName` degrades bar-wide: in #881's 12:38 log the live hidden
    /// section came back as `com.rogueamoeba.soundsource:com.rogueamoeba.soundsource`,
    /// `leits.MeetingBar:leits.MeetingBar` and nine more, and two minutes
    /// earlier the same items had read normally. Caching that reading is what
    /// makes the damage self-sustaining: every item looks new, so the whole
    /// bar is persisted under a second set of identifiers, and every
    /// subsequent flip between the two spellings presents a bar's worth of
    /// late arrivals to ``MenuBarItemManager/lateArrivingProfileIdentifiers(items:profileIdentifiers:alreadySortedIdentifiers:)``,
    /// which schedules a re-sort, which posts moves and captures the cursor.
    /// #881's reporter rode that loop to a streak of nine consecutive bulk
    /// applies with unenacted moves.
    ///
    /// Two signals, either of which is enough:
    ///
    /// - **A control item lost its name.** Thaw titles its own items
    ///   `Thaw.ControlItem.*`, so one in our namespace titled with our bundle
    ///   identifier can only be a degraded read. This is also the signal with
    ///   consequences of its own — ``MenuBarItem/init(uncheckedItemWindow:instanceIndex:)``
    ///   recognizes control items by that title prefix, so a degraded reading
    ///   arrives with the dividers missing.
    /// - **Half the bar is self-titled.** Covers the case where our own items
    ///   happen to read correctly, subject to ``minimumDegradationSample``.
    ///
    /// A partial degradation that trips neither signal still reaches the
    /// cache; ``prunedSectionOrder(_:)`` clears those entries at the next
    /// load rather than leaving them to accumulate.
    ///
    /// - Parameter identities: The namespace and title of every non-control
    ///   item in the reading, plus any window that *should* have been a
    ///   control item. Clones and ghost windows are expected to be dropped
    ///   already, so their throwaway titles cannot skew the proportion.
    ///
    /// Pure over its inputs.
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

    /// Removes persisted entries that can no longer match any live item.
    ///
    /// Two fixes so far prevent their own failure from recurring but leave
    /// the damage already written to disk in place. This clears both.
    ///
    /// **Provisional-identity duplicates (#788).** A Control-Center-hosted
    /// item whose source PID fails to resolve is namespaced
    /// `com.apple.controlcenter:<title>`, and older builds persisted that
    /// form. Once resolution works, the same item is saved again under its
    /// real owner, so the layout holds both. The Control Center copy can
    /// never match a live item again — resolution now succeeds — but it is
    /// still planned against on every apply. Dropped only when the identical
    /// title is also present under a real owner, so a genuine Control Center
    /// item is never removed on its own.
    ///
    /// **Volatile-title accumulation (#815).** An owner that titles its item
    /// with live content wrote one entry per sample: iStat Menus one per
    /// metric reading, LyricsX one per lyric. Canonicalization collapses them
    /// to a single key, and the rest are dead weight. This also matters
    /// beyond tidiness — the namespace fallback in
    /// ``planLeftmostRelocation`` only fires when an owner has exactly one
    /// saved entry, so the accumulated history disables the very remedy that
    /// would have prevented the churn.
    ///
    /// **Misattributed own-namespace entries (#927).** Source-PID resolution
    /// occasionally hands a foreign window Thaw's own PID, and the layout then
    /// holds e.g. `com.stonerl.Thaw:WiFi` for an item Control Center owns.
    /// Only the control items and spacers belong under this namespace, so
    /// everything else is dropped.
    ///
    /// **System clones (#927).** WindowServer's `System Status Item Clone`
    /// windows are refused by the cache, but layouts captured before that gate
    /// existed hold one entry per clone.
    ///
    /// **Self-titled entries (#881, #927).** A bar-wide `kCGWindowName`
    /// degradation titles every item with its own owner's bundle identifier,
    /// and the resulting `com.steipete.codexbar:com.steipete.codexbar` never
    /// matches the same item's normal reading. See ``isSelfTitledEntry(identifier:)``.
    ///
    /// Order is preserved: entries are dropped, never rearranged, so pruning
    /// cannot itself permute a section (#885).
    ///
    /// Pure over its inputs.
    static nonisolated func prunedSectionOrder(
        _ savedSectionOrder: [String: [String]],
        displayNameAliases: Set<String> = []
    ) -> [String: [String]] {
        let controlCenter = MenuBarItemTag.Namespace.controlCenter.description

        // Titles claimed by a real owner somewhere in the saved layout.
        //
        // A misattributed entry under our own namespace is not a real owner,
        // and counting it as one is worse than leaving it alone: it makes the
        // provisional-duplicate rule below delete the *genuine* Control Center
        // twin. #927's reporter lost `com.apple.controlcenter:WiFi` that way
        // and kept `com.stonerl.Thaw:WiFi`, so the live WiFi item was planned
        // as unmanaged on every apply.
        var titlesWithRealOwner = Set<String>()
        var controlCenterTitles = Set<String>()
        for identifiers in savedSectionOrder.values {
            for identifier in identifiers {
                if namespace(forIdentifier: identifier) == controlCenter {
                    controlCenterTitles.insert(titlePortion(forIdentifier: identifier))
                    continue
                }
                guard
                    !isForeignEntryUnderOwnNamespace(identifier: identifier),
                    !isSelfTitledEntry(identifier: identifier),
                    // A localized display name is not a real owner either.
                    // Counting `Control Centre:WiFi` as one deletes the
                    // genuine `com.apple.controlcenter:WiFi` below, and the
                    // live WiFi item then plans as unmanaged on every apply —
                    // the same failure #927 documents, through a vector its
                    // guards did not cover (#949).
                    !isDisplayNameNamespace(identifier: identifier, aliases: displayNameAliases)
                else {
                    continue
                }
                titlesWithRealOwner.insert(titlePortion(forIdentifier: identifier))
            }
        }

        // Deduplicate canonical forms across the *whole* saved order, not per
        // section. A volatile-title owner whose item was in visible when one
        // sample was persisted and in hidden when another was leaves two
        // entries that canonicalize to the same key in different sections.
        // Both would survive a per-section pass, and the section lookups built
        // from this order would then resolve that key by whichever section the
        // dictionary happened to iterate last — a nondeterministic answer to
        // "where does this item belong".
        //
        // Visible wins over hidden wins over always-hidden: keeping the item
        // in the most visible section it was ever saved in fails toward the
        // user seeing it, rather than toward it disappearing into a section
        // they have to open.
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
        // Sections outside the known three keep their own entries; they are
        // not part of the precedence order and must not be silently emptied.
        for (sectionKey, identifiers) in savedSectionOrder where keptPerSection[sectionKey] == nil {
            keptPerSection[sectionKey] = Set(identifiers)
        }

        return savedSectionOrder.reduce(into: [String: [String]]()) { result, entry in
            let (sectionKey, identifiers) = entry
            let kept = keptPerSection[sectionKey] ?? []
            var emitted = Set<String>()
            result[sectionKey] = identifiers.filter { identifier in
                let isControlCenterHosted = namespace(forIdentifier: identifier) == controlCenter
                let isProvisionalDuplicate = isControlCenterHosted
                    && titlesWithRealOwner.contains(titlePortion(forIdentifier: identifier))
                if isProvisionalDuplicate {
                    return false
                }
                // A display-name-namespaced ghost is pruned only when its
                // canonical twin exists: the Control Center entry sharing
                // its title, Thaw's own control items by their reserved
                // titles, or a real owner claiming the same non-generic
                // title (`Control Centre:Alcove` next to
                // `com.henrikruscon.Alcove:Alcove`). Generic `Item-N`
                // titles are excluded from the claimed-title rule — every
                // owner has an Item-0 — and a display-name entry with no
                // twin is left alone entirely: it may be the only identity
                // a bundle-ID-less app ever got, and deleting it would
                // lose the user's placement (#949).
                if isDisplayNameNamespace(identifier: identifier, aliases: displayNameAliases) {
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
                // A Control-Center-hosted entry with no title identifies
                // nothing: the only live item it could match is one whose
                // title was equally unreadable, and two of those are
                // indistinguishable apart from an instance index assigned in
                // arrival order. #881's reporter carried four of them —
                // `com.apple.controlcenter:` through `::3` — which the apply
                // planned against on every pass. Left to real owners, where
                // an empty title still feeds planLeftmostRelocation's
                // namespace fallback.
                if isControlCenterHosted, hasEmptyTitle(identifier: identifier) {
                    return false
                }
                // Nothing live will ever carry these names again: the first
                // is a foreign item wearing our namespace, the second a
                // WindowServer clone that the cache already refuses.
                if isForeignEntryUnderOwnNamespace(identifier: identifier) {
                    return false
                }
                if isSystemCloneEntry(identifier: identifier) {
                    return false
                }
                if isSelfTitledEntry(identifier: identifier) {
                    return false
                }
                // `kept` decides which section owns a canonical form; this
                // guards against the same raw identifier being listed twice
                // within one section.
                guard kept.contains(identifier) else { return false }
                return emitted.insert(identifier).inserted
            }
        }
    }

    /// Maps a persisted section key string to its enum value.
    private static nonisolated func sectionName(forPersistedKey key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }

    /// Maps a section to its persisted key string.
    private static nonisolated func sectionKeyFor(_ section: MenuBarSection.Name) -> String {
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
    /// `hasPendingDivergence` blocks the save when `applySavedLayout`
    /// has observed a layout divergence on the current cycle but is
    /// still awaiting confirmation on a second consecutive cycle before
    /// correcting it (#736). During that one-cycle window the live cache
    /// reflects a transient macOS rebuild (e.g. a space switch that
    /// re-exposed hidden items as visible) that has not yet been
    /// restored; persisting it bakes the transient state into the saved
    /// layout. Once `applySavedLayout` confirms and runs its correction
    /// the pending-divergence arm is cleared and the next cache cycle
    /// sees a settled layout safe to persist.
    ///
    /// `hasUnfinishedMoveBatch` blocks the save when the last bulk apply
    /// planned moves it never enacted (#900). What the bar shows then is
    /// neither the arrangement the user chose nor the one macOS had: it
    /// is the arrangement the batch happened to reach before it gave up.
    /// Persisting it overwrites the layout the batch was trying to
    /// restore, so the next pass measures against the partial result and
    /// the bar walks a little further each time instead of converging.
    /// Holding the old order keeps a fixed target for the retry.
    ///
    /// Pure over its inputs so the gate can be characterized without
    /// instantiating MenuBarItemManager. Any future addition to the
    /// gate (new in-flight signal) should extend both this function
    /// and its tests.
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
    /// Bundled rather than passed as nine positional flags. A new
    /// in-flight signal then extends this type instead of every call site,
    /// which is what the note above asks for, and the defaults spell out
    /// the permissive state — the one where persisting is safe — so a call
    /// site only names the signals that deviate from it.
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
        /// The two paths have to agree. `applySavedLayout` holds a five
        /// second cooldown after any move so a wave of relaunching apps
        /// cannot cascade into re-applies; this gate did not, so a cycle
        /// inside the cooldown skipped the restore and took the save,
        /// which is the one ordering that writes an unsettled bar down as
        /// the user's layout. In the #958 log that pairing is a single
        /// millisecond apart, and it moved twelve items out of the
        /// visible section for good.
        var isWithinMoveCooldown = false

        /// Whether the menu bar is on a different display than it was on
        /// the cycle that produced the current cache.
        ///
        /// macOS moves status items to the new screen one at a time, so a
        /// snapshot taken during the relocation reads a bar that is
        /// partly on each. `itemsSpanMultipleDisplays` is meant to catch
        /// exactly that, but it can only see the items still classified
        /// visible — and misclassification is the fault, so by the time
        /// it matters the evidence has already been moved out of its
        /// input. It correctly stopped a save 2.5 minutes earlier in the
        /// #958 log with sixteen visible items, then passed the one that
        /// mattered with four. This signal is derived from the displays
        /// themselves and does not thin out as items are misread.
        var menuBarDisplayChanged = false
    }

    /// Whether the always-hidden section is resolved well enough for the
    /// current cache snapshot to be an order of record.
    ///
    /// The always-hidden divider is the only boundary separating always-
    /// hidden items from hidden ones. When it is missing,
    /// `CacheContext.findSection` has no boundary to test against and
    /// degrades every always-hidden item to `.hidden` — a lossy but
    /// recoverable misreading, until `saveSectionOrder` writes it down and
    /// makes it the user's layout. That is #849: the divider went
    /// unresolved for a single cache cycle and the whole always-hidden
    /// section was persisted as visible.
    ///
    /// A nil divider is only a problem when the section is enabled. Users
    /// who never turned the always-hidden section on have no divider by
    /// design, and must still be able to persist their layout.
    static nonisolated func isAlwaysHiddenSectionResolved(
        hasAlwaysHiddenControlItem: Bool,
        isAlwaysHiddenSectionEnabled: Bool
    ) -> Bool {
        hasAlwaysHiddenControlItem || !isAlwaysHiddenSectionEnabled
    }

    /// Whether the hidden section has physical room between the two
    /// dividers for the items the saved layout puts there.
    ///
    /// The hidden section is the span between the always-hidden divider's
    /// trailing edge and the hidden divider's leading edge. When that span
    /// closes to zero, `CacheContext.findSection` can no longer satisfy the
    /// strict test for `.hidden` (it would need `minX >= ah.maxX` and
    /// `maxX <= hidden.minX` at the same coordinate), so every item falls
    /// through to the midpoint tie-break and the on-screen ones resolve
    /// `.visible`. Persisting that reading moves the user's hidden items
    /// into the visible section for good.
    ///
    /// Observed on a docked topology — external non-notched main display,
    /// notched built-in secondary at negative X — where the gap between the
    /// dividers went from 677pt to 0 across a single launch (#795).
    ///
    /// Two conditions keep this from firing on healthy layouts:
    ///
    /// - Without an always-hidden divider there is no second boundary and
    ///   so no span to close; everything left of the hidden divider is
    ///   `.hidden` by definition.
    /// - A user whose saved layout puts nothing in the hidden section has
    ///   no reason for the dividers to be apart, and must still be able to
    ///   persist. Only a saved layout that *expects* hidden items makes a
    ///   closed span evidence of a misread.
    ///
    /// **The saved count alone deadlocks (#924).** A user who drags every
    /// hidden item into visible leaves the dividers correctly adjacent, but
    /// the saved order still lists the old hidden entries — and it cannot stop
    /// listing them, because this gate is what blocks the write that would
    /// clear them. The gate's own effect preserves its trigger, so Thaw goes
    /// permanently read-only on that bar: no save, and no apply either, since
    /// `applySavedLayout` consults the same answer. Reinstalling does not help;
    /// the frozen order is on disk.
    ///
    /// `liveHiddenItemCount` cannot break the tie by itself, because a
    /// collapse *also* reads as zero live hidden items — that misclassification
    /// is the whole problem (#868). What separates the two is where the items
    /// went. A collapse leaves them parked thousands of points off every
    /// display while the cache calls them visible, which is a position no
    /// genuinely visible item can hold. An emptied section leaves every visible
    /// item on the bar. So an empty live section is trusted only when nothing
    /// the cache calls visible is parked off-screen.
    ///
    /// - Parameters:
    ///   - hiddenControlItemMinX: Leading edge of the hidden divider.
    ///   - alwaysHiddenControlItemMaxX: Trailing edge of the always-hidden
    ///     divider, or `nil` when the section has no divider.
    ///   - savedHiddenItemCount: How many items the saved layout assigns to
    ///     the hidden section.
    ///   - liveHiddenItemCount: How many items the current reading of the bar
    ///     places in the hidden section.
    ///   - hasVisibleItemParkedOffBar: Whether any item the current reading
    ///     calls visible is parked off every display. See
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

    /// Whether any item the current reading calls visible is parked off every
    /// display.
    ///
    /// This is the tell that separates a collapsed hidden section from an
    /// emptied one, and it is only meaningful for items classified `.visible`:
    /// hidden and always-hidden items are parked off-screen whenever their
    /// section is closed, which is ordinary rather than evidence of anything.
    /// An item the cache calls visible has no such excuse — a visible item is
    /// on the bar by definition, so one that is not is a misread.
    ///
    /// With no screen frames to test against the answer is unknowable, and the
    /// conservative answer is the one that preserves the older behaviour: say
    /// the items are parked, leaving the saved-count branch to decide.
    ///
    /// Membership is decided by geometry rather than by asking the cache,
    /// because the callers that need this answer include the apply path, which
    /// is handed a bar directly and has no populated cache to consult. Anything
    /// at or right of the hidden divider is what the visible section holds;
    /// hidden and always-hidden items sit left of it and are excluded, so a
    /// closed always-hidden section full of legitimately parked items does not
    /// read as a fault.
    ///
    /// Pure over its inputs. Off-bar membership is decided by
    /// ``isOnScreen(bounds:screenFrames:)``.
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
    /// The geometric counterpart to the cache's `.hidden` section, for the
    /// callers that have a bar but no cache.
    ///
    /// Pure over its inputs.
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
    static nonisolated func selectWindowForBatchScan<W>(
        windows: [W],
        windowID: (W) -> CGWindowID,
        cachedPIDs: [CGWindowID: pid_t]
    ) -> W? {
        windows.first(where: { window in
            cachedPIDs[windowID(window)] == nil
        })
    }
}
