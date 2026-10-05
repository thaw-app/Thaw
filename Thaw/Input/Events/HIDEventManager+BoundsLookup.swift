//
//  HIDEventManager+BoundsLookup.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import MenuBarModel

extension HIDEventManager {
    /// Anything wider is an expanded section divider and is excluded.
    static nonisolated let maxReasonableItemWidth: CGFloat = 500

    /// macOS 27 concealed items can keep phantom AX frames far below the bar;
    /// those must not count as items in hit-testing.
    static nonisolated let maxMenuBarItemMidY: CGFloat = MenuBarItemGeometry.maxOnBarMidY

    /// On macOS 27 synthetic window IDs have no live CG window, so cached AX
    /// bounds are trusted. Item frames are reported against one bar, so each
    /// entry is rebased onto destinationDisplay first (see MirroredBarGeometry).
    static nonisolated func menuBarBoundsLookupContains(
        _ location: CGPoint,
        entries: [(windowID: CGWindowID, bounds: CGRect)],
        destinationDisplay: CGRect?,
        displayBounds: [CGRect],
        trustCachedBoundsWithoutLiveWindowVerification: Bool,
        liveWindowBounds: (CGWindowID) -> CGRect? = { Bridging.getWindowBounds(for: $0) }
    ) -> Bool {
        for entry in entries {
            let bounds = MirroredBarGeometry.frame(
                entry.bounds,
                on: destinationDisplay,
                displayBounds: displayBounds
            )
            guard bounds.contains(location) else { continue }
            if trustCachedBoundsWithoutLiveWindowVerification {
                return true
            }
            if let currentBounds = liveWindowBounds(entry.windowID),
               MirroredBarGeometry.frame(
                   currentBounds,
                   on: destinationDisplay,
                   displayBounds: displayBounds
               ).contains(location)
            {
                return true
            }
        }
        return false
    }

    /// AX can overstate the digital clock's height. Clip both native and
    /// mirrored frames to the destination bar, never the application below it.
    static nonisolated func systemClockItem(
        at location: CGPoint,
        in items: [MenuBarItem],
        menuBarBands: [CGRect]
    ) -> MenuBarItem? {
        guard let targetBand = menuBarBands.first(where: { $0.contains(location) }) else { return nil }
        let clocks = items.filter { $0.isOnScreen && !$0.bounds.isEmpty && isSystemClockItem($0) }
        let template: MenuBarItem
        let bounds: CGRect
        if let direct = clocks.first(where: { $0.bounds.contains(location) }) {
            template = direct
            bounds = direct.bounds.intersection(targetBand)
        } else {
            guard let mirrored = clocks.first(where: { item in
                menuBarBands.contains { $0.intersects(item.bounds) }
            }), let sourceBand = menuBarBands.first(where: { $0.intersects(mirrored.bounds) }) else { return nil }
            template = mirrored
            let rightInset = sourceBand.maxX - mirrored.bounds.maxX
            bounds = CGRect(
                x: targetBand.maxX - rightInset - mirrored.bounds.width,
                y: targetBand.minY,
                width: mirrored.bounds.width,
                height: targetBand.height
            ).intersection(targetBand)
        }
        guard bounds.contains(location) else { return nil }
        return MenuBarItem(
            tag: template.tag,
            windowID: template.windowID,
            ownerPID: template.ownerPID,
            sourcePID: template.sourcePID,
            bounds: bounds,
            title: template.title,
            isOnScreen: true
        )
    }

    static nonisolated func isSystemClockItem(_ item: MenuBarItem) -> Bool {
        item.isNonConcealableSystemItem
            && SystemMenuBarModuleCatalog.isClock(title: item.tag.title)
    }

    static func displayID(
        containing point: CGPoint,
        fallback: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        NSScreen.screen(containingCGPoint: point)?.displayID ?? fallback
    }

    /// Whether an item counts in show-on and tooltip hit-testing. A concealed
    /// hidden item has no glyph and must not swallow a click on the empty bar.
    static nonisolated func shouldIncludeItemInMenuBarBoundsLookup(
        _ item: MenuBarItem,
        section: MenuBarSection.Name?,
        effectivelyConcealed: Set<String> = []
    ) -> Bool {
        guard item.bounds.width > 0, item.bounds.width <= maxReasonableItemWidth else {
            return false
        }
        guard item.bounds.midY <= maxMenuBarItemMidY else {
            return false
        }
        if item.tag.isNativeOverflowControl {
            return false
        }
        guard let section else {
            return true
        }
        if section != .visible, !item.isNonConcealableSystemItem {
            return !effectivelyConcealed.contains(
                MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
            )
        }
        return true
    }

