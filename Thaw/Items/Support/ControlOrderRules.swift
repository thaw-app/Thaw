//
//  ControlOrderRules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import PlatformRuntimeKit
import ThawLayout

/// What the live bar says about Thaw's own control items, and the order they belong in.
///
/// The three controls bound the sections, so every structural repair first asks whether they
/// stand in order, whether their frames can be trusted, and what sequence to write back.
/// These rules answer from the items alone.
enum ControlOrderRules {
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

    static nonisolated func trailingSiriIsMisplaced(in items: [MenuBarItem], displays: [CGRect] = BarAxis.liveDisplayBounds()) -> Bool {
        let onBar = items.filter {
            $0.isOnScreen && $0.bounds.width >= MenuBarItemGeometry.phantomFramePeerMinimumWidth &&
                !$0.bounds.isEmpty && !$0.bounds.isInfinite &&
                !$0.isParkedOffMenuBarBand(among: items, screens: displays)
        }
        guard let siri = onBar.first(where: { $0.tag == .siri }) else { return false }
        return onBar.contains {
            !$0.tag.isLayoutAnchoredSystemItem && $0.bounds.midX > siri.bounds.midX
        }
    }

    /// The cached items with the dividers from the last walk put back, since the cache drops them.
    /// Nil without a known Hidden divider, as nothing can be put in order then.
    static nonisolated func withDividers(
        _ cached: [MenuBarItem],
        _ dividers: ControlItemPair?
    ) -> (controlItems: ControlItemPair, items: [MenuBarItem])? {
        guard let dividers else { return nil }
        let missing = [dividers.hidden, dividers.alwaysHidden].compactMap(\.self).filter { divider in
            !cached.contains { $0.windowID == divider.windowID }
        }
        return (dividers, cached + missing)
    }

    /// The dividers a reveal's boundary check judges items against. Unless Always Hidden is the
    /// section shown, its divider is collapsed and macOS doesn't seat it where its weight says.
    static nonisolated func boundaryControls(
        _ controlItems: ControlItemPair,
        revealedSection: MenuBarSection.Name
    ) -> ControlItemPair {
        guard revealedSection != .alwaysHidden else { return controlItems }
        return ControlItemPair(hidden: controlItems.hidden, alwaysHidden: nil)
    }

    /// Whether macOS has parked the Hidden divider off the bar, as it does while
    /// a display reconnects. Which side of a parked divider an item reads on is
    /// meaningless, so no order judged against it may be written.
    ///
    /// A stand-in from CacheDividers is never parked: its empty frame only says
    /// that the cache dropped the divider, not where macOS put it.
    static func dividerIsOffTheBar(_ controlItems: ControlItemPair, among items: [MenuBarItem], displays: [CGRect] = MenuBarItemManager.activeDisplayBounds()) -> Bool {
        !CacheDividers.isStandIn(controlItems.hidden)
            && controlItems.hidden.isParkedOffMenuBarBand(among: items, screens: displays)
    }

    /// Whether item frames are stated against more than one display's bar.
    ///
    /// macOS 27 draws the item set on every bar, and an app's AX frame names whichever bar
    /// it last laid out on. Frames from different bars share no x axis, so an order read
    /// from them is meaningless. Parked and off-band frames are ignored.
    static func framesSpanSeveralBars(_ items: [MenuBarItem], displays: [CGRect] = MenuBarItemManager.activeDisplayBounds()) -> Bool {
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

    /// The freshest recorded Visible-section order.
    ///
    /// savedSectionOrder tracks live geometry and pane edits. The controller's
    /// copy misses Command-drags on the real bar, so restoring it would snap
    /// items back to an old order on every reveal.
    ///
    /// The mirror only catches up after the bar has been quiet for a while. A drag that
    /// ended since then has already put the bar in the order the user chose, so the bar is
    /// the record and an empty order lets the structural segment follow the live geometry.
    static func freshestRecordedVisibleOrder(
        mirroredOrder: [String]?,
        controllerOrder: [String]?,
        userDraggedSinceMirror: Bool = false
    ) -> [String] {
        if userDraggedSinceMirror {
            return []
        }
        return mirroredOrder ?? controllerOrder ?? []
    }

    /// Reject reversed Control Center/Clock ranks or non-anchors right of the trailing group; normalization repairs stable Siri stranding.
    /// Skip Thaw controls and sub-phantomFramePeerMinimumWidth slivers (including the intentionally zero-width icon); ranks also cover legacy spellings.
    static nonisolated func anchoredTrailingViolation(
        in sortedLeftToRight: [MenuBarItem],
        displays: [CGRect] = BarAxis.liveDisplayBounds()
    ) -> String? {
        var lastAnchoredRank = Int.min
        var sawAnchored = false
        for item in sortedLeftToRight {
            // A concealed item's parked or phantom frame says nothing about the bar's order.
            guard !item.isControlItem,
                  item.bounds.width >= MenuBarItemGeometry.phantomFramePeerMinimumWidth,
                  !item.isParkedOffMenuBarBand(among: sortedLeftToRight, screens: displays),
                  !item.hasPhantomFrame(among: sortedLeftToRight)
            else {
                continue
            }
            let rank = MenuBarItemTag.anchoredSystemItemRank(item.tag)
            if rank < 3 {
                sawAnchored = true
                guard rank >= lastAnchoredRank else {
                    return "anchored items out of canonical order at \(item.logString)"
                }
                lastAnchoredRank = rank
            } else if sawAnchored {
                return "non-anchored \(item.logString) sits right of the anchored trailing group"
            }
        }
        return nil
    }
}
