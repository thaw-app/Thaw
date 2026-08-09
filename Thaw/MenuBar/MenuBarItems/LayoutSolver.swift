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
    /// negative y origin. Centers that fall on no screen are intentionally
    /// parked off-screen hidden items (the control item shoves them thousands
    /// of points to the left) and are ignored. When the remaining on-screen
    /// items resolve to more than one distinct screen the active menu bar is
    /// relocating between displays: macOS migrates the status item windows
    /// asynchronously, so for a window of time some items sit on the old screen
    /// and some on the new one. A bulk apply dispatched then resolves each
    /// move against a different display and cannot converge, leaving items
    /// stranded where they read as un-hidden; a section order persisted then
    /// bakes that transition artifact into the saved layout. Both callers defer
    /// until the items collapse back onto a single display.
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
    /// Pure over its inputs. Matches the center-on-screen convention used
    /// by ``itemsSpanMultipleDisplays(itemCenters:screenFrames:)``.
    static nonisolated func isOnScreen(bounds: CGRect, screenFrames: [CGRect]) -> Bool {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return screenFrames.contains { $0.contains(center) }
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
        desiredAlwaysHidden: Set<String>
    ) -> Int {
        // Everything the profile places left of the hidden divider, in
        // either of the two concealed sections. Which of the two an item
        // lands in is the always-hidden divider's problem, handled by the
        // AH_ctrl planning that follows this check.
        let desiredConcealed = desiredHidden.union(desiredAlwaysHidden)
        let currentConcealed = currentHidden.union(currentAlwaysHidden)

        let wronglyVisible = currentVisible.intersection(desiredConcealed)
        let wronglyConcealed = currentConcealed.intersection(desiredVisible)

        return wronglyVisible.count + wronglyConcealed.count
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
    /// Pure over its inputs. Returns nil when neither section has a live
    /// movable member to anchor against.
    static nonisolated func planHiddenDividerAnchor(
        desiredHidden: [String],
        desiredVisible: [String],
        liveMovableUIDs: Set<String>
    ) -> HiddenDividerAnchor? {
        if let rightmostHidden = desiredHidden.first(where: liveMovableUIDs.contains) {
            return .rightOf(rightmostHidden)
        }
        if let leftmostVisible = desiredVisible.last(where: liveMovableUIDs.contains) {
            return .leftOf(leftmostVisible)
        }
        return nil
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
    static nonisolated func planLCSMoveSequence(
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
    static nonisolated func longestCommonSubsequence(_ a: [String], _ b: [String]) -> Set<String> {
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
    private static nonisolated func baseID(forIdentifier id: String) -> String {
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
    /// Order is preserved: entries are dropped, never rearranged, so pruning
    /// cannot itself permute a section (#885).
    ///
    /// Pure over its inputs.
    static nonisolated func prunedSectionOrder(
        _ savedSectionOrder: [String: [String]]
    ) -> [String: [String]] {
        let controlCenter = MenuBarItemTag.Namespace.controlCenter.description

        // Titles claimed by a real owner somewhere in the saved layout.
        var titlesWithRealOwner = Set<String>()
        for identifiers in savedSectionOrder.values {
            for identifier in identifiers where namespace(forIdentifier: identifier) != controlCenter {
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
                let isProvisionalDuplicate = namespace(forIdentifier: identifier) == controlCenter
                    && titlesWithRealOwner.contains(titlePortion(forIdentifier: identifier))
                if isProvisionalDuplicate {
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
            !gate.hasUnfinishedMoveBatch
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
    /// - Parameters:
    ///   - hiddenControlItemMinX: Leading edge of the hidden divider.
    ///   - alwaysHiddenControlItemMaxX: Trailing edge of the always-hidden
    ///     divider, or `nil` when the section has no divider.
    ///   - savedHiddenItemCount: How many items the saved layout assigns to
    ///     the hidden section.
    static nonisolated func hiddenSectionHasRoom(
        hiddenControlItemMinX: CGFloat,
        alwaysHiddenControlItemMaxX: CGFloat?,
        savedHiddenItemCount: Int
    ) -> Bool {
        guard let alwaysHiddenControlItemMaxX else {
            return true
        }
        guard savedHiddenItemCount > 0 else {
            return true
        }
        return hiddenControlItemMinX - alwaysHiddenControlItemMaxX > 0
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