    static nonisolated func menuBarItemBoundsLookupEntries(
        from items: [MenuBarItem],
        excluding knownWindowIDs: Set<CGWindowID>,
        shouldInclude: (MenuBarItem) -> Bool
    ) -> [(windowID: CGWindowID, bounds: CGRect)] {
        var seenWindowIDs = knownWindowIDs
        var entries = [(windowID: CGWindowID, bounds: CGRect)]()

        for item in items where item.isOnScreen && !seenWindowIDs.contains(item.windowID) {
            guard shouldInclude(item) else {
                continue
            }

            entries.append((windowID: item.windowID, bounds: item.bounds))
            seenWindowIDs.insert(item.windowID)
        }

        return entries
    }

    func refreshMenuBarItemBoundsLookup() {
        guard let appState else { return }
        rebuildWindowBoundsLookup(
            from: appState.itemManager.itemCache,
            including: onScreenItems?.items ?? []
        )
    }

    /// Reads the concealed set once per rebuild, not once per item.
    private func boundsLookupInclusionFilter() -> (MenuBarItem) -> Bool {
        guard let controller = appState?.menuBarManager.sectionController else {
            return { Self.shouldIncludeItemInMenuBarBoundsLookup($0, section: nil) }
        }
        let effectivelyConcealed = controller.effectivelyConcealedIdentifiers
        return { item in
            Self.shouldIncludeItemInMenuBarBoundsLookup(
                item,
                section: controller.section(for: item),
                effectivelyConcealed: effectivelyConcealed
            )
        }
    }

    /// Includes unmanaged windows too, so clicks on Clock or Control Center do
    /// not read as empty menu bar space.
    func rebuildWindowBoundsLookup(
        from cache: MenuBarItemManager.ItemCache,
        including recentOnScreenItems: [MenuBarItem] = []
    ) {
        refreshClockMenuBarBands()
        var knownWindowIDs = Set<CGWindowID>()
        var buffer = [(windowID: CGWindowID, bounds: CGRect)]()
        let shouldInclude = boundsLookupInclusionFilter()

        // Live window bounds first, in case the cache is stale.
        let allWindowIDs = Bridging.getMenuBarWindowList(option: [
            .onScreen, .activeSpace, .itemsOnly,
        ])
        for windowID in allWindowIDs {
            if let bounds = Bridging.getWindowBounds(for: windowID) {
                guard bounds.width <= Self.maxReasonableItemWidth else {
                    continue
                }
                buffer.append((windowID: windowID, bounds: bounds))
                knownWindowIDs.insert(windowID)
            }
        }

        let recentEntries = Self.menuBarItemBoundsLookupEntries(
            from: recentOnScreenItems,
            excluding: knownWindowIDs,
            shouldInclude: shouldInclude
        )
        buffer.append(contentsOf: recentEntries)
        knownWindowIDs.formUnion(recentEntries.map(\.windowID))

        let managedEntries = Self.menuBarItemBoundsLookupEntries(
            from: cache.managedItems,
            excluding: knownWindowIDs,
            shouldInclude: shouldInclude
        )
        buffer.append(contentsOf: managedEntries)
        let entries = buffer
        windowBoundsLock.withLock { $0 = entries }
    }

    /// Whether displayID is showing a fullscreen Space.
    static func isShowingFullscreenSpace(_ displayID: CGDirectDisplayID) -> Bool {
        guard let spaceID = Bridging.getCurrentSpaceID(for: displayID) else { return false }
        return Bridging.isSpaceFullscreen(spaceID)
    }

    /// A display showing a fullscreen Space gets no band: the app owns the
    /// top of the screen there, and the clock's last frame would take its clicks.
    func refreshClockMenuBarBands() {
        clockMenuBarBands = NSScreen.screens.compactMap { screen in
            guard !Self.isShowingFullscreenSpace(screen.displayID) else { return nil }
            let bounds = CGDisplayBounds(screen.displayID)
            return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: screen.getMenuBarHeightEstimate())
        }
    }

    /// Show/hide moves items while keeping window IDs, so the cache can be
    /// stale; a Window Server snapshot is used instead. On macOS 27 items have
    /// no CG windows, so the snapshot is empty and the cache is used.
    func rebuildWindowBoundsLookupFromCurrentLayout() {
        guard let appState else {
            windowBoundsLock.withLock { $0 = [] }
            return
        }
        rebuildWindowBoundsLookup(
            from: appState.itemManager.itemCache,
            including: onScreenItems?.items ?? []
        )
    }
}
