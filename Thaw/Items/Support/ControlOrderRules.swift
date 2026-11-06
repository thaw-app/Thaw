//
//  ControlOrderRules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import PlatformRuntimeKit

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
    static func dividerIsOffTheBar(_ controlItems: ControlItemPair, among items: [MenuBarItem], displays: [CGRect] = BarAxis.liveDisplayBounds()) -> Bool {
        !CacheDividers.isStandIn(controlItems.hidden)
            && controlItems.hidden.isParkedOffMenuBarBand(among: items, screens: displays)
    }

    /// Why no item can be judged against the Hidden divider's frame, or nil when it can.
    static func dividerMisplacement(
        _ controlItems: ControlItemPair,
        among items: [MenuBarItem],
        displays: [CGRect] = BarAxis.liveDisplayBounds()
    ) -> String? {
        if dividerIsOffTheBar(controlItems, among: items, displays: displays) {
            return "the Hidden divider is parked off the bar"
        }
        if dividerIsRightOfTrailingAnchors(controlItems, among: items, displays: displays) {
            return "the Hidden divider reads right of Control Center or the Clock"
        }
        return nil
    }

    /// Whether the Hidden divider reads right of, or over, Control Center or the Clock on its own bar.
    /// macOS keeps those two last, so this is a frame left over from a display change, and
    /// every item would read as stranded on the hidden side of it.
    static func dividerIsRightOfTrailingAnchors(
        _ controlItems: ControlItemPair,
        among items: [MenuBarItem],
        displays: [CGRect] = BarAxis.liveDisplayBounds()
    ) -> Bool {
        let divider = controlItems.hidden.bounds
        let center = CGPoint(x: divider.midX, y: divider.midY)
        guard !CacheDividers.isStandIn(controlItems.hidden), !divider.isEmpty,
              let bar = displays.first(where: { $0.contains(center) })
        else {
            return false
        }
        return items.contains { item in
            let rank = MenuBarItemTag.anchoredSystemItemRank(item.tag)
            // The rank reads titles only, so a third-party item with one of these titles must not count.
            return (rank == 1 || rank == 2) && item.tag.isSystemItem && item.isOnScreen
                && bar.contains(CGPoint(x: item.bounds.midX, y: item.bounds.midY))
                // Past the anchor's left edge: right of it, or over it, which can't be judged either.
                && divider.maxX > item.bounds.minX
        }
    }

    /// The dividers as a refreshed walk reads them, or nil when the walk lost the Hidden divider.
    static func refreshedControlItems(
        in items: [MenuBarItem],
        hiddenControlItemWindowID: CGWindowID?,
        alwaysHiddenControlItemWindowID: CGWindowID?
    ) -> ControlItemPair? {
        var items = items
        return ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWindowID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
        )
    }

    /// Whether item frames are stated against more than one display's bar.
    ///
    /// macOS 27 draws the item set on every bar, and an app's AX frame names whichever bar
    /// it last laid out on. Frames from different bars share no x axis, so an order read
    /// from them is meaningless. Parked and off-band frames are ignored.
    static func framesSpanSeveralBars(_ items: [MenuBarItem], displays: [CGRect] = BarAxis.liveDisplayBounds()) -> Bool {
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
        // so the trailing item (normally Thaw) stays trailing.
        let leading = newlyForcedVisible.filter { !$0.tag.isSiri }
        guard leading.count < newlyForcedVisible.count else {
            return RuntimeSectionController.anchoredSystemItemsTrail(in: newlyForcedVisible + authoredVisible)
        }
        // Siri is no anchor, so nothing else would move an unsaved one back; it keeps its live slot.
        let byIdentifier = Dictionary(
            liveSegment.map { ($0.uniqueIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let completed = LayoutEditorOrder.completingOrder(
            (leading + authoredVisible).map(\.uniqueIdentifier),
            withLive: liveSegment.map(\.uniqueIdentifier)
        )
        return RuntimeSectionController.anchoredSystemItemsTrail(in: completed.compactMap { byIdentifier[$0] })
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
    /// A drag since the last mirror makes the bar the record, so no order is returned.
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

    /// Reject reversed Control Center/Clock ranks or non-anchors right of the trailing group.
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
